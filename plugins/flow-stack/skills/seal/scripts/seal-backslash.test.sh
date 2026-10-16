#!/usr/bin/env bash
# seal-backslash.test.sh: a sealed path containing a backslash matches its own SEALS line in
# seal.sh add/rm and edit-guard (awk -v unescaped it, #73). probe.sh gets the same fix, but git
# quotes such names in its diff (#35), so it is not exercised here.
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"; PLUGIN="$(cd "$D/../../.." && pwd)"
SEAL="$D/seal.sh"; T="$PLUGIN/skills/flow/scripts/task.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/seal-backslash.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR" "$SB/repo"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID FLOW_SESSION_PID
cd "$SB/repo"
# shellcheck source=/dev/null
. "$PLUGIN/evals/_lib/toy.sh"
toy_repo
"$T" new bs bug >/dev/null
S=".flow/tasks/bs/SEALS"
f='src/a\nb.txt'
echo old >"$f"; git add -A; git commit -qm f

echo "-- add writes the path as given, and re-adding replaces it"
"$SEAL" add "$f" >/dev/null; "$SEAL" add "$f" >/dev/null
[ "$("$SEAL" list)" = "$f" ] && ok "one seal, exact path" || bad "SEALS: $(cat "$S")"

echo "-- edit-guard sees it sealed"
d="$(jq -nc --arg c "$PWD" --arg p "$PWD/$f" '{hook_event_name:"PreToolUse",session_id:"s",cwd:$c,tool_name:"Write",tool_input:{file_path:$p,content:"x"}}' |
  "$PLUGIN/hooks/edit-guard.sh" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')"
[ "$d" = ask ] && ok "Write asks" || bad "Write → ${d:-allow}, want ask"

echo "-- rm finds it"
"$SEAL" rm "$f" >/dev/null 2>&1 && [ ! -s "$S" ] && ok "unsealed" || bad "rm failed: $(cat "$S")"

[ "$FAILS" -eq 0 ] && { echo "== seal-backslash · PASS"; exit 0; }
echo "== seal-backslash · FAIL ($FAILS)"; exit 1
