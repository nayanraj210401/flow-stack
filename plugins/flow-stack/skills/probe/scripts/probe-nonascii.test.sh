#!/usr/bin/env bash
# probe-nonascii.test.sh: probe.sh must revert tracked, new, and deleted files whose names are
# non-ASCII (git C-quotes them as "caf\303\251.sh" unless core.quotepath is off).
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"; PLUGIN="$(cd "$D/../../.." && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/probe-nonascii.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
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
printf 'v1\n' >café.sh; printf 'gone\n' >ünï.sh
git add -A && git commit -qm base

echo "-- modified, new and deleted non-ASCII files"
echo v2 >café.sh; echo new >nöw.sh; rm ünï.sh
out="$("$P" N1 'grep -q v1 café.sh' 2>&1)"
grep -q "reverted 3" <<<"$out" && ok "probe reverted all three" || bad "probe did not revert all three: $out"
[ "$(cat café.sh)" = v2 ] && [ "$(cat nöw.sh)" = new ] && [ ! -e ünï.sh ] && ok "state restored" || bad "state not restored"

[ "$FAILS" -eq 0 ] && echo "probe-nonascii: ok" || { echo "probe-nonascii: $FAILS failed"; exit 1; }
