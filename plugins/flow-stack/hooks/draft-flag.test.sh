#!/usr/bin/env bash
# draft-flag.test.sh: the ready gate exempts a real draft flag, not "-d" inside a quoted title/body (#60), nor --draft=false (#122),
# including a draft wrapped in sh -c '…'.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/draft-flag.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
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

expect deny  'gh pr create --title x'
expect deny  'gh pr create --title "fix -d flag handling" --body x'
expect deny  "gh pr create --title x --body 'use -d here'"
expect deny  'gh pr create --title x --body "multi-line with -d
  here"'
expect deny  'gh pr create --title "a \" -d"'
expect deny  "gh pr create --title \$'a\\' -d'"
expect deny  'gh pr create --title fix\ -d'
expect allow 'gh pr create --draft --title x'
expect allow 'gh pr create -d --title x'
expect allow 'gh pr create --title "fix -d" --draft'
expect allow 'gh pr create --draft=true --title x'
expect deny  'gh pr create --draft=false'
expect deny  'gh pr create --title x --draft=false'
expect deny  'gh pr create --draft=false --title x'
# Wrapped in a quoted shell string: the wrapper's quote is not a quoted title.
expect allow "sh -c 'gh pr create --draft --title x'"
expect allow "bash -lc \"gh pr create -d --title x\""
expect deny  "sh -c 'gh pr create --title x'"
expect deny  "sh -c 'gh pr create --title \"a -d\" --body x'"
expect allow "sh -c 'gh pr create --draft'"
expect allow "eval \"gh pr create --title 'a -d' --draft\""
expect deny  'bash -c "gh pr create --body \"fix -d flag\" --title x"'
expect deny  "sh -c \"gh pr create --title 'x' --body \\\"y --draft z\\\"\""
# Every gh pr create/ready on the line needs its own draft flag; quoted text naming one doesn't count.
expect deny  "sh -c 'gh pr create --draft --title x' && gh pr create --title y"
expect deny  'gh pr create --draft --title x && gh pr create --title y'
expect deny  "echo 'gh pr create --draft x' && gh pr create --title x"
expect deny  "grep 'gh pr create -d foo' f; gh pr create --title x"
# Commands the split can't see into fail closed instead of riding on a draft elsewhere on the line.
expect deny  'gh pr create --draft; `gh pr create --title x`'
expect deny  'gh pr create --draft --title "$(gh pr create --title y)"'
expect deny  "gh pr create --draft; bash -c -e 'gh pr create --title x'"
expect deny  "gh pr create --draft; X=1 eval 'gh pr create --title x'"
expect deny  'gh pr create --title x # --draft'
expect allow 'gh pr create --draft --title x # opened as a draft'
expect deny  'gh pr create --title x "--draf\t"'
# A draft whose own text names the command is still a draft.
expect allow 'gh pr create --draft --title "docs: explain gh pr create flags"'
expect allow 'gh pr create --draft --title x --body "Run gh pr ready when done"'
expect allow 'git commit -m "guard: handle gh pr create" && gh pr create --draft --title x'
expect allow "gh pr create --draft --title x --body 'Fixes: gh pr create --draft wrapped in sh -c'"
expect allow 'gh pr create --title x \
--draft'
expect deny  "bash -c \$'gh pr create --title \\'a -d\\''"
expect allow "bash -c \$'gh pr create --title x --draft'"

[ "$FAILS" -eq 0 ] && echo "ok" || { echo "$FAILS failed"; exit 1; }
