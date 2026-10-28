#!/usr/bin/env bash
# mode-spoof.test.sh: the model can't fake a mode. Writes to the auto-mode flags ($FLOW_STACK_HOME/auto/) are
# denied from Bash and Edit/Write; writes to Claude Code settings (where an env block could fake a GitHub runner
# for --gha) need the human. Reading them stays allowed. Interpreter one-liners (python -c, node -e) are a
# known gap: a regex can't see their writes, and --gha itself re-checks the runner. Runs the working tree's hooks.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/mode-spoof.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME/auto" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo/.claude"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID GITHUB_ACTIONS GITHUB_RUN_ID RUNNER_ENVIRONMENT RUNNER_TEMP
cd "$SB/repo" && git init -q

decide() { # decide <hook> <tool_input json> [tool]
  local out
  out="$(jq -nc --arg c "$PWD" --arg t "${3:-Bash}" --argjson i "$2" '{hook_event_name:"PreToolUse",session_id:"s",cwd:$c,tool_name:$t,tool_input:$i}' | "$H/$1")"
  [ -n "$out" ] || { echo allow; return; }
  jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out"
}
bash_is() { local got; got="$(decide guard.sh "$(jq -nc --arg c "$2" '{command:$c}')")"; [ "$got" = "$1" ] && ok "$1: $2" || bad "$2 → $got, want $1"; }
edit_is() { local got; got="$(decide edit-guard.sh "$(jq -nc --arg f "$2" '{file_path:$f,content:"x"}')" Write)"; [ "$got" = "$1" ] && ok "$1: Write $2" || bad "Write $2 → $got, want $1"; }

echo "-- auto-mode flags: writes denied"
bash_is deny "echo ship > $FLOW_STACK_HOME/auto/s"
bash_is deny 'printf ship >~/.flow-stack/auto/s'
bash_is deny 'echo ship | tee "$FLOW_STACK_HOME/auto/s"'
bash_is deny 'cd ~/.flow-stack && echo ship > auto/s'
bash_is deny "cp /tmp/x $FLOW_STACK_HOME/auto/s"
edit_is deny "$FLOW_STACK_HOME/auto/s"
edit_is deny "$FLOW_STACK_HOME//auto/s"
edit_is deny "$FLOW_STACK_HOME/x/../auto/s"
echo "-- Claude Code settings: writes ask"
bash_is ask "jq '.env.GITHUB_ACTIONS=\"true\"' x > .claude/settings.local.json"
bash_is ask "sed -i '' 's/a/b/' .claude/settings.json"
bash_is ask 'cp /tmp/s.json ~/.claude/settings.json'
bash_is ask 'cd .claude && echo x > settings.local.json'
bash_is ask 'echo x > $CLAUDE_CONFIG_DIR/settings.json'
edit_is ask "$SB/repo/.claude/settings.local.json"
edit_is ask "$HOME/.claude/settings.json"
edit_is ask "$CLAUDE_CONFIG_DIR/settings.json"
edit_is ask "$SB/repo/.claude/x/../settings.json"
echo "-- reads and unrelated writes: allow"
bash_is allow "cat $FLOW_STACK_HOME/auto/s"
bash_is allow 'ls ~/.flow-stack/auto'
bash_is allow 'jq .env .claude/settings.json'
bash_is allow 'echo hi > notes.txt'
bash_is allow 'git add .claude/settings.json'
bash_is allow 'git log --format=%H -- .claude/settings.json'
bash_is allow 'grep -n addDirectories ~/.claude/settings.json'
bash_is allow 'rg -n ddd ~/.flow-stack/auto/s'
bash_is allow 'cd ~/.flow-stack && cat auto/s'
edit_is allow "$SB/repo/notes.txt"
edit_is allow "$SB/repo/.claude/agents/x.md"

[ "$FAILS" = 0 ] && echo "mode-spoof.test.sh: pass" || { echo "mode-spoof.test.sh: $FAILS failed"; exit 1; }
