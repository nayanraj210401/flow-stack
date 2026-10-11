#!/usr/bin/env bash
# slice-done-multiedit.test.sh: edit-guard denies marking a slice done by hand, through Edit,
# Write and MultiEdit alike. Runs the working tree's hook in a throwaway toy repo and home.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/slicedone.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR" "$SB/repo/.flow/tasks/x" "$SB/repo/src"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID
cd "$SB/repo"
git init -q && git config user.email a@b && git config user.name a
echo x >.flow/ACTIVE
printf '# Intent\n## Goal\ng\n' >.flow/tasks/x/INTENT.md
printf '## S1 a\nstatus: doing\nfence: src/**\n\n## S2 b\nstatus: todo\nfence: src/**\n' >.flow/tasks/x/SLICES.md
git add -A && git commit -qm i
SF="$PWD/.flow/tasks/x/SLICES.md"

# eg <tool> <tool_input json>: the hook's decision
eg() {
  jq -nc --arg c "$PWD" --argjson ti "$2" --arg t "$1" \
    '{hook_event_name:"PreToolUse", session_id:"s", cwd:$c, tool_name:$t, tool_input:$ti}' |
    "$H/edit-guard.sh" | { jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true; } | { read -r d; echo "${d:-allow}"; }
}
want() { # want <decision> <label> <tool> <tool_input>
  local got; got="$(eg "$3" "$4")"
  [ "$got" = "$1" ] && ok "$2 → $got" || bad "$2: got $got, want $1"
}
edits() { jq -nc --arg f "$SF" --argjson e "$1" '{file_path:$f, edits:$e}'; }

echo "-- marking a slice done by hand is denied"
want deny "Edit to done" Edit "$(jq -nc --arg f "$SF" '{file_path:$f, old_string:"status: todo", new_string:"status: done"}')"
want deny "MultiEdit to done" MultiEdit "$(edits '[{"old_string":"status: todo","new_string":"status: done"}]')"
want deny "MultiEdit, done in a later edit" MultiEdit "$(edits '[{"old_string":"fence: src/**","new_string":"fence: src/a"},{"old_string":"status: todo","new_string":"status: done"}]')"

echo "-- other SLICES.md edits stay allowed"
want allow "Edit another field" Edit "$(jq -nc --arg f "$SF" '{file_path:$f, old_string:"fence: src/**", new_string:"fence: src/a"}')"
want allow "MultiEdit another field" MultiEdit "$(edits '[{"old_string":"fence: src/**","new_string":"fence: src/a"}]')"
want allow "MultiEdit leaving a done line as it was" MultiEdit "$(edits '[{"old_string":"status: done","new_string":"status: done"}]')"

[ "$FAILS" = 0 ] && echo "== slice-done-multiedit · PASS" || { echo "== slice-done-multiedit · FAIL ($FAILS)"; exit 1; }
