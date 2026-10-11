#!/usr/bin/env bash
# mcp-writers.test.sh: MCP file writers (serena) get edit-guard's checks like Edit/Write do:
# hooks.json routes them to it, and it reads their relative_path / content / needle+repl.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/mcpwrite.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR" "$SB/repo/.flow/tasks/x" "$SB/repo/src" "$SB/repo/tests"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID
cd "$SB/repo"
git init -q && git config user.email a@b && git config user.name a
echo x >.flow/ACTIVE
printf '# Intent\n## Goal\ng\n' >.flow/tasks/x/INTENT.md
printf '## S1 a\nstatus: doing\nfence: src/** tests/**\n\n## S2 b\nstatus: todo\nfence: src/**\n' >.flow/tasks/x/SLICES.md
echo t >tests/t.sh
printf 'sha\ttests/t.sh\n' >.flow/tasks/x/SEALS
git add -A && git commit -qm i
SL=.flow/tasks/x/SLICES.md

echo "-- hooks.json routes MCP writers to edit-guard, not MCP readers"
routed() { jq -r --arg t "$1" '[.hooks.PreToolUse[] | select(any(.hooks[].command; test("edit-guard"))) | .matcher] | any(.[]; . as $m | $t | test("^(" + $m + ")$"))' "$H/hooks.json"; }
for t in mcp__serena__create_text_file mcp__serena__replace_content mcp__serena__replace_symbol_body mcp__serena__insert_after_symbol; do
  [ "$(routed "$t")" = true ] && ok "$t routed" || bad "$t not routed to edit-guard"
done
[ "$(routed mcp__serena__find_symbol)" = false ] && ok "find_symbol not routed" || bad "find_symbol routed to edit-guard"

# eg <tool> <tool_input json>: the hook's decision
eg() {
  jq -nc --arg c "$PWD" --argjson ti "$2" --arg t "$1" \
    '{hook_event_name:"PreToolUse", session_id:"s", cwd:$c, tool_name:$t, tool_input:$ti}' |
    "$H/edit-guard.sh" | { jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true; } | { read -r d; echo "${d:-allow}"; }
}
want() { # want <decision> <label> <serena tool> <tool_input>
  local got; got="$(eg "mcp__serena__$3" "$4")"
  [ "$got" = "$1" ] && ok "$2 → $got" || bad "$2: got $got, want $1"
}

echo "-- edit-guard judges serena's relative_path"
want deny  "create_text_file outside the fence" create_text_file '{"relative_path":"docs/a.md","content":"x"}'
want allow "create_text_file inside the fence" create_text_file '{"relative_path":"src/a.py","content":"x"}'
want ask   "replace_symbol_body in a sealed test" replace_symbol_body '{"relative_path":"tests/t.sh","name_path":"f","body":"x"}'
want deny  "replace_content marking a slice done" replace_content "{\"relative_path\":\"$SL\",\"needle\":\"status: todo\",\"repl\":\"status: done\",\"mode\":\"literal\"}"
want deny  "regex replace_content on SLICES.md" replace_content "{\"relative_path\":\"$SL\",\"needle\":\"(d)oing\",\"repl\":\"\$!1one\",\"mode\":\"regex\"}"
want deny  "create_text_file with a done slice" create_text_file "$(jq -nc --arg p "$SL" --rawfile c "$SL" '{relative_path:$p, content:($c | sub("status: todo"; "status: done"))}')"
want allow "literal replace_content of another field" replace_content "{\"relative_path\":\"$SL\",\"needle\":\"fence: src/**\\n\",\"repl\":\"fence: src/a\\n\",\"mode\":\"literal\"}"

[ "$FAILS" = 0 ] && echo "== mcp-writers · PASS" || { echo "== mcp-writers · FAIL ($FAILS)"; exit 1; }
