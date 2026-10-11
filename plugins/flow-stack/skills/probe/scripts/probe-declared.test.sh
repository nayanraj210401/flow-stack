#!/usr/bin/env bash
# probe-declared.test.sh: probe.sh with a C<n>/S<n> label runs only the check the task declares
# for it, as evidence.sh does, so `probe.sh S1 false` can't record the slice's teeth (#70).
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"; PLUGIN="$(cd "$D/../../.." && pwd)"
PROBE="$D/probe.sh"; T="$PLUGIN/skills/flow/scripts/task.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/probe-declared.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR" "$SB/repo"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID FLOW_SESSION_PID
cd "$SB/repo"
# shellcheck source=/dev/null
. "$PLUGIN/evals/_lib/toy.sh"
toy_repo
echo 1 >a.txt; git add -A; git commit -qm a
"$T" new pd bugfix --goal g --check "grep -q 2 a.txt" >/dev/null
printf '## S1 · a\nstatus: doing\ncheck: grep -q 2 a.txt\nfence: a.txt\n' >.flow/tasks/pd/SLICES.md
EV=.flow/tasks/pd/EVIDENCE.md
echo 2 >a.txt
teeth() { grep -c "probe:$1 · TEETH" "$EV" 2>/dev/null || true; }

echo "-- a command other than the declared check is refused"
for id in S1 C1; do
  "$PROBE" "$id" false >/dev/null 2>&1; rc=$?
  { [ "$rc" = 2 ] && [ "$(teeth "$id")" = 0 ]; } && ok "$id false: refused" || bad "$id false: rc=$rc, TEETH recorded $(teeth "$id")x"
done
"$PROBE" S9 false >/dev/null 2>&1; rc=$?
[ "$rc" != 2 ] && ok "undeclared S9: runs (no check to hold it to)" || bad "undeclared S9: refused"

echo "-- the declared check runs"
for id in S1 C1; do
  "$PROBE" "$id" "grep -q 2 a.txt" >/dev/null 2>&1
  [ "$(teeth "$id")" = 1 ] && ok "$id declared: TEETH" || bad "$id declared: TEETH recorded $(teeth "$id")x"
done

echo "-- free labels run what they are given"
"$PROBE" smoke false >/dev/null 2>&1
[ "$(teeth smoke)" = 1 ] && ok "smoke: runs" || bad "smoke: TEETH recorded $(teeth smoke)x"

[ "$FAILS" -eq 0 ] && { echo "== probe-declared · PASS"; exit 0; }
echo "== probe-declared · FAIL ($FAILS)"; exit 1
