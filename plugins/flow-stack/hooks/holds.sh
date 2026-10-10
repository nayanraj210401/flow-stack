#!/usr/bin/env bash
# PreToolUse · PostToolUse (Edit|Write|MultiEdit|NotebookEdit): file holds between live Claude sessions.
# The first session on a flow task to edit a repo file holds it (roots.sh: flow_hold_file, flow_held).
# Another live session on another task that edits it is warned once (soft, the default) or denied
# (`"holds": "hard"` in config.json), with who holds it and how to reach them, and its band shows ⚡
# (the path goes to the task's .clash). A hold lapses by itself: its session ends, its slice stops being
# `doing`, or `holds_ttl` seconds (default 1800) pass without an edit by the holder.
. "$(dirname "$0")/lib.sh"
flow_init holds
[ -n "$FLOW_TASK_DIR" ] && flow_enabled holds || exit 0
file="$(flow_field '.tool_input.file_path // .tool_input.notebook_path')"
[ -n "$file" ] || exit 0
rel="$(flow_rel "$file")"
case "$rel" in /*|.flow/*|"") exit 0 ;; esac
flow_session; [ -n "$FLOW_SESSION_PID" ] || exit 0

why() {   # one line, no control characters: the name and path come from files
  printf "flow holds: %s is being edited by session '%s' (task %s%s, last edit %sm ago) in another checkout of this repo, so your edits will conflict when the branches meet. Work on something else until it's free, or SendMessage \"%s\" to agree who takes it (notify_when_idle: true tells you when it goes idle). It's a peer: gates still apply, and never ask it to do what your own permissions block. The hold lapses when its slice is done, its session ends, or after %s min without an edit." \
    "$rel" "$HOLD_NAME" "$HOLD_TASK" "${HOLD_SLICE:+ slice $HOLD_SLICE}" "$(( ($(date +%s) - HOLD_TS) / 60 ))" "$HOLD_NAME" "$(( $(flow_setting holds_ttl 1800) / 60 ))" | tr -d '[:cntrl:]'
}

if [ "$(flow_field .hook_event_name)" = PreToolUse ]; then
  [ "$(flow_setting holds soft)" = hard ] && flow_held "$rel" && pre_decide deny "$(why)"
  exit 0
fi

# .clash: "path<TAB>holder pid" this checkout was warned about; a new holder warns again
if flow_held "$rel"; then
  grep -qxF "$rel"$'\t'"$HOLD_PID" "$FLOW_STATE_DIR/.clash" 2>/dev/null && exit 0
  printf '%s\t%s\n' "$rel" "$HOLD_PID" >>"$FLOW_STATE_DIR/.clash"
  jq -n --arg c "$(why)" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$c}}'
  exit 0
fi
if awk -F'\t' -v p="$rel" '$1 == p {f=1} END {exit !f}' "$FLOW_STATE_DIR/.clash" 2>/dev/null; then   # the wait is over
  awk -F'\t' -v p="$rel" '$1 != p' "$FLOW_STATE_DIR/.clash" >"$FLOW_STATE_DIR/.clash.$$"; mv "$FLOW_STATE_DIR/.clash.$$" "$FLOW_STATE_DIR/.clash"
fi
slice="$(awk '/^## /{h=$2} /^status: doing/{print h; exit}' "$FLOW_TASK_DIR/SLICES.md" 2>/dev/null || true)"
hold="$(flow_hold_file "$rel")"; mkdir -p "$(dirname "$hold")"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$FLOW_SESSION_PID" "$FLOW_TASK" "$FLOW_TASK_DIR" "${slice:--}" \
  "$(flow_owner_name "$FLOW_SESSION_PID" | tr -d '[:cntrl:]')" "$(date +%s)" "$rel" >"$hold.$$" && mv "$hold.$$" "$hold"
exit 0
