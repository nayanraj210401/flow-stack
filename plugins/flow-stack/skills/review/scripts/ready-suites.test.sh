#!/usr/bin/env bash
# ready-suites.test.sh: ready.sh runs the impacted tests.suites, a failing one blocks the stamp, and
# with no base to diff against it runs the full suite instead of passing on nothing.
set -uo pipefail
R="$(cd "$(dirname "$0")" && pwd)/ready.sh"
FAILS=0
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/ready-suites.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
cd "$SB/repo" && git init -q -b trunk && git config user.email a@b && git config user.name a
mkdir -p .flow src/a src/b
echo a >src/a/x && echo b >src/b/x
jq -n '{tests: {suites: [{id: "a", paths: ["src/a/**"], run: "grep -q zzz src/a/x"}, {id: "b", paths: ["src/b/**"], run: "test -f src/b/x"}]}}' >.flow/config.json
git add -A && git commit -qm i
base="$(git rev-parse HEAD)"

echo b2 >>src/b/x && git commit -qam b
out="$("$R" -v --base "$base" </dev/null 2>&1)"
grep -q '✓ impacted test suites' <<<"$out" || bad "passing impacted suite b → ✓: $out"

echo a2 >>src/a/x && git commit -qam a
out="$("$R" -v --base "$base" </dev/null 2>&1)"
grep -q '✗ impacted test suites' <<<"$out" || bad "failing impacted suite a blocks: $out"

git reset -q --hard HEAD~1   # only b changed, but there's no main/master/origin to diff against
out="$("$R" -v </dev/null 2>&1)"
grep -q '✗ impacted test suites' <<<"$out" || bad "no base → full suite (a fails), not a pass on nothing: $out"

[ "$FAILS" = 0 ] || { echo "== ready-suites · FAIL ($FAILS)"; exit 1; }
echo "== ready-suites · PASS"
