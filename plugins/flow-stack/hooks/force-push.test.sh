#!/usr/bin/env bash
# force-push.test.sh: guard.sh denies a force-push to main/master however the flags are spelled,
# asks for any other force-push, and leaves ordinary pushes alone. Runs the working tree's hook.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/force-push.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID
cd "$SB/repo" && git init -q

decide() {
  local out
  out="$(jq -nc --arg c "$PWD" --arg cmd "$1" '{hook_event_name:"PreToolUse",session_id:"s",cwd:$c,tool_name:"Bash",tool_input:{command:$cmd}}' | "$H/guard.sh")"
  [ -n "$out" ] || { echo allow; return; }
  jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out"
}
expect() { # expect <want> <command>
  local got; got="$(decide "$2")"
  [ "$got" = "$1" ] && ok "$1: $2" || bad "$2 → $got, want $1"
}

echo "-- force-push to main/master: deny"
expect deny 'git push --force origin main'
expect deny 'git push origin main --force'
expect deny 'git -C . push --force origin main'
expect deny 'git -c user.name=x push --force origin main'
expect deny 'git push -fu origin main'
expect deny 'git push -uf origin master'
expect deny 'git push origin +main'
expect deny 'git push origin HEAD:+main'
expect deny 'git push origin HEAD:refs/heads/main -f'
expect deny 'git push origin refs/heads/main --force'
echo "-- force-push elsewhere: ask"
expect ask 'git push -f origin feat/x'
expect ask 'git -C . push -f origin feat/x'
expect ask 'git -c k=v push -fu origin feat/x'
expect ask 'git push origin +feat/x'
expect ask 'git push -f origin feature/main'
expect ask 'git push --force origin HEAD:refs/heads/feature/main'
expect ask 'git push --force-with-lease origin feat/x'
echo "-- ordinary pushes: allow"
expect allow 'git push origin main'
expect allow 'git push -u origin main'
expect allow 'git push -u origin feat/maintenance'

[ "$FAILS" -eq 0 ] && { echo "force-push: PASS"; exit 0; }
echo "force-push: FAIL ($FAILS)"; exit 1
