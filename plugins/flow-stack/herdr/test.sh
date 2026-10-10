#!/usr/bin/env bash
# test.sh [data] [host] [plugin]  (none = all): the herdr plugin and the flow-stack pieces it reads,
# in a throwaway toy repo with a throwaway FLOW_STACK_HOME and Claude config dir, herdr stubbed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
T="$PLUGIN/skills/flow/scripts/task.sh"; ST="$PLUGIN/skills/flow/scripts/status.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
has() { grep -Fq -- "$2" <<<"$1"; }
SECTIONS=("$@")
on() { [ ${#SECTIONS[@]} -eq 0 ] && return 0; local s; for s in "${SECTIONS[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/herdr-board.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
OWNERS=()
cleanup() { [ ${#OWNERS[@]} -eq 0 ] || kill "${OWNERS[@]}" 2>/dev/null; rm -rf "$SB"; }
trap cleanup EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
unset HERDR_ENV HERDR_PANE_ID HERDR_SOCKET_PATH HERDR_BIN_PATH ORCA_PANE_KEY CMUX_WORKSPACE_ID
export FLOW_SESSION_PID=""  # outside Claude: the human's view, every task visible
cd "$SB/repo"
# shellcheck source=/dev/null
. "$PLUGIN/evals/_lib/toy.sh"
toy_repo
toy_task demo "mul multiplies" "no division"
toy_slice demo S1 doing "bash tests/test_mul.sh" "src/**"
git add -A && git commit -qm task

# session <name> <session-id>: a live fake Claude session in the registry; prints its pid
session() {
  sleep 600 >/dev/null 2>&1 & local p=$!
  OWNERS+=("$p")
  jq -n --argjson pid "$p" --arg n "$1" --arg s "$2" '{pid:$pid, name:$n, sessionId:$s, status:"idle"}' >"$CLAUDE_CONFIG_DIR/sessions/$p.json"
  echo "$p"
}

if on data; then
  echo "-- data: status.sh names the live owner of the checkout's task"
  pid="$(session flow-demo-1 sess-1)"
  printf 'demo\n%s\n' "$pid" >.flow/ACTIVE
  out="$("$ST" --full "$PWD")"
  [ "$(jq -r .owner <<<"$out")" = "$pid" ] && ok "owner is the live session's pid" || bad "owner: $(jq -c '{task,owner}' <<<"$out")"
  printf 'demo\n%s\n' 999999 >.flow/ACTIVE
  [ "$("$ST" --full "$PWD" | jq -r .owner)" = "" ] && ok "a dead owner reads as none" || bad "dead owner shown"

  echo "-- data: a gate is decided with a choice and a note"
  cat >.flow/tasks/demo/GATES.md <<'EOF'
GATE · push the branch?
  options: A) push now  B) hold   (recommend: A, because CI is green)
  evidence: EVIDENCE.md C1

GATE · open the PR as draft?
  options: A) draft  B) ready
EOF
  q="push the branch?"
  o="$("$T" gate 1 approve "$q" "B) hold" "wait for the review" 2>&1)"
  line="$(grep '^  decided: ' .flow/tasks/demo/GATES.md | head -n1)"
  has "$line" "decided: human approve" && has "$line" "choice: B) hold" && has "$line" "note: wait for the review" \
    && ok "decided line carries choice and note" || bad "decided: $line ($o)"
  has "$(tail -n1 .flow/tasks/demo/DECISIONS.tsv)" "B) hold" && ok "DECISIONS.tsv logs the choice" || bad "decisions: $(tail -n1 .flow/tasks/demo/DECISIONS.tsv)"
  [ "$("$ST" --full "$PWD" | jq '.gates | length')" = 1 ] && ok "the decided gate leaves the open list" || bad "gates: $("$ST" --full "$PWD" | jq -c .gates)"
  "$T" gate 2 reject "open the PR as draft?" >/dev/null 2>&1 && has "$(grep -c '^  decided: human reject' .flow/tasks/demo/GATES.md)" 1 \
    && ok "choice and note stay optional" || bad "plain reject failed"
  bad_note="$(printf 'x\033[31mred\nnext')"
  printf 'GATE · third?\n  options: A) yes\n' >>.flow/tasks/demo/GATES.md
  "$T" gate 3 approve "third?" "A) yes" "$bad_note" >/dev/null 2>&1
  l3="$(grep '^  decided: ' .flow/tasks/demo/GATES.md | tail -n1)"
  ! grep -q $'\033' .flow/tasks/demo/GATES.md && [ "$(grep -c '^GATE · ' .flow/tasks/demo/GATES.md)" = 3 ] && has "$l3" "note: x[31mred next" \
    && ok "a note's control characters and newlines are stripped" || bad "note leaked: $l3"
  rm -f .flow/tasks/demo/GATES.md
fi

if [ "$FAILS" -eq 0 ]; then echo "== herdr · PASS"; exit 0; fi
echo "== herdr · FAIL ($FAILS)"; exit 1
