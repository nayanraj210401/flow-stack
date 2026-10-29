#!/usr/bin/env bash
# guard-push.test.sh: pushes that delete or mirror remote refs ask; plain branch pushes stay allowed.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/guard-push.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions"
cd "$SB" && git init -q .

# check <want> <command>
check() {
  local out got
  out="$(jq -nc --arg cwd "$PWD" --arg c "$2" \
    '{cwd:$cwd, session_id:"s", hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}}' | bash "$H/guard.sh" 2>/dev/null)"
  got="allow"
  [ -z "$out" ] || got="$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out")"
  if [ "$got" = "$1" ]; then ok "$2 → $1"; else bad "$2 → got $got, want $1"; fi
}

check ask   'git push origin :main'
check ask   'git push origin :master'
check ask   'git push --delete origin main'
check ask   'git push origin --delete master'
check ask   'git push -d origin main'
check ask   'git push --mirror'
check deny  'git push --force origin main'
check allow 'git push origin feature'
check allow 'git push origin :feature'
check allow 'git push --delete origin feature'
check allow 'git push -u origin main-fix'

[ "$FAILS" -eq 0 ]
