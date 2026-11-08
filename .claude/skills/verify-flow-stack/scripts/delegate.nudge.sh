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

echo "-- a subagent's reads never nudge the main thread (fresh session: only the agent_id guard can silence it)"
hook delegate-nudge.sh "$(jq -nc --arg tp "$TR" '{agent_id:"a1", session_id:"SUB", transcript_path:$tp, cwd:"'"$PWD"'", hook_event_name:"PostToolUse", tool_name:"Read"}')"
[ -z "$OUT" ] && ok "subagent read → quiet" || bad "subagent nudged: $OUT"
hook delegate-nudge.sh "$(ptool SUB)"
[ -n "$OUT" ] && ok "same session, no agent_id → nudges (so the guard is what silenced it)" || bad "fresh session did not nudge"
mkdir -p "$SB/ng"; cp "$H"/*.sh "$SB/ng/"; sed -i.bak '/flow_field .agent_id/d' "$SB/ng/delegate-nudge.sh"
OUT="$(jq -nc --arg tp "$TR" '{agent_id:"a1", session_id:"SUB2", transcript_path:$tp, cwd:"'"$PWD"'", hook_event_name:"PostToolUse"}' | bash "$SB/ng/delegate-nudge.sh" 2>/dev/null)" || true
[ -n "$OUT" ] && ok "TEETH: guard deleted → subagent nudged" || bad "guard has no teeth"

echo "-- re-nudge only after >=3 more human turns"
hu t9; as; hu t10; as; reads
hook delegate-nudge.sh "$(ptool S)"
[ -z "$OUT" ] && ok "2 turns after the nudge → quiet" || bad "re-nudged early: $OUT"
hu t11; as; reads
hook delegate-nudge.sh "$(ptool S)"
[ -n "$OUT" ] && ok "3 turns after the nudge → nudges again" || bad "no re-nudge"

echo "-- scroll-out: old prompts leaving the 3000-line window cannot silence it"
: >"$TR"; for i in 1 2 3 4 5 6 7 8; do hu "turn $i"; as; done
for i in $(seq 1 3100); do as; done
hu t9; as; reads
hook delegate-nudge.sh "$(ptool SCROLL)"
[ -n "$OUT" ] && ok "8+ turns, most scrolled out → nudges" || bad "scroll-out silenced it"

echo "-- sdk and person origins count as turns"
: >"$TR"; for i in 1 2 3 4 5 6 7 8; do jq -nc '{type:"user", message:{role:"user",content:"p"}, turnOrigin:"sdk"}' >>"$TR"; as; done; reads
hook delegate-nudge.sh "$(ptool SDK)"
[ -n "$OUT" ] && ok "turnOrigin sdk → counted" || bad "sdk turns ignored"
: >"$TR"; for i in 1 2 3 4 5 6 7 8; do jq -nc '{type:"user", message:{role:"user",content:"p"}, origin:{kind:"person"}}' >>"$TR"; as; done; reads
hook delegate-nudge.sh "$(ptool PERSON)"
[ -n "$OUT" ] && ok "origin person → counted" || bad "person turns ignored"
: >"$TR"; for i in 1 2 3 4 5 6 7 8; do jq -nc '{type:"user", message:{role:"user",content:[{type:"tool_result",content:"x"}]}}' >>"$TR"; as; done; reads
hook delegate-nudge.sh "$(ptool TR)"
[ -z "$OUT" ] && ok "tool_result lines are not turns" || bad "tool results counted: $OUT"

echo "-- Grep/Glob count toward the run; a non-read tool resets it"
: >"$TR"; for i in 1 2 3 4 5 6 7 8; do hu "turn $i"; as; done
rd a; jq -nc '{type:"assistant", message:{content:[{type:"tool_use", name:"Grep", input:{pattern:"x"}}]}}' >>"$TR"
jq -nc '{type:"assistant", message:{content:[{type:"tool_use", name:"Glob", input:{pattern:"*"}}]}}' >>"$TR"; rd b
hook delegate-nudge.sh "$(ptool G)"
[ -n "$OUT" ] && ok "Read+Grep+Glob+Read → nudge" || bad "Grep/Glob not counted"
: >"$TR"; for i in 1 2 3 4 5 6 7 8; do hu "turn $i"; as; done
rd a; rd b; rd c; jq -nc '{type:"assistant", message:{content:[{type:"tool_use", name:"Edit", input:{}}]}}' >>"$TR"; rd d
hook delegate-nudge.sh "$(ptool E)"
[ -z "$OUT" ] && ok "an Edit mid-run resets it → quiet" || bad "run not reset: $OUT"

echo "-- hooks.delegate: false turns it off"
: >"$TR"; for i in 1 2 3 4 5 6 7 8; do hu "turn $i"; as; done; reads
printf '{"hooks":{"delegate":false}}' >"$FLOW_STACK_HOME/config.json"
hook delegate-nudge.sh "$(ptool OFF)"
[ -z "$OUT" ] && ok "hooks.delegate false → quiet" || bad "ignored off switch: $OUT"
rm -f "$FLOW_STACK_HOME/config.json"

echo "-- budget: keys override the defaults; context alone can trigger"
printf -- '---\nbudget:\n  delegate_after_turns: 100\n  delegate_after_tokens: 20000\n---\n' >"$FLOW_STACK_HOME/profile.md"
: >"$TR"; for i in 1 2 3 4 5 6 7 8; do hu "turn $i"; as; done; reads
hook delegate-nudge.sh "$(ptool S2)"
[ -z "$OUT" ] && ok "8 turns but delegate_after_turns 100 → quiet" || bad "ignored turn override: $OUT"
printf -- '---\nbudget:\n  delegate_after_turns: 2\n---\n' >"$FLOW_STACK_HOME/profile.md"
: >"$TR"; hu one; as; hu two; as; hu three; as; reads
hook delegate-nudge.sh "$(ptool S3)"
[ -n "$OUT" ] && ok "delegate_after_turns 2 → nudges at turn 3" || bad "lowered threshold ignored"
printf -- '---\nbudget:\n  delegate_after_turns: 100\n  delegate_after_tokens: 20000\n---\n' >"$FLOW_STACK_HOME/profile.md"
: >"$TR"; hu one; as; hu two; as; hu three; as
for f in a b c d; do
  jq -nc --arg f "src/$f.sh" '{type:"assistant", message:{content:[{type:"tool_use", name:"Read", input:{file_path:$f}}], usage:{input_tokens:25000, cache_creation_input_tokens:0, cache_read_input_tokens:0}}}' >>"$TR"
done
hook delegate-nudge.sh "$(ptool S4)"
jq -e '.hookSpecificOutput.additionalContext' <<<"$OUT" >/dev/null 2>&1 && ok "context over threshold → nudge" || bad "no context nudge: $OUT"
finish
