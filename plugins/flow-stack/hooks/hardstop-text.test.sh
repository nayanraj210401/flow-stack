#!/usr/bin/env bash
# hardstop-text.test.sh: guard.sh's recursive-rm and force-push stops judge commands, not text.
# Only literal text is skipped: terminated heredoc bodies, and the quoted messages and echo/printf
# words that can't run (no $( or backticks, not piped). Every invocation is still stopped (#74).
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
expect deny '{ rm -rf /; }'
expect deny 'timeout 5 rm -rf /'
expect deny 'nice rm -rf ~'
expect deny 'find . -exec rm -rf / \;'
expect deny 'case x in x) rm -rf /;; esac'
expect deny 'timeout 9 git push -f origin main'
expect deny 'git push -f origin "main"'
expect deny 'echo rm -rf / | sh'
expect deny 'echo "$(rm -rf /)"'
expect deny $'cat <<EOF\n$(rm -rf /)\nEOF'
expect deny 'git commit -m "$(rm -rf /)"'
expect deny 'find . -exec echo {} + -exec rm -rf ~ +'
echo "-- a heredoc a shell runs is code"
expect deny $'bash <<\'EOF\'\nrm -rf ~\nEOF'
expect deny $'sh -s <<EOF\nrm -rf /\nEOF'
expect deny $'ssh host <<EOF\nrm -rf ~\nEOF'
expect deny $'cd x && bash <<EOF\ngit push -f origin main\nEOF'
expect allow $'git commit -F - <<\'EOF\'\nthe rm -rf / guard\nEOF'
expect allow $'cat <<EOF > n.md\nblock git push -f origin main\nEOF'
echo "-- << that starts no heredoc hides nothing"
expect deny $'echo " <<EOF"\nrm -rf /\nEOF'
expect deny $'echo $((1<<n))\nrm -rf /'
expect deny $'grep x <<<EOF\nrm -rf /'
expect deny $'git commit -m \'see <<EOF\'\nrm -rf /'
expect deny $'echo $((1<<n))\ngit push -f origin main'

[ "$FAILS" -eq 0 ] && { echo "== hardstop-text · PASS"; exit 0; }
echo "== hardstop-text · FAIL ($FAILS)"; exit 1
