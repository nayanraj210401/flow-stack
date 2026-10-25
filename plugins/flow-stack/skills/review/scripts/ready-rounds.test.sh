#!/usr/bin/env bash
# ready-rounds.test.sh: the third reviewed commit on a branch without ship says to challenge the approach.
# Rounds count review rows on this branch's commits only, so other branches don't add to them.
set -uo pipefail
R="$(cd "$(dirname "$0")" && pwd)/ready.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/ready-rounds.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
cd "$SB/repo" && git init -q -b main && git config user.email a@b && git config user.name a
mkdir -p .flow
commit() { echo "$1" >>f && git add f && git commit -qm "$1"; }
commit base
git checkout -q -b other && commit other && "$R" record review fix-first >/dev/null
git checkout -q main && git checkout -q -b work

commit one; out1="$("$R" record review fix-first 2>&1)"
again="$("$R" record review fix-first 2>&1)"
commit two; out2="$("$R" record review fix-first 2>&1)"
commit three; out3="$("$R" record review fix-first 2>&1)"

grep -q 'round 1' <<<"$out1" && ok "first review is round 1 (the other branch doesn't count)" || bad "round 1 missing: $out1"
grep -q "git diff $(git rev-parse --short=7 HEAD~2)..HEAD" <<<"$out1" && ok "round 1 names the re-review range" || bad "no re-review range: $out1"
grep -q 'round 1' <<<"$again" && ok "the same commit reviewed twice is still round 1" || bad "re-record counted: $again"
grep -q 'challenge' <<<"$out2" && bad "round 2 already says challenge: $out2" || ok "round 2 doesn't say challenge"
grep -q 'round 3 without ship: stop patching findings; run the challenge skill' <<<"$out3" \
  && ok "round 3 without ship says challenge" || bad "round 3 lacks the directive: $out3"
[ "$("$R" rounds)" = 3 ] && ok "ready.sh rounds prints 3" || bad "ready.sh rounds: $("$R" rounds)"
grep -q 'challenge' <<<"$("$R" record review ship)" && bad "ship at round 3 says challenge" || ok "ship at round 3: no challenge"
commit four; "$R" record review ship >/dev/null
commit five; out5="$("$R" record review fix-first 2>&1)"
grep -q 'round 1' <<<"$out5" && ! grep -q 'challenge' <<<"$out5" \
  && ok "after ships, the next slice's first fix-first is round 1" || bad "ships counted as fix rounds: $out5"

[ "$FAILS" = 0 ] || { echo "== ready-rounds · FAIL ($FAILS)"; exit 1; }
echo "== ready-rounds · PASS"
