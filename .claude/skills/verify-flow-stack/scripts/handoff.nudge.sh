#!/usr/bin/env bash
# handoff.nudge: once the latest request's context passes budget:handoff_at_tokens (default 150K),
# handoff-nudge.sh injects one line telling the agent to finish the slice and handoff. Once per
# crossing: staying over the threshold does not repeat, and dropping back below re-arms it.
. "$(dirname "$0")/lib.sh"; sandbox handoff.nudge
TR="$SB/transcript.jsonl"
: >"$TR"
usage() { jq -nc --argjson n "$1" '{type:"assistant", message:{content:[{type:"text",text:"ok"}], usage:{input_tokens:$n, cache_creation_input_tokens:0, cache_read_input_tokens:0}}}' >>"$TR"; }
up() { jq -nc --arg sid "$1" --arg tp "$TR" '{session_id:$sid, transcript_path:$tp, cwd:"'"$PWD"'", hook_event_name:"UserPromptSubmit", prompt:"next"}'; }

echo "-- over the threshold nudges once"
: >"$TR"; usage 160000
hook handoff-nudge.sh "$(up S)"
jq -e '.hookSpecificOutput.additionalContext' <<<"$OUT" >/dev/null 2>&1 && ok "over threshold → nudge" || bad "no nudge: $OUT"
has "$OUT" "handoff" && ok "nudge says handoff" || bad "nudge: $OUT"
hook handoff-nudge.sh "$(up S)"
[ -z "$OUT" ] && ok "not nudged again while still over" || bad "re-nudged: $OUT"

echo "-- below the threshold stays quiet"
: >"$TR"; usage 100000
hook handoff-nudge.sh "$(up S2)"
[ -z "$OUT" ] && ok "below threshold → quiet" || bad "nudged below: $OUT"

echo "-- budget:handoff_at_tokens overrides the default, and a crossing re-nudges"
printf -- '---\nbudget:\n  handoff_at_tokens: 50000\n---\n' >"$FLOW_STACK_HOME/profile.md"
: >"$TR"; usage 120000
hook handoff-nudge.sh "$(up S3)"
jq -e '.hookSpecificOutput.additionalContext' <<<"$OUT" >/dev/null 2>&1 && ok "configured threshold → nudge" || bad "no nudge at configured threshold: $OUT"
: >"$TR"; usage 40000
hook handoff-nudge.sh "$(up S3)"
[ -z "$OUT" ] && ok "below threshold again → quiet (flag cleared)" || bad "still nudging: $OUT"
: >"$TR"; usage 90000
hook handoff-nudge.sh "$(up S3)"
jq -e '.hookSpecificOutput.additionalContext' <<<"$OUT" >/dev/null 2>&1 && ok "a second crossing nudges again" || bad "no re-nudge on new crossing: $OUT"
finish
