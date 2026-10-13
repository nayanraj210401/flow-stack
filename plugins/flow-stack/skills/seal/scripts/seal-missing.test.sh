#!/usr/bin/env bash
# seal-missing.test.sh: `seal.sh add` of a nonexistent path exits non-zero (#99).
set -uo pipefail
S="$(cd "$(dirname "$0")" && pwd)/seal.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/seal-missing.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
cd "$SB/repo" && git init -q && git config user.email a@b && git config user.name a
mkdir -p .flow/tasks/x; echo x >.flow/ACTIVE; echo hi >t.sh
git add -A && git commit -qm i

"$S" add nope.sh >/dev/null 2>&1 && bad "missing file exited 0" || ok "missing file exits non-zero"
"$S" add t.sh >/dev/null 2>&1 && ok "existing file seals, exit 0" || bad "existing file failed"
"$S" add t.sh nope.sh >/dev/null 2>&1 && bad "mixed list exited 0" || ok "mixed list exits non-zero"
"$S" verify | grep -q 'seals intact (1 files)' && ok "the existing file stays sealed" || bad "seal lost"
[ "$FAILS" = 0 ] || { echo "$FAILS failed"; exit 1; }
echo "all passed"
