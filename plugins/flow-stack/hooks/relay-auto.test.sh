#!/usr/bin/env bash
# relay-auto.test.sh: --auto / --no-auto count only in the human's own words. Relayed hand-backs (Claude Code's
# <agent-message> and <task-notification>, T3 Code's "Delegated task node:" reports and "Update on pull request"
# watches, system reminders) arrive as prompts too and must not flip the mode. Runs the working tree's anchor.sh.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/relay-auto.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude"
mkdir -p "$FLOW_STACK_HOME" "$SB/repo" && cd "$SB/repo" && git init -q
unset GITHUB_ACTIONS GITHUB_RUN_ID RUNNER_ENVIRONMENT

send() { jq -nc --arg p "$2" --arg c "$PWD" --arg s "$1" '{hook_event_name:"UserPromptSubmit",session_id:$s,cwd:$c,prompt:$p}' | "$H/anchor.sh" >/dev/null; }
is_auto() { [ -f "$FLOW_STACK_HOME/auto/$1" ]; }
off_after() { send "$1" "$2"; is_auto "$1" && bad "$3 turned auto on" || ok "$3 stays off"; }

off_after a "$(printf 'Delegated task node:delegated-task:x (#183 mention routine) [completed]:\nruns /flow-stack:flow --auto ship with the plugin')" "a T3 delegate report quoting --auto ship"
off_after b "$(printf 'Update on pull request #199 (https://x/pull/199):\n- 1 new comment: run it with --auto')" "a T3 PR-watch update quoting --auto"
off_after c "$(printf '<system-reminder>\nthe lead used --auto\n</system-reminder>')" "a system reminder quoting --auto"
off_after d "$(printf '<task-notification>\nran with --auto\n</task-notification>')" "a task notification quoting --auto"

send e "--auto"; is_auto e && ok "a bare --auto from the human turns it on" || bad "bare --auto ignored"
send e "--no-auto I'm back"; is_auto e && bad "--no-auto ignored" || ok "--no-auto turns it off"

[ "$FAILS" -eq 0 ] && echo "== relay-auto · PASS" || { echo "== relay-auto · FAIL ($FAILS)"; exit 1; }
