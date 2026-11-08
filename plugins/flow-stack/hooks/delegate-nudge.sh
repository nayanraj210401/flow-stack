#!/usr/bin/env bash
# PostToolUse (Read|Grep|Glob): once a session is long (human turn >=
# budget:delegate_after_turns, or context >= budget:delegate_after_tokens, whichever first), nudge the
# main thread to hand bulk reading to a subagent so the main context stays small.
# One line, at most once every few turns. Fresh or short sessions, and subagents, stay quiet.
. "$(dirname "$0")/lib.sh"
flow_init delegate-nudge
flow_enabled delegate || exit 0
[ -z "$(flow_field .agent_id)" ] || exit 0
tr="$(flow_field .transcript_path)"; [ -f "$tr" ] || exit 0

# turns = human prompts over the whole file (monotonic: scroll-out can't shrink it); ctx and reads
# come from the tail: ctx = the latest request's context, reads = the trailing run of Read/Grep/Glob
# calls (reset by a human turn or a non-read tool call).
# human = a typed prompt: not a tool result, meta/compact line, slash-command or task-notification echo, or an interrupt marker (mirrors board/attention.sh)
DEFS='def body: if (.message.content? | type) == "string" then .message.content
          else [.message.content[]? | select(type == "object" and .type == "text") | .text] | join("\n") end;
def noise: test("^\\s*<(command-message|command-name|local-command|task-notification|system-reminder|bash-stdout|bash-stderr)") or test("^\\[Request interrupted");
def human: .type == "user" and (.isMeta | not) and (.isCompactSummary | not)
  and ((.message.content? | type) != "array" or any(.message.content[]; type == "object" and .type == "text"))
  and (((.origin.kind? // .turnOrigin? // "human") | . == "human" or . == "person" or . == "sdk"))
  and (body | test("\\S")) and (body | noise | not);'
turns="$(grep -F '"type":"user"' "$tr" 2>/dev/null | grep -v '"type":"tool_result"' | jq -nR "$DEFS"'reduce (inputs | fromjson?) as $l (0; if ($l | human) then . + 1 else . end)' 2>/dev/null || true)"
s="$(tail -n 3000 "$tr" | jq -nrR "$DEFS"'
  reduce (inputs | fromjson?) as $l ({ctx:0, reads:0};
    if ($l | human) then .reads = 0
    elif $l.type == "assistant" then
      .ctx = ((($l.message.usage? // {}) | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)))
      | reduce ($l.message.content? // [] | if type == "array" then .[] else empty end) as $c (.;
          if $c.type == "tool_use" then
            if ($c.name == "Read" or $c.name == "Grep" or $c.name == "Glob") then .reads += 1 else .reads = 0 end
          else . end)
    else . end) | [.ctx, .reads] | @tsv' 2>/dev/null || true)"
IFS=$'\t' read -r ctx reads <<<"$s" || true
turns="${turns:-0}"

after_turns="$(profile_fm delegate_after_turns)"; after_turns="${after_turns:-7}"
after_tokens="$(profile_fm delegate_after_tokens)"; after_tokens="${after_tokens:-120000}"

[ "${turns:-0}" -ge "$after_turns" ] || [ "${ctx:-0}" -ge "$after_tokens" ] || exit 0
[ "${reads:-0}" -ge 4 ] || exit 0

sid="$(flow_field .session_id)"
[ -n "$sid" ] || exit 0
state="$FLOW_HOME/delegate/${sid//\//_}"
last="$(cat "$state" 2>/dev/null || true)"
case $last in *[!0-9]*) last=;; esac
if [ -n "$last" ]; then
  [ $((turns - last)) -lt 3 ] && exit 0
fi
mkdir -p "$(dirname "$state")"; find "$(dirname "$state")" -type f -mtime +7 -delete 2>/dev/null || true; echo "$turns" >"$state"

msg="flow: this session is at turn $turns (~$((ctx / 1000))K context); hand this bulk reading to flow-stack:flow-agent or Explore on the profile's subagent_model and take back only the answer, so the main context stays small."
jq -n --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$m}}'
exit 0
