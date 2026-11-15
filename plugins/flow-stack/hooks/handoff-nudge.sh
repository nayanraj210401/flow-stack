#!/usr/bin/env bash
# Handoff before the window fills. Every request re-sends the whole context, so a session's cost
# grows with its size; past budget:handoff_at_tokens (default 100K) the next session is cheaper.
#   UserPromptSubmit: once per crossing, nudge "finish the slice, then handoff". A per-session flag
#     is set on the nudge and cleared when the context drops back below.
#   PostToolUse Bash, right after a successful `task.sh slice <id> done`: the slice boundary is the
#     clean place to stop, and an --auto run may never see a prompt, so this fires at every slice
#     done while over the threshold (the flag doesn't apply). Under --auto it says to write the
#     handoff and end the turn, so whatever launched the run starts a fresh session.
# Subagents' own calls never nudge: their context isn't the main thread's.
FLOW_INPUT="$(cat)"
event="$(jq -r '.hook_event_name // empty' <<<"$FLOW_INPUT" 2>/dev/null || true)"; event="${event:-UserPromptSubmit}"
if [ "$event" = PostToolUse ]; then
  # fast exit: this runs on every Bash call
  jq -e '.tool_name == "Bash"
    and ((.tool_input.command // "") | test("task\\.sh[\"'"'"']?[[:space:]]+slice[[:space:]]+[^[:space:];&|]+[[:space:]]+done"))
    and ((.tool_response | if type == "object" then (.stdout // "") else tostring end) | test("→ done"))
    and ((.agent_id // "") == "")' <<<"$FLOW_INPUT" >/dev/null 2>&1 || exit 0
fi
. "$(dirname "$0")/lib.sh"
flow_init handoff-nudge
flow_enabled handoff || exit 0
[ -z "$(flow_field .agent_id)" ] || exit 0
tr="$(flow_field .transcript_path)"; [ -f "$tr" ] || exit 0

ctx="$(tail -n 400 "$tr" | jq -nrR '
  reduce (inputs | fromjson?) as $l (0;
    ((($l.message.usage? // {}) | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))) as $t
    | if $l.type == "assistant" and ($l.isSidechain // false) != true and ($l.message.model? // "") != "<synthetic>" and $t > 0 then $t else . end)' 2>/dev/null || true)"
ctx="${ctx:-0}"

tok="$(profile_fm handoff_at_tokens)"
[[ "$tok" =~ ^[1-9][0-9]{0,9}$ ]] || tok=100000

sid="$(flow_field .session_id)"
[ -n "$sid" ] || exit 0
flag="$FLOW_HOME/handoff/${sid//\//_}"

say() { jq -n --arg e "$event" --arg m "$1" '{hookSpecificOutput:{hookEventName:$e, additionalContext:$m}}'; }
k=$((ctx / 1000))

if [ "$ctx" -lt "$tok" ]; then
  [ "$event" = PostToolUse ] || rm -f "$flag"
  exit 0
fi

if [ "$event" = PostToolUse ]; then
  if flow_auto; then
    say "flow: slice done at ~${k}K tokens of context, past budget:handoff_at_tokens ($tok). Every request re-sends all of it. Write the handoff now (/flow-stack:handoff, GATES.md items first), then end your turn: a fresh session that runs /flow resume continues for a fraction of the cost."
  else
    say "flow: slice done at ~${k}K tokens of context, past budget:handoff_at_tokens ($tok). This is the clean place to stop: run /flow-stack:handoff now, then tell the human to start a fresh session with /flow resume."
  fi
  exit 0
fi

[ -f "$flag" ] && exit 0
mkdir -p "$(dirname "$flag")"; : >"$flag"
say "flow: context is ~${k}K tokens, past budget:handoff_at_tokens ($tok). Finish the current slice, then run /flow-stack:handoff before the window fills."
exit 0
