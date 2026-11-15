#!/usr/bin/env bash
# hook-off-warn.test.sh: turning a flow-stack hook off warns (you and the agent) but is never blocked, even
# in --auto: settings.sh hook <name> off, shell writes to ~/.flow-stack/{settings,config}.json, and Edit/Write
# of those files. A compound command still gets guard's later checks. Runs the working tree's hooks.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/hook-off-warn.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME/auto" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID GITHUB_ACTIONS GITHUB_RUN_ID RUNNER_ENVIRONMENT RUNNER_TEMP
cd "$SB/repo" && git init -q

run() { # run <hook> <tool> <tool_input json>: the hook's JSON output
  jq -nc --arg c "$PWD" --arg t "$2" --argjson i "$3" '{hook_event_name:"PreToolUse",session_id:"s",cwd:$c,tool_name:$t,tool_input:$i}' | "$H/$1"
}
sh_in() { jq -nc --arg c "$1" '{command:$c}'; }
warns() { # warns <label> <output>: a warning for both, and no permission decision
  grep -q 'turns off' <<<"$(jq -r '.systemMessage // empty' <<<"$2")" || bad "$1: no systemMessage: $2"
  grep -q 'turns off' <<<"$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$2")" || bad "$1: no additionalContext: $2"
  [ -z "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$2")" ] || bad "$1: decided instead of warning: $2"
}
silent() { [ -z "$2" ] || bad "$1: expected no output, got $2"; }

S=plugins/flow-stack/skills/settings/scripts/settings.sh
warns "settings.sh hook guard off" "$(run guard.sh Bash "$(sh_in "bash $S hook guard off")")"
warns "settings.sh hook claims off --repo" "$(run guard.sh Bash "$(sh_in "$S hook claims off --repo")")"
warns "redirect into settings.json" "$(run guard.sh Bash "$(sh_in "echo '{\"hooks\":{\"fence\":false}}' > $FLOW_STACK_HOME/settings.json")")"
warns "jq rewrite of config.json via mv" "$(run guard.sh Bash "$(sh_in "jq . x > t && mv t ~/.flow-stack/config.json")")"
warns "Write settings.json" "$(run edit-guard.sh Write "$(jq -nc --arg f "$FLOW_STACK_HOME/settings.json" '{file_path:$f,content:"{}"}')")"

mkdir -p .flow
warns "settings.sh hook guard default" "$(run guard.sh Bash "$(sh_in "$S hook guard default --repo")")"
warns "redirect into repo .flow/config.json" "$(run guard.sh Bash "$(sh_in "echo '{\"hooks\":{\"guard\":false}}' > .flow/config.json")")"
warns "jq + mv of repo .flow/config.json" "$(run guard.sh Bash "$(sh_in "jq '.hooks.guard = false' .flow/config.json > t && mv t .flow/config.json")")"
warns "Edit repo .flow/config.json to false" "$(run edit-guard.sh Edit "$(jq -nc --arg f "$PWD/.flow/config.json" '{file_path:$f,old_string:"true",new_string:"\"guard\": false"}')")"
silent "Edit repo .flow/config.json commands" "$(run edit-guard.sh Edit "$(jq -nc --arg f "$PWD/.flow/config.json" '{file_path:$f,old_string:"a",new_string:"\"test\": \"npm test\""}')")"
silent "Edit repo .flow/config.json, replace_all false" "$(run edit-guard.sh Edit "$(jq -nc --arg f "$PWD/.flow/config.json" '{file_path:$f,old_string:"a",new_string:"\"run\": \"x\"",replace_all:false}')")"
silent "Edit repo .flow/config.json false → true" "$(run edit-guard.sh Edit "$(jq -nc --arg f "$PWD/.flow/config.json" '{file_path:$f,old_string:"\"fence\": false",new_string:"\"fence\": true"}')")"
silent "Edit a nested .flow/config.json (fence and tdd judge it)" "$(run edit-guard.sh Edit "$(jq -nc --arg f "$PWD/packages/api/.flow/config.json" '{file_path:$f,old_string:"a",new_string:"\"guard\": false"}')")"
ln -s "$PWD" "$SB/link"
warns "Edit .flow/config.json via a symlinked repo path" "$(run edit-guard.sh Edit "$(jq -nc --arg f "$SB/link/.flow/config.json" '{file_path:$f,old_string:"a",new_string:"\"guard\": false"}')")"
warns "serena replace_content into .flow/config.json" "$(run edit-guard.sh mcp__serena__replace_content '{"relative_path":".flow/config.json","needle":"true","repl":"false","mode":"literal"}')"
silent "commit message naming the command" "$(run guard.sh Bash "$(sh_in 'git commit -m "docs: settings.sh hook guard off now warns"')")"
silent "jq rewrite of repo commands" "$(run guard.sh Bash "$(sh_in "jq '.commands.test = \"x\"' .flow/config.json > t && mv t .flow/config.json")")"
silent "settings.sh hook guard on" "$(run guard.sh Bash "$(sh_in "$S hook guard on")")"
silent "settings.sh show" "$(run guard.sh Bash "$(sh_in "$S show")")"
silent "reading settings.json" "$(run guard.sh Bash "$(sh_in "cat $FLOW_STACK_HOME/settings.json")")"

# a later check still fires: the warning doesn't end guard early
out="$(run guard.sh Bash "$(sh_in "$S hook guard off && git push --force origin main")")"
[ -n "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$out")" ] || bad "hook off && force push → still decided by guard: $out"

# an earlier check that decides still names the hook going off
out="$(run guard.sh Bash "$(sh_in "$S hook seal off && git reset --hard")")"
grep -q 'turns off the seal hook' <<<"$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$out")" || bad "hook off && reset --hard → the decision names the hook: $out"

# --auto: still a warning, not a queued deny
echo on >"$FLOW_STACK_HOME/auto/s"
warns "--auto settings.sh hook guard off" "$(run guard.sh Bash "$(sh_in "$S hook guard off")")"

[ "$FAILS" = 0 ] || { echo "== hook-off-warn · FAIL ($FAILS)"; exit 1; }
echo "== hook-off-warn · PASS"
