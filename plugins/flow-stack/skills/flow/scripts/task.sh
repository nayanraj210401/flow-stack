#!/usr/bin/env bash
# task.sh: manage flow-stack task folders.
#   task.sh new <slug> [playbook] --goal "<outcome>" --check "<cmd>" [--workspace <name> | --repos <a,b,...>]
#                                     create .flow/tasks/<slug>/, make it active; --goal and
#                                     --check fill INTENT's Goal and C1. A multi-repo
#                                     task (profile # Workspaces, or repo names from # Repos)
#                                     lives in the primary repo (role: primary, else the first);
#                                     REPOS lists name<TAB>path, and every other repo's ACTIVE
#                                     points home: "@<home-path>:<slug>"
#   task.sh repos                     the active task's repos (name<TAB>path)
#   task.sh active                    print the active slug (empty if none)
#   task.sh dir                       print the active task dir
#   task.sh switch <slug>             make another task active
#   task.sh close                     clear ACTIVE (folder is kept)
#   task.sh list                      tasks with slice progress
#   task.sh ticket [<ref>]            record (or print) the ticket this task works on; leads.sh shows it
#   task.sh slice <id> <status>       set a slice status (todo|doing|done|blocked)
#                                     "done" is gated: red-first, green after the last edit,
#                                     probe TEETH, diff budget (see proofs). Override with
#                                     --force "<reason>" (logged to DECISIONS.tsv).
#   task.sh proofs <id>               show which done-proofs a slice has and lacks
#   task.sh todo                      SLICES.md as todo-list lines: one per slice, the doing
#                                     slice expanded into its loop steps (copy into the todo list)
#   task.sh tdd <id> red|green [--force "<reason>"]   opt-in TDD lock: red edits only tests,
#                                     green only code (tests locked); green needs a new <id>:red
#                                     FAIL since red began. task.sh tdd off [reason] ends it (logged)
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
. "$here/../../../hooks/roots.sh"; flow_roots; flow_task
root="$FLOW_MAIN"
flow="$FLOW_DIR"
profile="${FLOW_STACK_HOME:-$HOME/.flow-stack}/profile.md"

die() { echo "task.sh: $*" >&2; exit 1; }
active() { printf '%s' "$FLOW_TASK"; }
active_dir() {
  [ -n "$FLOW_TASK_DIR" ] || die "no active task (run: task.sh new <slug>)"
  printf '%s' "$FLOW_TASK_DIR"
}

# profile lookups: repo_field <name> <field> (from # Repos) · ws_repos <workspace> (from # Workspaces)
repo_field() {
  awk -v n="## $1" -v k="- $2:" '/^# /{on=($0=="# Repos")} on && /^## /{cur=$0}
    on && cur==n && index($0,k)==1 {v=substr($0,length(k)+1); sub(/^[[:space:]]+/,"",v); sub(/[[:space:]]+$/,"",v); print v; exit}' "$profile" 2>/dev/null || true
}
ws_repos() {
  awk -v n="## $1" '/^# /{on=($0=="# Workspaces")} on && /^## /{cur=$0}
    on && cur==n && /^- repos:/ {sub(/^- repos:[[:space:]]*/,""); gsub(/[[:space:]]*,[[:space:]]*/,"\n"); print; exit}' "$profile" 2>/dev/null || true
}
# point_repos <task-dir> <slug>: ACTIVE in the home repo, pointers everywhere else
point_repos() {
  local d="$1" slug="$2" home name path cur
  home="$(cd "$d/../../.." && pwd -P)"
  printf '%s\n' "$slug" >"$home/.flow/ACTIVE"
  [ -f "$d/REPOS" ] || return 0
  while IFS=$'\t' read -r name path; do
    [ "$path" = "$home" ] && continue
    mkdir -p "$path/.flow"
    cur="$(head -n1 "$path/.flow/ACTIVE" 2>/dev/null | tr -d '[:space:]' || true)"
    [ -n "$cur" ] && [ "$cur" != "@$home:$slug" ] && echo "  $name: was on '$cur', now on $slug" >&2
    printf '@%s:%s\n' "$home" "$slug" >"$path/.flow/ACTIVE"
    git -C "$path" check-ignore -q .flow/ACTIVE 2>/dev/null || grep -qxF ".flow/ACTIVE" "$path/.gitignore" 2>/dev/null || printf '.flow/ACTIVE\n' >>"$path/.gitignore"
  done <"$d/REPOS"
}

ensure_repo_files() {
  mkdir -p "$flow/tasks"
  [ -f "$flow/config.json" ] || cp "$templates/config.json" "$flow/config.json"
  local gi="$root/.gitignore"
  for line in ".flow/ACTIVE" ".flow/tasks/" ".flow/trail.jsonl"; do
    git -C "$root" check-ignore -q "$line" 2>/dev/null && continue
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
    local srepo; srepo="$(flow_repo_path "$(slice_field "$s" "$id" repo)")"
    set -f; line="$(cd "${srepo:-.}" && "$here/../../loop/scripts/diffstat.sh" $fence | head -n1 || true)"; set +f
    local changed="${line#*changed=}"; changed="${changed%% *}"
    if [ "${changed:-0}" -le "$budget" ]; then echo "  ✓ budget: $line (≤ $budget)"
    else echo "  ✗ budget: $line (> $budget; split the slice or justify with --force)"; ok=1; fi
  fi
  return $ok
}

cmd="${1:-}"; shift || true
case "$cmd" in
  new|switch|close|slice|accept|ticket)
    [ -z "$FLOW_LANE" ] || die "'$cmd' is refused in worktree lane '$FLOW_LANE': the task plan is shared. Return your evidence; the delegate accepts it and marks the slice." ;;
esac
case "$cmd" in
  new)
    slug="${1:-}"; [ -n "$slug" ] || die "usage: task.sh new <slug> [playbook] [--workspace <name> | --repos <a,b>]"
    [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "slug must be kebab-case: $slug"
    shift; playbook=feature; names=""; goal=""; c1=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --workspace) names="$(ws_repos "${2:-}")"; [ -n "$names" ] || die "no workspace '${2:-}' in $profile (# Workspaces)"; shift 2 ;;
        --repos) names="$(printf '%s' "${2:-}" | tr ',' '\n' | sed 's/^ *//; s/ *$//')"; shift 2 ;;
        --goal|--check) [ $# -ge 2 ] || die "$1 needs a value"
          if [ "$1" = --goal ]; then goal="$2"; else c1="$2"; fi; shift 2 ;;
        -*) die "unknown option: $1" ;;
        *) playbook="$1"; shift ;;
      esac
    done
    repos_tsv=""
    if [ -n "$names" ]; then
      home=""; first=""
      while IFS= read -r n; do
        [ -n "$n" ] || continue
        pth="$(repo_field "$n" path)"; pth="${pth/#\~/$HOME}"
        [ -n "$pth" ] && [ -d "$pth" ] || die "repo '$n': no '- path:' in the profile's # Repos, or it doesn't exist"
        pth="$(cd "$pth" && pwd -P)"
        repos_tsv="$repos_tsv$n	$pth"$'\n'
        [ -n "$first" ] || first="$pth"
        [ -z "$home" ] && [ "$(repo_field "$n" role)" = primary ] && home="$pth"
      done <<<"$names"
      root="${home:-$first}"; flow="$root/.flow"
    fi
    ensure_repo_files
    d="$flow/tasks/$slug"
    [ -e "$d" ] && die "task exists: $d (use: task.sh switch $slug)"
    mkdir -p "$d"
    fill "$slug" "$templates/INTENT.md" | GOAL="$goal" C1="$c1" awk '
      /^- \[ \] C1 ·  · ``$/ && ENVIRON["C1"] != "" { print "- [ ] C1 · the goal holds · `" ENVIRON["C1"] "`"; next }
      { print }
      /^## Goal/ { g = 1 }
      g && /-->$/ { if (ENVIRON["GOAL"] != "") print ENVIRON["GOAL"]; g = 0 }' >"$d/INTENT.md"
    fill "$slug" "$templates/SLICES.md" >"$d/SLICES.md"
    cp "$templates/DECISIONS.tsv" "$d/DECISIONS.tsv"
    printf '# Evidence · %s\n<!-- Written only by verify/scripts/evidence.sh. -->\n\n' "$slug" >"$d/EVIDENCE.md"
    printf '%s\n' "$playbook" >"$d/PLAYBOOK"
    [ -n "$repos_tsv" ] && printf '%s' "$repos_tsv" >"$d/REPOS"
    point_repos "$d" "$slug"
    echo "$d"
    ;;
  active) active ;;
  dir) active_dir ;;
  repos)
    d="$(active_dir)"
    if [ -f "$d/REPOS" ]; then cat "$d/REPOS"; else printf '%s\t%s\n' "$(basename "$FLOW_TASK_HOME")" "$FLOW_TASK_HOME"; fi ;;
  switch)
    [ -d "$flow/tasks/${1:-}" ] || die "no such task: ${1:-}"
    point_repos "$flow/tasks/$1" "$1"; echo "active: $1"
    ;;
  close)
    if [ -n "$FLOW_TASK_DIR" ] && [ -f "$FLOW_TASK_DIR/REPOS" ]; then
      while IFS=$'\t' read -r _ path; do rm -f "$path/.flow/ACTIVE"; done <"$FLOW_TASK_DIR/REPOS"
    fi
    rm -f "$flow/ACTIVE" "${FLOW_TASK_HOME:-$root}/.flow/ACTIVE"; echo "no active task" ;;
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
  tdd)
    st="$(flow_state_dir "$(active_dir)")"; pf="$st/TDD"
    if [ "${1:-}" = off ]; then
      [ -f "$pf" ] || die "the TDD lock is not on"
      rm -f "$pf"; "$0" decide agent yes "TDD lock off" "${2:-no reason given}" >/dev/null; echo "tdd: off"; exit 0
    fi
    id="${1:-}"; ph="${2:-}"
    [[ "$ph" =~ ^(red|green)$ ]] || die "usage: task.sh tdd <id> red|green [--force \"<reason>\"] | task.sh tdd off [reason]"
    grep -q "^## $id " "$(active_dir)/SLICES.md" || die "no slice $id"
    reds="$(grep -cE "^### [^ ]+ · $id:(red|before) · FAIL " "$st/EVIDENCE.md" 2>/dev/null || true)"; reds="${reds:-0}"
    if [ "$ph" = green ]; then
      read -r pid pph pn _ <"$pf" 2>/dev/null || true
      [ "${pid:-}" = "$id" ] && [ "${pph:-}" = red ] || die "slice $id is not in red; start with: task.sh tdd $id red"
      if [ "$reds" -le "${pn:-0}" ]; then
        if [ "${3:-}" = --force ] && [ -n "${4:-}" ]; then
          "$0" decide agent yes "tdd green without a fresh red FAIL for $id" "$4" >/dev/null; echo "forced: logged to DECISIONS.tsv"
        else
          die "no failing '$id:red' run since red began. Run evidence.sh $id:red and watch it fail for the right reason, or: task.sh tdd $id green --force \"<reason>\""
        fi
      fi
    fi
    mkdir -p "$st"; printf '%s %s %s\n' "$id" "$ph" "$reds" >"$pf"; echo "$id → $ph" ;;
  ticket)
    if [ -n "${1:-}" ]; then printf '%s\n' "$1" >"$(active_dir)/TICKET"; echo "ticket: $1"; else cat "$(active_dir)/TICKET" 2>/dev/null || true; fi ;;
  todo)
    f="$(active_dir)/SLICES.md"
    grep -q '^status:' "$f" 2>/dev/null || die "no slices in $f yet (run the slice skill)"
    awk '
      function out() {
        if (id == "") return
        mark = (st == "done" ? "[x]" : st == "doing" ? "[>]" : st == "blocked" ? "[!]" : "[ ]")
        printf "%s %s · %s\n", mark, id, title
        if (st != "doing") return
        if (red !~ /^n\/a/) printf "    - red: evidence.sh %s:before fails for the right reason\n", id
        printf "    - subtract scan, one line in DECISIONS.tsv\n"
        printf "    - build inside the fence: %s\n", fence
        printf "    - green: evidence.sh %s passes\n", id
        if (teeth !~ /^n\/a/) printf "    - teeth: probe.sh %s says TEETH\n", id
        printf "    - task.sh slice %s done\n", id
      }
      /^## / { out(); id = $2; title = $0; sub(/^## [^ ]+ · ?/, "", title); st = ""; red = ""; teeth = ""; fence = "" }
      /^status:/ { st = $2 }
      /^fence:/ { fence = $0; sub(/^fence:[[:space:]]*/, "", fence) }
      /^red:/ { red = $0; sub(/^red:[[:space:]]*/, "", red) }
      /^teeth:/ { teeth = $0; sub(/^teeth:[[:space:]]*/, "", teeth) }
      END { out() }' "$f" ;;
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
    if [ -d "$flow/features" ]; then
      ld="$(dirname "$lev")"; br="$(cat "$ld/BRANCH" 2>/dev/null || true)"; base="$(cat "$ld/BASE" 2>/dev/null || true)"
      [ -n "$br" ] && [ -n "$base" ] || die "lane '$lane' has no BRANCH/BASE record (its first evidence.sh run writes them); re-run its check inside the lane"
      git -C "$root" merge-base --is-ancestor "$br" HEAD 2>/dev/null || die "lane '$lane' (branch $br) is not merged into HEAD; merge it (not --squash) first"
      feats="$here/../../feature-map/scripts/features.sh"; ids=()
      while IFS= read -r i; do [ -n "$i" ] && ids+=("$i"); done < <(cd "$root" && git diff --name-only "$base" "$br" | { paths=(); while IFS= read -r p; do paths+=("$p"); done; [ ${#paths[@]} -eq 0 ] || "$feats" impact --ids "${paths[@]}"; })
      if [ ${#ids[@]} -gt 0 ]; then
        out="$(cd "$root" && "$feats" run "${ids[@]}" 2>&1)" \
          || die "lane '$lane' is merged, but features it touched fail on the merged tree, so its evidence is not accepted. Fix it with a fresh worker, or undo the merge.
$out"
        printf '%s\n' "$out"
      fi
    fi
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
  -h|--help|"") sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command: $cmd (try -h)" ;;
esac
