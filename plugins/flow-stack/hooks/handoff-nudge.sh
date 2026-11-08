#!/usr/bin/env bash
# UserPromptSubmit: once the latest request's context passes budget:handoff_at_tokens (default
# 150K), nudge handoff ("finish the slice, then handoff") before the window fills. Once per
# crossing: a per-session flag is set on the nudge and cleared when the context drops back below.
. "$(dirname "$0")/lib.sh"
flow_init handoff-nudge
flow_enabled handoff || exit 0
tr="$(flow_field .transcript_path)"; [ -f "$tr" ] || exit 0

ctx="$(tail -n 400 "$tr" | jq -nrR '
  reduce (inputs | fromjson?) as $l (0;
    ((($l.message.usage? // {}) | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))) as $t
    | if $l.type == "assistant" and ($l.isSidechain // false) != true and ($l.message.model? // "") != "<synthetic>" and $t > 0 then $t else . end)' 2>/dev/null || true)"
ctx="${ctx:-0}"

tok="$(profile_fm handoff_at_tokens)"
case "$tok" in ''|*[!0-9]*) tok=150000 ;; esac

sid="$(flow_field .session_id)"
[ -n "$sid" ] || exit 0
flag="$FLOW_HOME/handoff/${sid//\//_}"

if [ "$ctx" -lt "$tok" ]; then
  rm -f "$flag"
  exit 0
fi
[ -f "$flag" ] && exit 0
mkdir -p "$(dirname "$flag")"; : >"$flag"

jq -n --arg m "flow: context is ~$((ctx / 1000))K tokens, past budget:handoff_at_tokens ($tok). Finish the current slice, then run /flow-stack:handoff before the window fills." \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$m}}'
exit 0
