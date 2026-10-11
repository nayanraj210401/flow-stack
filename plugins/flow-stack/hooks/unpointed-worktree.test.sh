#!/usr/bin/env bash
# unpointed-worktree.test.sh: a linked worktree with no flow-active/flow-lane pointer has no task
# (issue #66); a subagent spawned from the main checkout still joins main's task as a lane.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"; PLUGIN="$(cd "$H/.." && pwd)"
T="$PLUGIN/skills/flow/scripts/task.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/unpointed.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/main"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID FLOW_SESSION_PID
cd "$SB/main" && git init -q && git config user.email a@b && git config user.name a
echo 1 >app.ts; git add -A; git commit -qm i
"$T" new bughunt >/dev/null
printf '# Slices\n\n## S1 · notes\nstatus: doing\ncheck: test -s notes.md\nfence: notes.md\n' >.flow/tasks/bughunt/SLICES.md
git worktree add -q ../herdr-wt -b worktree/clear-harbor; W="$(cd ../herdr-wt && pwd -P)"
git worktree add -q ../sub-wt -b worker/sub; SW="$(cd ../sub-wt && pwd -P)"
M="$SB/main"
edit() { jq -nc --arg c "$1" --arg f "$1/app.ts" '{hook_event_name:"PreToolUse",session_id:"wt",cwd:$c,tool_name:"Edit",tool_input:{file_path:$f,old_string:"1",new_string:"2"}}'; }

echo "-- an unpointed worktree has no task"
[ -z "$(cd "$W" && "$T" active)" ] && ok "task.sh active is empty" || bad "active: '$(cd "$W" && "$T" active)'"
out="$(edit "$W" | "$H/edit-guard.sh" 2>/dev/null)"
case "$out" in *deny*) bad "edit-guard fenced the human's edit: $out" ;; *) ok "edit outside main's fence is not denied" ;; esac
[ ! -e "$(git -C "$W" rev-parse --absolute-git-dir)/flow-lane" ] && ok "no flow-lane written" || bad "flow-lane written"

echo "-- the main checkout and joined lanes keep working"
[ "$(cd "$M" && "$T" active)" = bughunt ] && ok "main still leads bughunt" || bad "main active"
jq -c '. + {agent_id:"a1"}' <<<"$(edit "$SW")" >"$SB/in.json"
echo '{"pid":4242,"cwd":"'"$M"'"}' >"$CLAUDE_CONFIG_DIR/sessions/4242.json"
FLOW_SESSION_PID=4242 "$H/edit-guard.sh" <"$SB/in.json" >/dev/null 2>&1
[ "$(head -n1 "$(git -C "$SW" rev-parse --absolute-git-dir)/flow-lane" 2>/dev/null)" = bughunt ] && ok "subagent of main joined bughunt" || bad "subagent did not join"
[ "$(cd "$SW" && "$T" active)" = bughunt ] && ok "joined worktree resolves bughunt" || bad "joined active: '$(cd "$SW" && "$T" active)'"
out="$(edit "$SW" | "$H/edit-guard.sh" 2>/dev/null)"
case "$out" in *deny*) ok "joined lane is fenced" ;; *) bad "joined lane not fenced: $out" ;; esac

[ "$FAILS" -eq 0 ] && echo "unpointed-worktree: PASS" || { echo "unpointed-worktree: FAIL ($FAILS)"; exit 1; }
