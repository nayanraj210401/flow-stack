#!/usr/bin/env bash
# seal-deleted.test.sh: `seal.sh add <dir>` skips tracked-but-deleted files and never writes a hashless seal (#133).
set -uo pipefail
S="$(cd "$(dirname "$0")" && pwd)/seal.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/seal-deleted.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
cd "$SB/repo" && git init -q && git config user.email a@b && git config user.name a
mkdir -p .flow/tasks/x tests; echo x >.flow/ACTIVE; echo a >tests/a.sh; echo b >tests/b.sh
git add -A && git commit -qm i
rm tests/b.sh

out="$("$S" add tests 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "the existing file seals, exit 0" || bad "exit $rc: $out"
case "$out" in *"sealed: tests/b.sh"*) bad "announced the deleted file" ;; *) ok "deleted file not announced" ;; esac
[ "$(wc -l <.flow/tasks/x/SEALS | tr -d ' ')" = 1 ] && ok "one seal line" || bad "SEALS: $(cat .flow/tasks/x/SEALS)"
grep -Eq '^[0-9a-f]{64}  ' .flow/tasks/x/SEALS && ok "the seal has a hash" || bad "hashless seal"
"$S" verify | grep -q 'seals intact (1 files)' && ok "verify counts 1 file" || bad "verify count wrong"
[ "$FAILS" = 0 ] || { echo "== seal-deleted · FAIL ($FAILS)"; exit 1; }
echo "== seal-deleted · PASS"
