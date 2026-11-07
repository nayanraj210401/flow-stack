#!/usr/bin/env bash
# delegate.nudge: once a session is long (human turn >= budget:delegate_after_turns, or context
# >= budget:delegate_after_tokens) and the main thread starts bulk reading, delegate-nudge.sh
# injects one line suggesting a subagent. Short sessions, subagents, and repeats stay quiet.
. "$(dirname "$0")/lib.sh"; sandbox delegate.nudge
TR="$SB/transcript.jsonl"
: >"$TR"
hu() { jq -nc --arg t "$1" '{type:"user", message:{role:"user",content:$t}, origin:{kind:"human"}}' >>"$TR"; }
as() { jq -nc '{type:"assistant", message:{content:[{type:"text",text:"ok"}]}}' >>"$TR"; }
rd() { jq -nc --arg f "$1" '{type:"assistant", message:{content:[{type:"tool_use", name:"Read", input:{file_path:$f}}]}}' >>"$TR"; }
reads() { rd src/a.sh; rd src/b.sh; rd src/c.sh; rd src/d.sh; }
ptool() { jq -nc --arg sid "$1" --arg tp "$TR" '{session_id:$sid, transcript_path:$tp, cwd:"'"$PWD"'", hook_event_name:"PostToolUse", tool_name:"Read"}'; }

echo "-- a short session with a read run stays quiet"
: >"$TR"; hu one; as; hu two; as; hu three; as; reads
hook delegate-nudge.sh "$(ptool S)"
[ -z "$OUT" ] && ok "turn 3 + 4 reads → quiet" || bad "nudged too early: $OUT"

echo "-- a long session (8 human turns) nudges once on a 4th read"
: >"$TR"; for i in 1 2 3 4 5 6 7 8; do hu "turn $i"; as; done; reads
hook delegate-nudge.sh "$(ptool S)"
jq -e '.hookSpecificOutput.additionalContext' <<<"$OUT" >/dev/null 2>&1 && ok "turn 8 + 4th read → nudge" || bad "no nudge: $OUT"
has "$OUT" "flow-agent" && ok "nudge names flow-agent" || bad "nudge: $OUT"

hook delegate-nudge.sh "$(ptool S)"
[ -z "$OUT" ] && ok "not nudged again right away" || bad "re-nudged: $OUT"

echo "-- a subagent's reads never nudge the main thread"
hook delegate-nudge.sh "$(jq -nc --arg tp "$TR" '{agent_id:"a1", session_id:"S", transcript_path:$tp, cwd:"'"$PWD"'", hook_event_name:"PostToolUse", tool_name:"Read"}')"
[ -z "$OUT" ] && ok "subagent read → quiet" || bad "subagent nudged: $OUT"

echo "-- budget: keys override the defaults; context alone can trigger"
printf -- '---\nbudget:\n  delegate_after_turns: 100\n  delegate_after_tokens: 20000\n---\n' >"$FLOW_STACK_HOME/profile.md"
: >"$TR"; hu one; as; hu two; as; hu three; as; reads
hook delegate-nudge.sh "$(ptool S2)"
[ -z "$OUT" ] && ok "below both configured thresholds → quiet" || bad "nudged below thresholds: $OUT"
: >"$TR"; hu one; as; hu two; as; hu three; as
for f in a b c d; do
  jq -nc --arg f "src/$f.sh" '{type:"assistant", message:{content:[{type:"tool_use", name:"Read", input:{file_path:$f}}], usage:{input_tokens:25000, cache_creation_input_tokens:0, cache_read_input_tokens:0}}}' >>"$TR"
done
hook delegate-nudge.sh "$(ptool S2)"
jq -e '.hookSpecificOutput.additionalContext' <<<"$OUT" >/dev/null 2>&1 && ok "context over threshold → nudge" || bad "no context nudge: $OUT"
finish
