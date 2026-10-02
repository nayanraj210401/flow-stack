#!/usr/bin/env bash
# evidence.sh: run a check and record the result as evidence.
#   evidence.sh <C<n>|S<n>>[:before] [<command string>] [artifact-path ...]
#   evidence.sh <label> <command string> [artifact-path ...]
#
# A C<n> or S<n> label runs the command the active task declares for it (INTENT.md
# acceptance check, SLICES.md check:). A different command is refused (exit 2), and so
# is a check that can't fail (empty, :, true). Other labels (feat:x, blind, smoke …) run
# the command given. Appends a block to the active task's EVIDENCE.md, prints the
# output tail, and ends with one machine-readable line the circuit breaker reads:
#   flow-evidence: PASS
#   flow-evidence: FAIL sig=<hash>
# Exits with the command's exit code.
set -uo pipefail

[ $# -ge 1 ] || { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
label="$1"; check="${2-}"; shift; [ $# -eq 0 ] || shift

. "$(dirname "$0")/../../../hooks/roots.sh"; flow_roots; flow_task

refuse() { echo "evidence.sh: $*" >&2; echo "flow-evidence: REFUSED"; exit 2; }
declared() { # declared <C<n>|S<n>>: the command the active task gives for that check
  case "$1" in
    C*) sed -nE "s/^- \[.\] $1 · .* · \`(.*)\`[[:space:]]*\$/\1/p" "$FLOW_TASK_DIR/INTENT.md" ;;
    S*) awk -v id="$1" '/^## /{on=($2==id)} on&&/^check:/{sub(/^check:[ \t]*/,""); print; exit}' "$FLOW_TASK_DIR/SLICES.md" ;;
  esac 2>/dev/null | head -n1
}

id="${label%%:*}"
if [ -n "$FLOW_TASK_DIR" ] && [[ "$id" =~ ^[CS][0-9]+$ ]]; then
  want="$(declared "$id")"
  [ -n "$want" ] || refuse "$id has no runnable command declared in task $FLOW_TASK. Declare it (INTENT.md \`- [ ] $id · <what> · \\\`<cmd>\\\`\`, or a slice's check:), or use a free label."
  [ -z "$check" ] || [ "$check" = "$want" ] || refuse "$id is declared as \`$want\`. Run \`evidence.sh $label\` with no command, or record this run under another label."
  check="$want"
fi
case "$(tr -d '[:space:]' <<<"$check")" in
  ""|:|true|exit0) refuse "'$check' can't fail, so it proves nothing. Give a command that exercises the behavior." ;;
esac
root="$FLOW_ROOT"
ev=""
if [ -n "$FLOW_TASK_DIR" ]; then
  ev="$(flow_state_dir "$FLOW_TASK_DIR")/EVIDENCE.md"; mkdir -p "$(dirname "$ev")"
  # A lane records its branch and fork point once, so task.sh accept knows exactly what it merges.
  if [ -n "$FLOW_LANE" ] && [ ! -s "$(dirname "$ev")/BASE" ]; then
    git -C "$root" rev-parse --abbrev-ref HEAD >"$(dirname "$ev")/BRANCH" 2>/dev/null
    git -C "$root" merge-base HEAD "$(git -C "$FLOW_MAIN" rev-parse HEAD)" >"$(dirname "$ev")/BASE" 2>/dev/null
  fi
fi

out="$(mktemp)"
start=$(date +%s)
( cd "$root" && bash -c "$check" ) >"$out" 2>&1
code=$?
secs=$(( $(date +%s) - start ))

if [ "$code" -eq 0 ]; then
  verdict=PASS; sigpart=""
else
  verdict=FAIL
  # Signature: the failure's shape with volatile parts (numbers, hex, tmp paths) removed.
  sig="$(tail -n 30 "$out" | sed -E 's#/(tmp|var|private)/[^ ]*#TMP#g; s/0x[0-9a-f]+/HEX/g; s/[0-9]+(\.[0-9]+)?(ms|s)?/N/g' | shasum | cut -c1-10)"
  sigpart=" sig=$sig"
fi

if [ -n "$ev" ]; then
  head_sha="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo none)"
  dirty="$([ -n "$(git -C "$root" status --porcelain 2>/dev/null | grep -v '^?? .flow/' || true)" ] && echo yes || echo no)"
  {
    printf '### %s · %s · %s · exit=%s\n' "$(date -u +%FT%TZ)" "$label" "$verdict" "$code"
    printf -- '- cmd: `%s`\n' "$check"
    [ -n "$FLOW_REPO_KEY" ] && printf -- '- repo: %s\n' "$FLOW_REPO_KEY"
    printf -- '- head: %s  dirty: %s  took: %ss\n' "$head_sha" "$dirty" "$secs"
    for a in "$@"; do printf -- '- artifact: %s\n' "$a"; done
    printf '<details><summary>output (last 40 lines)</summary>\n\n```\n'
    tail -n 40 "$out"
    printf '```\n</details>\n\n'
  } >>"$ev"
else
  echo "evidence.sh: no active task; result not recorded" >&2
fi

tail -n 15 "$out"
rm -f "$out"
echo "flow-evidence: ${verdict}${sigpart}"
exit "$code"
