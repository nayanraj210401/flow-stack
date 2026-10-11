#!/usr/bin/env bash
# blind-collide.test.sh: blind-run.sh must restore every pre-existing target when two paths
# flatten to one name (src/a/b__c.sh vs src/a__b/c.sh) (#72). Runs a copy of the script
# (BLIND_SRC overrides the source) in a throwaway toy repo with a throwaway home.
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"; PLUGIN="$(cd "$D/../../.." && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/blind-collide.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR" "$SB/p/skills/verify/scripts" "$SB/repo"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID
cp -R "$PLUGIN/hooks" "$SB/p/hooks"
cp "${BLIND_SRC:-$D/blind-run.sh}" "$SB/p/skills/verify/scripts/blind-run.sh"; chmod +x "$SB/p/skills/verify/scripts/blind-run.sh"
B="$SB/p/skills/verify/scripts/blind-run.sh"

cd "$SB/repo"
# shellcheck source=/dev/null
. "$PLUGIN/evals/_lib/toy.sh"
toy_repo
toy_task demo "mul multiplies" "no division"
mkdir -p src/a src/a__b
echo USER1 >src/a/b__c.sh; echo USER2 >src/a__b/c.sh
BL=.flow/tasks/demo/blind; mkdir -p "$BL"
echo BLIND1 >"$BL/x"; echo BLIND2 >"$BL/y"
manifest() { printf 'run: %s\n' "$1" >"$BL/MANIFEST"; shift; printf '%s\n' "$@" >>"$BL/MANIFEST"; }

echo "-- pre-existing targets at colliding paths"
manifest 'cat src/a/b__c.sh src/a__b/c.sh >seen' 'file: x -> src/a/b__c.sh' 'file: y -> src/a__b/c.sh'
"$B" >/dev/null 2>&1
[ "$(tr '\n' / <seen)" = "BLIND1/BLIND2/" ] && ok "both blind files installed" || bad "blind files not installed"
[ "$(cat src/a/b__c.sh 2>&1)/$(cat src/a__b/c.sh 2>&1)" = "USER1/USER2" ] && ok "both user files restored" || bad "a user file was lost"

echo "-- target escaping the repo is refused"
printf 'USER\n' >"$SB/sib.sh"
manifest 'true' 'file: x -> ../sib.sh'
"$B" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && [ "$(cat "$SB/sib.sh")" = USER ] && ok "../ target refused, file untouched" || bad "../ target was installed (rc=$rc)"

echo "-- new target is removed afterwards"
manifest 'test -f src/new.sh' 'file: x -> src/new.sh'
"$B" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ ! -e src/new.sh ] && ok "installed then removed" || bad "new target mishandled (rc=$rc)"

[ "$FAILS" -eq 0 ] || { echo "blind-collide: $FAILS failure(s)"; exit 1; }
echo "blind-collide: PASS"
