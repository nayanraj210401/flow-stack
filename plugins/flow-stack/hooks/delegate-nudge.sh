#!/usr/bin/env bash
# PostToolUse (Read|Grep|Glob|Bash): once a session is long (human turn >=
# budget:delegate_after_turns, or context >= budget:delegate_after_tokens, whichever first), nudge the
# main thread to hand bulk reading to a subagent so the main context stays small.
# One line, at most once every few turns. Fresh or short sessions, and subagents, stay quiet.
. "$(dirname "$0")/lib.sh"
flow_init delegate-nudge
flow_enabled delegate || exit 0
[ -z "$(flow_field .agent_id)" ] || exit 0
tr="$(flow_field .transcript_path)"; [ -f "$tr" ] || exit 0

# turns = human turns in the window, ctx = the latest request's context, reads = the trailing
# run of Read/Grep/Glob calls (reset by a human turn or a non-read tool call).
s="$(tail -n 3000 "$tr" | jq -nrR '
  reduce (inputs | fromjson?) as $l ({turns:0, ctx:0, reads:0};
    if $l.type == "user" and (($l.origin.kind? // $l.turnOrigin? // "") == "human")
      then .turns += 1 | .reads = 0
    elif $l.type == "assistant" then
      .ctx = ((($l.message.usage? // {}) | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)))
      | reduce ($l.message.content? // [] | if type == "array" then .[] else empty end) as $c (.;
          if $c.type == "tool_use" then
            if ($c.name == "Read" or $c.name == "Grep" or $c.name == "Glob") then .reads += 1 else .reads = 0 end
          else . end)
    else . end) | [.turns, .ctx, .reads] | @tsv' 2>/dev/null || true)"
IFS=$'\t' read -r turns ctx reads <<<"$s" || true

after_turns="$(profile_fm delegate_after_turns)"; after_turns="${after_turns:-7}"
after_tokens="$(profile_fm delegate_after_tokens)"; after_tokens="${after_tokens:-120000}"

[ "${turns:-0}" -ge "$after_turns" ] || [ "${ctx:-0}" -ge "$after_tokens" ] || exit 0
[ "${reads:-0}" -ge 4 ] || exit 0

sid="$(flow_field .session_id)"
[ -n "$sid" ] || exit 0
state="$FLOW_HOME/delegate/${sid//\//_}"
last="$(cat "$state" 2>/dev/null || true)"
if [ -n "$last" ]; then
  [ $((turns - last)) -lt 3 ] && exit 0
fi
mkdir -p "$(dirname "$state")"; echo "$turns" >"$state"

msg="flow: this session is at turn $turns (~$((ctx / 1000))K context); hand this bulk reading to flow-stack:flow-agent or Explore on the profile's subagent_model and take back only the answer, so the main context stays small."
jq -n --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$m}}'
exit 0
