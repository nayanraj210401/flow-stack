#!/usr/bin/env bash
# handoff.nudge: once the latest request's context passes budget:handoff_at_tokens (default 100K),
# handoff-nudge.sh injects one line telling the agent to finish the slice and handoff. On prompts, once
# per crossing: staying over the threshold does not repeat, and dropping back below re-arms it. After a
# successful `task.sh slice <id> done` (PostToolUse Bash) it nudges every time while over, and under
# --auto it says to end the turn.
. "$(dirname "$0")/lib.sh"; sandbox handoff.nudge
TR="$SB/transcript.jsonl"
: >"$TR"
usage() { jq -nc --argjson n "$1" '{type:"assistant", message:{content:[{type:"text",text:"ok"}], usage:{input_tokens:$n, cache_creation_input_tokens:0, cache_read_input_tokens:0}}}' >>"$TR"; }
up() { jq -nc --arg sid "$1" --arg tp "$TR" '{session_id:$sid, transcript_path:$tp, cwd:"'"$PWD"'", hook_event_name:"UserPromptSubmit", prompt:"next"}'; }
# post <sid> <command> <stdout> [agent_id]: a PostToolUse Bash payload
post() { jq -nc --arg sid "$1" --arg tp "$TR" --arg c "$2" --arg o "$3" --arg a "${4:-}" \
  '{session_id:$sid, transcript_path:$tp, cwd:"'"$PWD"'", hook_event_name:"PostToolUse", tool_name:"Bash", tool_input:{command:$c}, tool_response:{stdout:$o, stderr:""}} + (if $a != "" then {agent_id:$a, agent_type:"flow-stack:worker"} else {} end)'; }
ctxof() { jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$OUT" 2>/dev/null; }
evof() { jq -r '.hookSpecificOutput.hookEventName // empty' <<<"$OUT" 2>/dev/null; }

echo "-- over the threshold nudges once"
: >"$TR"; usage 160000
hook handoff-nudge.sh "$(up S)"
jq -e '.hookSpecificOutput.additionalContext' <<<"$OUT" >/dev/null 2>&1 && ok "over threshold → nudge" || bad "no nudge: $OUT"
has "$OUT" "handoff" && ok "nudge says handoff" || bad "nudge: $OUT"
hook handoff-nudge.sh "$(up S)"
[ -z "$OUT" ] && ok "not nudged again while still over" || bad "re-nudged: $OUT"

echo "-- below the threshold stays quiet"
: >"$TR"; usage 90000
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
jq -nc '{type:"assistant", message:{model:"<synthetic>", usage:{input_tokens:5000}}}' >>"$TR"
hook handoff-nudge.sh "$(up S4)"
[ -z "$OUT" ] && ok "synthetic zero line does not re-arm" || bad "re-nudged after synthetic: $OUT"
usage 160000
hook handoff-nudge.sh "$(up S4)"
[ -z "$OUT" ] && ok "next real over-threshold line after a synthetic one is not a new crossing" || bad "re-nudged after synthetic: $OUT"
jq -nc '{type:"assistant", message:{usage:{input_tokens:0}}}' >>"$TR"
hook handoff-nudge.sh "$(up S4)"
[ -z "$OUT" ] && ok "plain zero-usage line is ignored too" || bad "re-nudged after zero-usage line: $OUT"
: >"$TR"; usage 60000; jq -nc '{type:"assistant", isSidechain:true, message:{usage:{input_tokens:200000}}}' >>"$TR"
hook handoff-nudge.sh "$(up S5)"
[ -z "$OUT" ] && ok "large sidechain line does not nudge a small main session" || bad "sidechain nudged: $OUT"

echo "-- a non-numeric threshold falls back to 100K"
printf -- '---\nbudget:\n  handoff_at_tokens: 100k\n---\n' >"$FLOW_STACK_HOME/profile.md"
: >"$TR"; usage 90000
hook handoff-nudge.sh "$(up S6)"
[ -z "$OUT" ] && ok "bad threshold, small ctx → quiet" || bad "nudged on bad threshold: $OUT"
: >"$TR"; usage 160000
hook handoff-nudge.sh "$(up S6)"
jq -e '.hookSpecificOutput.additionalContext' <<<"$OUT" >/dev/null 2>&1 && ok "bad threshold falls back to the default" || bad "no nudge: $OUT"

echo "-- a zero threshold falls back to the default instead of nudging at any size"
printf -- '---\nbudget:\n  handoff_at_tokens: 0\n---\n' >"$FLOW_STACK_HOME/profile.md"
: >"$TR"; usage 90000
hook handoff-nudge.sh "$(up S10)"
[ -z "$OUT" ] && ok "threshold 0 + small ctx → quiet" || bad "nudged on threshold 0: $OUT"

echo "-- an oversized or zero-padded threshold falls back to the default"
for bad_tok in 99999999999999999999 00; do
  printf -- '---\nbudget:\n  handoff_at_tokens: %s\n---\n' "$bad_tok" >"$FLOW_STACK_HOME/profile.md"
  : >"$TR"; usage 90000
  hook handoff-nudge.sh "$(up "S11-$bad_tok")"
  [ -z "$OUT" ] && ok "threshold $bad_tok + small ctx → quiet" || bad "nudged on threshold $bad_tok: $OUT"
done

echo "-- the default is 100K: 110K nudges, 90K does not"
printf -- '---\n---\n' >"$FLOW_STACK_HOME/profile.md"
: >"$TR"; usage 110000
hook handoff-nudge.sh "$(up S12)"
has "$(ctxof)" "(100000)" && ok "110K → nudge naming the 100000 default" || bad "no 100K-default nudge: $OUT"

echo "-- slice done past the threshold nudges at the boundary, every time"
DONE='../flow/scripts/task.sh slice S2 done'
: >"$TR"; usage 120000
hook handoff-nudge.sh "$(post P1 "$DONE" 'S2 → done')"
has "$(ctxof)" "slice done" && ok "slice done over threshold → nudge" || bad "no slice-done nudge: $OUT"
[ "$(evof)" = PostToolUse ] && ok "hookEventName is PostToolUse" || bad "wrong event name: $(evof)"
has "$(ctxof)" "/flow resume" && ok "interactive wording points the human to /flow resume" || bad "wording: $(ctxof)"
hook handoff-nudge.sh "$(post P1 "$DONE" 'S2 → done')"
has "$(ctxof)" "slice done" && ok "next slice done still nudges (no once-per-crossing flag)" || bad "slice-done nudge suppressed: $OUT"
hook handoff-nudge.sh "$(up P1)"
has "$(ctxof)" "handoff" && ok "slice-done nudges don't use up the prompt nudge" || bad "prompt nudge lost: $OUT"
hook handoff-nudge.sh "$(post P1 "bash \"$H/../skills/flow/scripts/task.sh\" slice S3 done" 'S3 → done')"
has "$(ctxof)" "slice done" && ok "quoted task.sh path is matched" || bad "quoted path missed: $OUT"

echo "-- other Bash calls, refused slice gates, small contexts and subagents stay quiet"
hook handoff-nudge.sh "$(post P2 'npm test' 'ok')"
[ -z "$OUT" ] && ok "unrelated Bash call → quiet" || bad "nudged on unrelated Bash: $OUT"
hook handoff-nudge.sh "$(post P2 "$DONE" '')"
[ -z "$OUT" ] && ok "refused slice gate (no '→ done') → quiet" || bad "nudged on refused gate: $OUT"
hook handoff-nudge.sh "$(post P2 '../flow/scripts/task.sh slice S2 doing' 'S2 → doing')"
[ -z "$OUT" ] && ok "slice doing → quiet" || bad "nudged on slice doing: $OUT"
hook handoff-nudge.sh "$(post P2 "$DONE" 'S2 → done' agent-123)"
[ -z "$OUT" ] && ok "a subagent's slice done → quiet" || bad "subagent nudged: $OUT"
: >"$TR"; usage 60000
hook handoff-nudge.sh "$(post P2 "$DONE" 'S2 → done')"
[ -z "$OUT" ] && ok "slice done below threshold → quiet" || bad "nudged below threshold: $OUT"

echo "-- under --auto the slice-done nudge says to end the turn"
mkdir -p "$FLOW_STACK_HOME/auto"; : >"$FLOW_STACK_HOME/auto/P3"
: >"$TR"; usage 120000
hook handoff-nudge.sh "$(post P3 "$DONE" 'S2 → done')"
has "$(ctxof)" "end your turn" && ok "--auto → write the handoff and end the turn" || bad "auto wording: $OUT"

echo "-- hooks.handoff:false and a missing transcript are quiet"
printf '{"hooks":{"handoff":false}}\n' >"$FLOW_STACK_HOME/config.json"
hook handoff-nudge.sh "$(up S8)"
[ -z "$OUT" ] && ok "hooks.handoff:false → quiet" || bad "nudged while disabled: $OUT"
hook handoff-nudge.sh "$(post S8 "$DONE" 'S2 → done')"
[ -z "$OUT" ] && ok "hooks.handoff:false → slice done quiet too" || bad "slice-done nudged while disabled: $OUT"
rm -f "$FLOW_STACK_HOME/config.json"
hook handoff-nudge.sh "$(up S9 | jq -c '.transcript_path="/nonexistent"')"
[ -z "$OUT" ] && ok "missing transcript → quiet" || bad "output on missing transcript: $OUT"
finish
