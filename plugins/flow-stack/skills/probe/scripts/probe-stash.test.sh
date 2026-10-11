#!/usr/bin/env bash
# probe-stash.test.sh: probe.sh must restore every reverted file when two paths flatten to one
# name (src/a/b__c.sh vs src/a__b/c.sh). Runs a copy of the script (PROBE_SRC overrides the
# source) so the revert cannot break the running file.
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"; PLUGIN="$(cd "$D/../../.." && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/probe-stash.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
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
mkdir -p src/a src/a__b
echo base1 >src/a/b__c.sh; echo base2 >src/a__b/c.sh
git add -A && git commit -qm collide

echo "-- tracked edits at colliding paths"
echo USER1 >src/a/b__c.sh; echo USER2 >src/a__b/c.sh
out="$("$P" S1 true 2>&1)"
grep -q "reverted 2" <<<"$out" && ok "probe reverted both" || bad "probe did not revert both"
[ "$(cat src/a/b__c.sh)/$(cat src/a__b/c.sh)" = "USER1/USER2" ] && ok "both edits restored" || bad "an edit was lost"
git checkout -q src

echo "-- untracked files at colliding paths"
mkdir -p src/a__n; echo NEW1 >src/a/n__x.sh; echo NEW2 >src/a__n/x.sh
"$P" S2 true >/dev/null 2>&1
[ "$(cat src/a/n__x.sh 2>&1)/$(cat src/a__n/x.sh 2>&1)" = "NEW1/NEW2" ] && ok "both new files restored" || bad "a new file was lost"
rm -rf src/a/n__x.sh src/a__n

echo "-- hollowed files at colliding paths"
echo 'H1 one' >src/a/b__c.sh; echo 'H2 two' >src/a__b/c.sh
"$P" S3 true --hollow src/a/b__c.sh one 1 --hollow src/a__b/c.sh two 2 >/dev/null 2>&1
[ "$(cat src/a/b__c.sh)/$(cat src/a__b/c.sh)" = "H1 one/H2 two" ] && ok "both hollowed files restored" || bad "a hollowed file was lost"
git checkout -q src

echo "-- non-colliding edit still restored"
echo EDIT >src/calc.sh
"$P" S4 true >/dev/null 2>&1
[ "$(cat src/calc.sh)" = EDIT ] && ok "plain edit restored" || bad "plain edit lost"

[ "$FAILS" -eq 0 ] || { echo "probe-stash: $FAILS failure(s)"; exit 1; }
echo "probe-stash: PASS"
