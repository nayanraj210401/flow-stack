#!/usr/bin/env bash
# seal-worktree.test.sh: in a lead worktree, verify and reseal hash the worktree's file, the one
# add hashed, not the main checkout's copy (#85).
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"; PLUGIN="$(cd "$D/../../.." && pwd)"
SEAL="$D/seal.sh"; T="$PLUGIN/skills/flow/scripts/task.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
has() { grep -Fq -- "$2" <<<"$1"; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/seal-worktree.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR" "$SB/main"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID FLOW_SESSION_PID
cd "$SB/main"
# shellcheck source=/dev/null
. "$PLUGIN/evals/_lib/toy.sh"
toy_repo
git worktree add -q ../lead -b fix/lead; W="$(cd ../lead && pwd -P)"
cd "$W"
"$T" new wtdemo bugfix >/dev/null
S="$SB/main/.flow/tasks/wtdemo/SEALS"
[ -d "$SB/main/.flow/tasks/wtdemo" ] && ok "task folder lives in the main checkout" || bad "task folder not in main"
echo 'echo new check' >tests/test_new.sh   # a test the slice adds: main has no copy
echo 'echo worktree' >>tests/test_add.sh  # main's copy differs from the worktree's
"$SEAL" add tests/test_new.sh tests/test_add.sh >/dev/null

echo "-- untouched seals verify intact in the lead worktree"
v="$("$SEAL" verify)"; rc=$?
[ "$rc" = 0 ] && ok "seals intact" || bad "false alarm (rc=$rc): $v"

echo "-- an edit in the worktree is detected"
echo tamper >>tests/test_add.sh
v="$("$SEAL" verify)"; rc=$?
{ [ "$rc" != 0 ] && has "$v" "CHANGED  tests/test_add.sh"; } && ok "edit detected" || bad "edit missed (rc=$rc): $v"

echo "-- reseal records the worktree's hash"
"$SEAL" reseal >/dev/null
v="$("$SEAL" verify)"; rc=$?
[ "$rc" = 0 ] && ok "intact after reseal" || bad "reseal hashed another file (rc=$rc): $v"
[ "$(grep -c . "$S")" = 2 ] && ok "reseal kept both seals" || bad "reseal dropped a seal: $(cat "$S")"

[ "$FAILS" -eq 0 ] && { echo "== seal-worktree · PASS"; exit 0; }
echo "== seal-worktree · FAIL ($FAILS)"; exit 1
