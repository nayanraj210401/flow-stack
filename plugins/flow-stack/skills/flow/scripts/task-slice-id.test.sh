#!/usr/bin/env bash
# task-slice-id.test.sh: `slice`/`tdd` match the id literally, not as a regex (#96).
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd)/task.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/task-slice-id.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
cd "$SB/repo" && git init -q && git config user.email a@b && git config user.name a && git commit -q --allow-empty -m i
"$T" new t bug >/dev/null || { echo "setup failed"; exit 1; }
F=.flow/tasks/t/SLICES.md
printf '# Slices\n\n## S1 · first\nstatus: todo\n\n## S2 · second\nstatus: todo\n' >"$F"
before="$(cat "$F")"

for id in 'S.' 'S[0-9]' '.*'; do
  out="$("$T" slice "$id" doing 2>&1)" && bad "slice '$id' exited 0: $out" || ok "slice '$id' rejected"
  [ "$(cat "$F")" = "$before" ] && ok "SLICES.md unchanged for '$id'" || bad "SLICES.md changed for '$id'"
done
"$T" tdd 'S.' red >/dev/null 2>&1 && bad "tdd 'S.' accepted" || ok "tdd 'S.' rejected"
"$T" slice S2 doing >/dev/null 2>&1 && grep -A1 '^## S2' "$F" | grep -q 'status: doing' && ok "a real id still works" || bad "S2 doing failed"
[ "$FAILS" = 0 ] || { echo "$FAILS failed"; exit 1; }
echo "all passed"
