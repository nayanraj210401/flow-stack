#!/usr/bin/env bash
# discard-git.test.sh: the ready gate exempts a real draft flag, not "-d" inside a quoted title/body (#60).
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/discard-git.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID
cd "$SB/repo" && git init -q && git config user.email a@b && git config user.name a
mkdir -p .flow/tasks/x; echo x >.flow/ACTIVE
printf '# Intent\n## Goal\ng\n' >.flow/tasks/x/INTENT.md
git add -A && git commit -qm i

decide() {
  local out
  out="$(jq -nc --arg c "$PWD" --arg cmd "$1" '{hook_event_name:"PreToolUse",session_id:"s",cwd:$c,tool_name:"Bash",tool_input:{command:$cmd}}' | "$H/guard.sh")"
  [ -n "$out" ] || { echo allow; return; }
  jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out"
}
expect() { local got; got="$(decide "$2")"; [ "$got" = "$1" ] && ok "$1: $2" || bad "$2 → $got, want $1"; }


expect ask   'git reset --hard'
expect ask   'git clean -fd'
expect ask   'git -C . reset --hard'
expect ask   'git -c x=y clean -fd'
expect ask   'git clean -d -f'
expect ask   'git clean --force -d'
expect ask   'git -C . clean -d --force'
expect ask   'git reset --hard HEAD~1'
expect allow 'git reset --soft HEAD~1'
expect allow 'git clean -n'
expect allow 'git clean -nd'
expect allow 'git -C . status'
expect allow 'git reset HEAD file'

[ "$FAILS" -eq 0 ] && echo "ok" || { echo "$FAILS failed"; exit 1; }
