#!/usr/bin/env bash
# hardstop-text.test.sh: guard.sh's recursive-rm and force-push stops judge commands, not text.
# Quoted strings, commit messages and heredoc bodies that name them pass; real invocations,
# wrapped or after a heredoc, are still stopped (#74).
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/hardstop-text.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR" "$SB/repo"
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
  [ "$got" = "$1" ] && ok "$1: ${2//$'\n'/⏎}" || bad "${2//$'\n'/⏎} → $got, want $1"
}

echo "-- text that names a stopped command passes"
expect allow $'cat > notes.md <<\'EOF\'\nthe rm -rf / guard\nEOF'
expect allow $'cat > notes.md <<EOF\nblock git push --force origin main\nEOF'
expect allow "git commit -m 'block git push --force origin main'"
expect allow 'git commit -m "fix: rm -rf ~ hard stop"'
expect allow 'echo "rm -rf /"'
expect allow 'echo the rm -rf / guard'
expect allow 'echo "rm -rf $DIR is risky"'
echo "-- real invocations are still stopped"
expect deny 'rm -rf /'
expect deny 'sudo rm -rf /'
expect deny "bash -c 'rm -rf /'"
expect deny 'x=1; rm -rf ~'
expect deny 'if true; then rm -rf /; fi'
expect deny 'echo $(rm -rf /)'
expect deny 'echo `rm -rf /`'
expect deny $'cat > n.md <<EOF\nhi\nEOF\nrm -rf /'
expect ask 'rm -rf $DIR'
expect deny 'git push --force origin main'
expect deny 'GIT_TRACE=1 git push -f origin main'
expect deny "sh -c 'git push --force origin main'"
expect deny $'cat > n.md <<EOF\nhi\nEOF\ngit push -f origin main'
expect ask 'git push -f origin feat/x'

[ "$FAILS" -eq 0 ] && { echo "== hardstop-text · PASS"; exit 0; }
echo "== hardstop-text · FAIL ($FAILS)"; exit 1
