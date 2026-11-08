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

echo "-- sidechain, synthetic and zero-usage lines are ignored"
printf -- '---\n---\n' >"$FLOW_STACK_HOME/profile.md"
: >"$TR"; usage 160000
jq -nc '{type:"assistant", isSidechain:true, message:{usage:{input_tokens:5000}}}' >>"$TR"
hook handoff-nudge.sh "$(up S4)"
jq -e '.hookSpecificOutput.additionalContext' <<<"$OUT" >/dev/null 2>&1 && ok "small sidechain line does not hide the nudge" || bad "sidechain hid it: $OUT"
jq -nc '{type:"assistant", message:{model:"<synthetic>", usage:{input_tokens:0}}}' >>"$TR"
hook handoff-nudge.sh "$(up S4)"
[ -z "$OUT" ] && ok "synthetic zero line does not re-arm" || bad "re-nudged after synthetic: $OUT"
: >"$TR"; usage 100000; jq -nc '{type:"assistant", isSidechain:true, message:{usage:{input_tokens:200000}}}' >>"$TR"
hook handoff-nudge.sh "$(up S5)"
[ -z "$OUT" ] && ok "large sidechain line does not nudge a small main session" || bad "sidechain nudged: $OUT"

echo "-- a non-numeric threshold falls back to 150K"
printf -- '---\nbudget:\n  handoff_at_tokens: 150k\n---\n' >"$FLOW_STACK_HOME/profile.md"
: >"$TR"; usage 100000
hook handoff-nudge.sh "$(up S6)"
[ -z "$OUT" ] && ok "bad threshold, small ctx → quiet" || bad "nudged on bad threshold: $OUT"
: >"$TR"; usage 160000
hook handoff-nudge.sh "$(up S6)"
jq -e '.hookSpecificOutput.additionalContext' <<<"$OUT" >/dev/null 2>&1 && ok "bad threshold falls back to the default" || bad "no nudge: $OUT"

echo "-- hooks.handoff:false and a missing transcript are quiet"
printf '{"hooks":{"handoff":false}}\n' >"$FLOW_STACK_HOME/config.json"
hook handoff-nudge.sh "$(up S8)"
[ -z "$OUT" ] && ok "hooks.handoff:false → quiet" || bad "nudged while disabled: $OUT"
rm -f "$FLOW_STACK_HOME/config.json"
hook handoff-nudge.sh "$(up S9 | jq -c '.transcript_path="/nonexistent"')"
[ -z "$OUT" ] && ok "missing transcript → quiet" || bad "output on missing transcript: $OUT"
finish
