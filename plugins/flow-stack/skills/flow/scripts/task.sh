#!/usr/bin/env bash
# task.sh: manage flow-stack task folders.
#   task.sh new <slug> [playbook]     create .flow/tasks/<slug>/, make it active
#   task.sh active                    print the active slug (empty if none)
#   task.sh dir                       print the active task dir
#   task.sh switch <slug>             make another task active
#   task.sh close                     clear ACTIVE (folder is kept)
#   task.sh list                      tasks with slice progress
#   task.sh slice <id> <status>       set a slice status (todo|doing|done|blocked)
#                                     "done" is gated: red-first, green after the last edit,
#                                     probe TEETH, diff budget (see proofs). Override with
#                                     --force "<reason>" (logged to DECISIONS.tsv).
#   task.sh proofs <id>               show which done-proofs a slice has and lacks
#   task.sh accept <lane>             import a worker lane's EVIDENCE.md into the task
#                                     (delegate, main checkout, after reviewing its branch)
#   task.sh decide <who> <reversible yes|no> <decision> <why> [evidence]
#
# Inside a linked git worktree (a delegate worker's lane) the task folder is the
# main checkout's, read-only: new, switch, close, slice, and accept are refused,
# and proofs read the lane's own evidence and trail (.flow/tasks/<slug>/lanes/<lane>/).
#   task.sh estimate <usd> <ctx_pct> <human_min>
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
templates="$here/../../../templates"
. "$here/../../../hooks/roots.sh"; flow_roots
root="$FLOW_MAIN"
flow="$FLOW_DIR"

die() { echo "task.sh: $*" >&2; exit 1; }
active() { [ -f "$flow/ACTIVE" ] && head -n1 "$flow/ACTIVE" | tr -d '[:space:]' || true; }
active_dir() {
  local s; s="$(active)"
  [ -n "$s" ] && [ -d "$flow/tasks/$s" ] || die "no active task (run: task.sh new <slug>)"
  printf '%s' "$flow/tasks/$s"
}

ensure_repo_files() {
  mkdir -p "$flow/tasks"
  [ -f "$flow/config.json" ] || cp "$templates/config.json" "$flow/config.json"
  local gi="$root/.gitignore"
  for line in ".flow/ACTIVE" ".flow/tasks/" ".flow/trail.jsonl"; do
    grep -qxF "$line" "$gi" 2>/dev/null || printf '%s\n' "$line" >>"$gi"
  done
}

fill() { sed -e "s/{{slug}}/$1/g" -e "s/{{time}}/$(date -u +%FT%TZ)/g" "$2"; }

slice_field() { # slice_field <SLICES.md> <id> <field>
  awk -v id="$2" -v k="$3:" '/^## /{cur=$2} cur==id && index($0,k)==1 {sub("^" k "[[:space:]]*",""); sub(/[[:space:]]+#.*/,""); print; exit}' "$1"
}

# proofs <id>: exit 0 when the slice has every done-proof it owes.
proofs() {
  local id="$1" d s ev trail last_edit ok=0 red teeth budget fence line ts
  [ -n "$id" ] || die "usage: task.sh proofs <id>"
  d="$(active_dir)"; s="$d/SLICES.md"
  local st; st="$(flow_state_dir "$d")"; ev="$st/EVIDENCE.md"; trail="$st/trail.jsonl"
  red="$(slice_field "$s" "$id" red)"; teeth="$(slice_field "$s" "$id" teeth)"
  budget="$(slice_field "$s" "$id" budget)"; fence="$(slice_field "$s" "$id" fence)"
  last_edit="$(jq -r 'select(.tool=="Edit" or .tool=="Write" or .tool=="MultiEdit") | .ts' "$trail" 2>/dev/null | tail -n1 || true)"
  newest() { grep -E "^### [^ ]+ · $1 · $2 " "$ev" 2>/dev/null | tail -n1 | awk '{print $2}' || true; }

  case "$red" in
    n/a*) echo "  – red first: $red" ;;
    *) ts="$(newest "$id:(before|red)" FAIL)"
       if [ -n "$ts" ]; then echo "  ✓ red first: check failed before the change ($ts)"
       else echo "  ✗ red first: no '$id:before' FAIL in EVIDENCE (run the check before building)"; ok=1; fi ;;
  esac
  ts="$(newest "$id" PASS)"
  if [ -z "$ts" ]; then echo "  ✗ green: no '$id' PASS in EVIDENCE"; ok=1
  elif [ -n "$last_edit" ] && [[ "$ts" < "$last_edit" ]]; then echo "  ✗ green: last PASS ($ts) is older than the last edit ($last_edit)"; ok=1
  else echo "  ✓ green: $ts"; fi
  case "$teeth" in
    n/a*) echo "  – teeth: $teeth" ;;
    *) ts="$(newest "probe:$id" TEETH)"
       if [ -z "$ts" ]; then echo "  ✗ teeth: no 'probe:$id' TEETH in EVIDENCE"; ok=1
       elif [ -n "$last_edit" ] && [[ "$ts" < "$last_edit" ]]; then echo "  ✗ teeth: probe ($ts) is older than the last edit"; ok=1
       else echo "  ✓ teeth: $ts"; fi ;;
  esac
  if [ -n "$budget" ]; then
    set -f; line="$("$here/../../loop/scripts/diffstat.sh" $fence | head -n1 || true)"; set +f
    local changed="${line#*changed=}"; changed="${changed%% *}"
    if [ "${changed:-0}" -le "$budget" ]; then echo "  ✓ budget: $line (≤ $budget)"
    else echo "  ✗ budget: $line (> $budget; split the slice or justify with --force)"; ok=1; fi
  fi
  return $ok
}

cmd="${1:-}"; shift || true
case "$cmd" in
  new|switch|close|slice|accept)
    [ -z "$FLOW_LANE" ] || die "'$cmd' is refused in worktree lane '$FLOW_LANE': the task plan is shared. Return your evidence; the delegate accepts it and marks the slice." ;;
esac
case "$cmd" in
  new)
    slug="${1:-}"; [ -n "$slug" ] || die "usage: task.sh new <slug> [playbook]"
    [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "slug must be kebab-case: $slug"
    ensure_repo_files
    d="$flow/tasks/$slug"
    [ -e "$d" ] && die "task exists: $d (use: task.sh switch $slug)"
    mkdir -p "$d"
    fill "$slug" "$templates/INTENT.md" >"$d/INTENT.md"
    fill "$slug" "$templates/SLICES.md" >"$d/SLICES.md"
    cp "$templates/DECISIONS.tsv" "$d/DECISIONS.tsv"
    printf '# Evidence · %s\n<!-- Written only by verify/scripts/evidence.sh. -->\n\n' "$slug" >"$d/EVIDENCE.md"
    printf '%s\n' "${2:-feature}" >"$d/PLAYBOOK"
    printf '%s\n' "$slug" >"$flow/ACTIVE"
    echo "$d"
    ;;
  active) active ;;
  dir) active_dir ;;
  switch)
    [ -d "$flow/tasks/${1:-}" ] || die "no such task: ${1:-}"
    printf '%s\n' "$1" >"$flow/ACTIVE"; echo "active: $1"
    ;;
  close) rm -f "$flow/ACTIVE"; echo "no active task" ;;
  list)
    a="$(active)"
    for d in "$flow"/tasks/*/; do
      [ -d "$d" ] || continue
      s="$(basename "$d")"
      total="$(grep -c '^status:' "$d/SLICES.md" 2>/dev/null || true)"
      done_n="$(grep -c '^status: done' "$d/SLICES.md" 2>/dev/null || true)"
      printf '%s %s  %s/%s slices  %s\n' "$([ "$s" = "$a" ] && echo '*' || echo ' ')" "$s" "${done_n:-0}" "${total:-0}" "$(cat "$d/PLAYBOOK" 2>/dev/null || echo '?')"
    done
    ;;
  proofs)
    proofs "${1:-}" ;;
  slice)
    id="${1:-}"; st="${2:-}"
    [[ "$st" =~ ^(todo|doing|done|blocked)$ ]] || die "usage: task.sh slice <id> <todo|doing|done|blocked> [--force \"<reason>\"]"
    f="$(active_dir)/SLICES.md"
    grep -q "^## $id " "$f" || die "no slice $id in $f"
    if [ "$st" = done ]; then
      if [ "${3:-}" = --force ]; then
        [ -n "${4:-}" ] || die "--force needs a reason"
        "$0" decide agent yes "slice $id marked done without full proofs" "$4" "$(proofs "$id" | tr '\n' ' ')" >/dev/null
        echo "forced: logged to DECISIONS.tsv"
      elif ! proofs "$id"; then
        die "slice $id is not proven done (see above). Produce the missing proofs, or: task.sh slice $id done --force \"<reason>\""
      fi
    fi
    tmp="$(mktemp)"
    awk -v id="$id" -v st="$st" '
      /^## / { cur = $2 }
      /^status:/ {
        if (cur == id) { print "status: " st; next }
        if (st == "doing" && $2 == "doing") { print "status: todo"; next }
      }
      { print }' "$f" >"$tmp" && mv "$tmp" "$f"
    echo "$id → $st"
    ;;
  accept)
    lane="${1:-}"; [ -n "$lane" ] || die "usage: task.sh accept <lane>"
    lev="$(active_dir)/lanes/$lane/EVIDENCE.md"
    [ -f "$lev" ] || die "no evidence in lane '$lane' ($lev)"
    { printf '<!-- accepted from lane %s at %s -->\n' "$lane" "$(date -u +%FT%TZ)"; cat "$lev"; } >>"$(active_dir)/EVIDENCE.md"
    echo "accepted: $(grep -c '^### ' "$lev") evidence block(s) from lane $lane"
    ;;
  decide)
    [ $# -ge 4 ] || die "usage: task.sh decide <who> <yes|no> <decision> <why> [evidence]"
    clean() { printf '%s' "$1" | tr '\t\n' '  '; }
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$(clean "$1")" "$(clean "$3")" "$(clean "$4")" "$(clean "${5:-}")" "$2" \
      >>"$(active_dir)/DECISIONS.tsv"
    echo "logged"
    ;;
  estimate)
    [ $# -eq 3 ] || die "usage: task.sh estimate <usd> <ctx_pct> <human_min>"
    printf 'usd=%s ctx_pct=%s human_min=%s at=%s\n' "$1" "$2" "$3" "$(date -u +%FT%TZ)" >"$(active_dir)/ESTIMATE"
    echo "estimate saved"
    ;;
  -h|--help|"") sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command: $cmd (try -h)" ;;
esac
