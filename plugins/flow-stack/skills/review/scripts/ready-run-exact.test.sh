#!/usr/bin/env bash
# ready-run-exact.test.sh: ready[] run commands execute exactly as written: backslashes kept, every line run (#120).
set -uo pipefail
R="$(cd "$(dirname "$0")" && pwd)/ready.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/ready-run-exact.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
cd "$SB/repo" && git init -q && git config user.email a@b && git config user.name a
mkdir -p .flow
echo hi >f && git add f && git commit -qm i
printf 'a.b\n' >data
jq -n --arg bs "grep -q 'a\\.b' data" --arg multi $'echo one\nfalse' \
  '{ready:[{id:"bs",run:$bs},{id:"multi",run:$multi},{id:"plain",run:"test -f f"}]}' >.flow/config.json
git add data && git commit -qm d
out="$("$R" </dev/null 2>&1)"
grep -q '✓ bs' <<<"$out" && ok "a backslash in run is kept" || bad "bs failed: $out"
grep -q '✗ multi' <<<"$out" && ok "a later line of a multi-line run is executed" || bad "multi passed: $out"
grep -q '✓ plain' <<<"$out" && ok "a plain entry still passes" || bad "plain failed: $out"
[ "$FAILS" = 0 ] || { echo "== ready-run-exact · FAIL ($FAILS)"; exit 1; }
echo "== ready-run-exact · PASS"
