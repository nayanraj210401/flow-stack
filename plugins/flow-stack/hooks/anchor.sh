#!/usr/bin/env bash
# UserPromptSubmit: re-anchor the active task's intent in three lines so the
# agent does not drift from the goal over a long session.
. "$(dirname "$0")/lib.sh"
flow_init anchor
flow_enabled anchor || exit 0
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
