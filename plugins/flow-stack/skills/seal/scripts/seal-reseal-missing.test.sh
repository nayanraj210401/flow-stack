#!/usr/bin/env bash
# seal-reseal-missing.test.sh: `seal.sh reseal` keeps the seal of a deleted file and fails (#138).
set -uo pipefail
S="$(cd "$(dirname "$0")" && pwd)/seal.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/seal-reseal.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
cd "$SB/repo" && git init -q && git config user.email a@b && git config user.name a
mkdir -p .flow/tasks/x; echo x >.flow/ACTIVE; echo hi >a.sh; echo yo >b.sh
git add -A && git commit -qm i
"$S" add a.sh b.sh >/dev/null 2>&1

rm b.sh; echo changed >a.sh
out="$("$S" reseal 2>&1)"; code=$?
[ "$code" != 0 ] && ok "reseal exits non-zero with a sealed file missing" || bad "reseal exited 0"
grep -q 'MISSING b.sh' <<<"$out" && ok "reseal names the missing file" || bad "no MISSING line: $out"
v="$("$S" verify 2>&1)"
grep -Eq 'MISSING +b.sh' <<<"$v" && ok "verify still reports MISSING" || bad "seal was laundered"
grep -Eq 'CHANGED +a.sh' <<<"$v" && bad "a.sh not resealed" || ok "the existing file is resealed"
"$S" rm b.sh >/dev/null 2>&1; "$S" reseal >/dev/null 2>&1 && ok "after rm, reseal exits 0" || bad "reseal still fails after rm"
[ "$FAILS" = 0 ] || { echo "== seal-reseal-missing · FAIL ($FAILS)"; exit 1; }
echo "== seal-reseal-missing · PASS"
