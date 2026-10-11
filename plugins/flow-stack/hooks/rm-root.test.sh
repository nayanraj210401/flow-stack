#!/usr/bin/env bash
# rm-root.test.sh: guard.sh hard-stops a recursive rm of / or home however the flags are spelled
# (split, long, quoted $HOME) and leaves ordinary rm targets at their current decision.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"; PLUGIN="$(cd "$H/.." && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/rm-root.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR" "$SB/repo"
cd "$SB/repo"
# shellcheck source=/dev/null
. "$PLUGIN/evals/_lib/toy.sh"
toy_repo

# want <allow|deny|ask> <command>: the decision guard.sh gives that Bash command
want() {
  local out d
  out="$(jq -nc --arg cwd "$PWD" --arg c "$2" '{cwd:$cwd, hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}}' |
    "$H/guard.sh" 2>/dev/null)" || true
  d="allow"; [ -z "$out" ] || d="$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out")"
  if [ "$d" = "$1" ]; then ok "$2 → $1"; else bad "$2 → got $d, want $1"; fi
}

echo "-- root and home are never deleted"
want deny 'rm -rf /'
want deny 'rm -r -f /'
want deny 'rm -f -r /'
want deny 'rm --recursive --force /'
want deny 'rm -rf "$HOME"'
want deny 'rm -rf "${HOME}"'
want deny 'rm -r -f ~/'
want deny 'cd x && rm -rf --no-preserve-root /'

echo "-- other targets keep their decision"
want allow 'rm -rf ./build'
want allow 'rm -rf /tmp/x'
want allow 'rm -r -f build/ dist/'
want allow 'rm -f /'
want ask   'rm -rf "$HOME/tmp/x"'

[ "$FAILS" -eq 0 ] && { echo "== rm-root · PASS"; exit 0; }
echo "== rm-root · FAIL ($FAILS)"; exit 1
