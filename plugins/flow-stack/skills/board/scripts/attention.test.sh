#!/usr/bin/env bash
# attention.test.sh: attention.sh turns a transcript into prompt / answer / question / permission
# events with capped secs, in time order even when the file is not, and never prints prompt text.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
SB="$(mktemp -d "${TMPDIR:-/tmp}/attention.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
export CLAUDE_CONFIG_DIR="$SB/claude" FLOW_STACK_HOME="$SB/home"; mkdir -p "$CLAUDE_CONFIG_DIR/projects/-r" "$FLOW_STACK_HOME"
sid=0000aaaa-1111-2222-3333-444455556666
jq -nc '
  def at($s): 1793059200 + $s | todate;
  def you($s; $t): {type:"user", timestamp:at($s), origin:{kind:"human"}, message:{role:"user", content:$t}};
  def say($s; $t): {type:"assistant", timestamp:at($s), message:{role:"assistant", content:[{type:"text", text:$t}]}};
  you(0; "hi"),
  you(70; "next"),                                                    # before the reply it follows: file out of order
  say(10; "Done."),
  {type:"assistant", timestamp:at(100), message:{content:[{type:"tool_use", id:"q1", name:"AskUserQuestion", input:{}}]}},
  {type:"user", timestamp:at(130), message:{content:[{type:"tool_result", tool_use_id:"q1", content:"A"}]}},
  {type:"user", timestamp:at(131), isMeta:true, message:{content:"skill text"}},
  {type:"user", timestamp:at(132), isSidechain:true, origin:{kind:"human"}, message:{content:"agent prompt"}},
  say(140; "Plan:\n```\nwhy?\n```\nShall I start?"),
  you(1140; "yes"),                                                   # 1000 s later: an answer, capped
  say(1200; "Built it. Is it good? I think so.\n\nAll done."),
  you(1260; "ok"),
  say(1300; "```\nok?\n```"),
  {type:"attachment", timestamp:at(1307)},                           # written at approval: ends the permission wait
  you(1320; [{type:"text", text:"thanks"}]),
  {type:"user", timestamp:at(1330), isCompactSummary:true, message:{content:"This session is being continued"}},
  you(1340; "<bash-stdout>ok</bash-stdout><bash-stderr></bash-stderr>"),
  you(1345; "[Request interrupted by user]"),
  {type:"ai-title", aiTitle:"Fixture title"}
' >"$CLAUDE_CONFIG_DIR/projects/-r/$sid.jsonl"
jq -nc --arg s "$sid" '{ts:(1793059200 + 1305 | todate), sid:$s, kind:"permission_prompt"}' >"$FLOW_STACK_HOME/waits.jsonl"

out="$("$H/attention.sh" 2>&1)"
got="$(jq -c 'select(.kind != "session") | [.kind, .wait, .secs]' <<<"$out" 2>&1)"
want='["prompt",60,60]
["question",30,30]
["answer",1000,300]
["prompt",60,60]
["permission",2,2]
["prompt",20,20]'
fail=0
[ "$got" = "$want" ] && echo "  ✓ events, kinds, caps, order" || { echo "  ✗ events: want
$want
got
$got"; fail=1; }
ses="$(jq -c 'select(.kind == "session") | [.sid, .title, .last - .first]' <<<"$out" 2>&1)"
[ "$ses" = "[\"$sid\",\"Fixture title\",1345]" ] && echo "  ✓ session line" || { echo "  ✗ session: $ses"; fail=1; }
grep -qE 'thanks|Shall I|agent prompt' <<<"$out" && { echo "  ✗ prompt text leaked"; fail=1; } || echo "  ✓ no prompt text"
# many busy transcripts at once: parallel workers must never splice lines (jq flushes in 4 KB blocks)
for k in $(seq 10 49); do
  jq -nc --arg t "busy $k" '
    range(0; 1200) as $i | {type:"assistant", timestamp:(1793059200 + $i * 20 | todate), message:{content:[{type:"text", text:"ok"}]}},
      {type:"user", timestamp:(1793059200 + $i * 20 + 10 | todate), origin:{kind:"human"}, message:{content:"go"}}' \
    >"$CLAUDE_CONFIG_DIR/projects/-r/abcdef$k-0000-0000-0000-000000000000.jsonl"
done
"$H/attention.sh" >"$SB/busy.out" 2>/dev/null; busy="$(cat "$SB/busy.out")"   # a file, as collect.sh writes it
bad="$(jq -cR 'fromjson? // "BAD"' <<<"$busy" | grep -c '^"BAD"$')"
n="$(jq -cR 'fromjson? | select(.kind == "prompt" and (.sid | startswith("abcdef")))' <<<"$busy" | wc -l | tr -d ' ')"
[ "$bad" = 0 ] && [ "$n" = $((40 * 1200)) ] && echo "  ✓ 40 busy transcripts: every line parses, none lost" || { echo "  ✗ busy: $bad unparseable lines, $n of $((40 * 1200)) prompts"; fail=1; }
[ "$fail" = 0 ] && echo PASS || exit 1
