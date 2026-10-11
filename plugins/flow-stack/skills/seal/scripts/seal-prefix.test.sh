#!/usr/bin/env bash
# seal-prefix.test.sh: sealing a path must not drop the seal of a longer-named file (#32).
# Runs the working tree's seal.sh in a throwaway toy repo with a throwaway home.
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"; PLUGIN="$(cd "$D/../../.." && pwd)"
SEAL="$D/seal.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
has() { grep -Fq -- "$2" <<<"$1"; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/seal-prefix.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR" "$SB/repo"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID
cd "$SB/repo"
# shellcheck source=/dev/null
. "$PLUGIN/evals/_lib/toy.sh"
toy_repo
"$PLUGIN/skills/flow/scripts/task.sh" new demo feature >/dev/null
echo a >tests/foo.test.ts; echo b >tests/foo.test; echo c >tests/bar.test
git add -A && git commit -qm files

echo "-- sealing a prefix keeps the longer-named seal"
"$SEAL" add tests/foo.test.ts >/dev/null; "$SEAL" add tests/foo.test >/dev/null
l="$("$SEAL" list)"
has "$l" "tests/foo.test.ts" && ok "foo.test.ts still sealed" || bad "foo.test.ts seal dropped: $l"
grep -qx 'tests/foo.test' <<<"$l" && ok "foo.test sealed" || bad "foo.test not sealed: $l"
echo z >>tests/foo.test.ts
v="$("$SEAL" verify)"; rc=$?
{ [ "$rc" != 0 ] && has "$v" "CHANGED  tests/foo.test.ts"; } && ok "edit to foo.test.ts is detected" || bad "edit undetected (rc=$rc): $v"

echo "-- re-adding the same path replaces its line"
"$SEAL" add tests/bar.test >/dev/null; "$SEAL" add tests/bar.test >/dev/null
n="$("$SEAL" list | grep -cx 'tests/bar.test')"
[ "$n" = 1 ] && ok "one line for bar.test" || bad "bar.test has $n lines"

echo "-- rm of the prefix keeps the longer-named seal"
"$SEAL" rm tests/foo.test >/dev/null
l="$("$SEAL" list)"
[ "$(grep -cx 'tests/foo.test' <<<"$l")" = 0 ] && ok "foo.test removed" || bad "foo.test still sealed: $l"
has "$l" "tests/foo.test.ts" && ok "foo.test.ts survives rm foo.test" || bad "rm dropped foo.test.ts: $l"

[ "$FAILS" -eq 0 ] && { echo "== seal-prefix · PASS"; exit 0; }
echo "== seal-prefix · FAIL ($FAILS)"; exit 1
