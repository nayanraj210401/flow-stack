#!/usr/bin/env bash
# UserPromptSubmit: re-anchor the active task's intent in three lines so the
# agent does not drift from the goal over a long session.
. "$(dirname "$0")/lib.sh"
flow_init anchor
flow_enabled anchor || exit 0

# --auto / --no-auto anywhere in a prompt switch this session's auto mode. Only the human's own
# prompts count: agent hand-backs and task notifications arrive as prompts too.
prompt="$(flow_field .prompt)"
grep -Eq '<(agent-message|task-notification)[[:space:]>]' <<<"$prompt" && prompt=""
if flag="$(flow_auto_flag)"; then
  if grep -Eq '(^|[[:space:]])--no-auto([[:space:],.;:!?)]|$)' <<<"$prompt"; then
    rm -f "$flag"; echo "[flow auto] off: the human is back; gates ask again."
  elif grep -Eq '(^|[[:space:]])--auto([[:space:],.;:!?)]|$)' <<<"$prompt"; then
    mkdir -p "${flag%/*}"; touch "$flag"
    find "${flag%/*}" -type f -mtime +7 -delete 2>/dev/null || true
  fi
  if [ -f "$flag" ]; then
    echo "[flow auto] the human is away (--auto; --no-auto ends it). Never wait on them: run flow's Autonomous mode. Reversible gates, including intent and seal approval: take your recommended option and log it with task.sh decide agent. Irreversible actions (push, PR, merge, deploy, publish, .flow/gates.md) never happen: queue them in GATES.md. The hooks catch push, PR, publish, and gates.md; a deploy script is on you. Notify and hand off at the end."
  fi
fi

[ -n "$FLOW_TASK_DIR" ] && [ -f "$FLOW_TASK_DIR/INTENT.md" ] || exit 0

section_first() {
  awk -v h="## $1" '/<!--/{c=1} c{if(/-->/)c=0; next} $0 == h {on=1; next} on && /^## /{exit} on && NF && $0 != "- " {print; exit}' "$FLOW_TASK_DIR/INTENT.md"
}

goal="$(section_first Goal)"
nongoal="$(section_first Non-goals)"
slice="$(awk '/^## /{h=$0} /^status: doing/{print h; exit}' "$FLOW_TASK_DIR/SLICES.md" 2>/dev/null || true)"

printf '[flow anchor · %s] goal: %s\n' "$FLOW_TASK" "${goal:-?}"
[ -n "$nongoal" ] && printf '[flow anchor] not doing: %s\n' "${nongoal#- }"
[ -n "$slice" ] && printf '[flow anchor] current slice: %s\n' "${slice#\#\# }"
exit 0
