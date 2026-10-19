#!/usr/bin/env bash
# probe-deleted-dir.test.sh: a tracked file deleted together with its directory is restored for
# the revert probe (verdict TEETH when the check needs it), and afterwards the file and the
# recreated directory are gone again (#146). PROBE_SRC overrides the probe.sh under test.
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"; PLUGIN="$(cd "$D/../../.." && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/probe-deleted-dir.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR" "$SB/p/skills/probe/scripts" "$SB/repo"
cp -R "$PLUGIN/hooks" "$SB/p/hooks"
cp "${PROBE_SRC:-$D/probe.sh}" "$SB/p/skills/probe/scripts/probe.sh"; chmod +x "$SB/p/skills/probe/scripts/probe.sh"
P="$SB/p/skills/probe/scripts/probe.sh"

cd "$SB/repo"
# shellcheck source=/dev/null
. "$PLUGIN/evals/_lib/toy.sh"
toy_repo
mkdir -p src/old/deep
echo keep >src/old/deep/x.sh
git add -A && git commit -qm old

echo "-- the change deletes src/old/ entirely; the check passes only when x.sh is gone"
git rm -rq src/old
out="$("$P" S1 "test ! -e src/old/deep/x.sh" 2>&1)"; code=$?
grep -q "reverted 1" <<<"$out" && ok "probe reverted the deletion" || bad "probe did not revert the deletion: $out"
grep -q TEETH <<<"$out" && [ "$code" -eq 0 ] && ok "verdict TEETH" || bad "verdict not TEETH (exit $code): $out"
[ ! -e src/old ] && ok "src/old is gone again after the probe" || bad "src/old was left behind"

echo "-- a directory that still exists is kept"
git reset -q --hard
mkdir -p src/old/other && echo y >src/old/other/y.txt
git rm -q src/old/deep/x.sh
"$P" S1 "test ! -e src/old/deep/x.sh" >/dev/null 2>&1
[ -f src/old/other/y.txt ] && ok "existing sibling kept" || bad "existing sibling removed"
[ ! -e src/old/deep ] && ok "recreated src/old/deep removed" || bad "src/old/deep left behind"

[ "$FAILS" -eq 0 ] && { echo "== probe-deleted-dir · PASS"; exit 0; }
echo "== probe-deleted-dir · FAIL ($FAILS)"; exit 1
