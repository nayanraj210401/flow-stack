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
  you(1320; [{type:"text", text:"thanks"}]),
  {type:"ai-title", aiTitle:"Fixture title"}
' >"$CLAUDE_CONFIG_DIR/projects/-r/$sid.jsonl"
jq -nc --arg s "$sid" '{ts:(1793059200 + 1305 | todate), sid:$s, kind:"permission_prompt"}' >"$FLOW_STACK_HOME/waits.jsonl"

out="$("$H/attention.sh" 2>&1)"
got="$(jq -c 'select(.kind != "session") | [.kind, .wait, .secs]' <<<"$out" 2>&1)"
want='["prompt",60,60]
["question",30,30]
["answer",1000,300]
["prompt",60,60]
["permission",15,15]
["prompt",20,20]'
fail=0
[ "$got" = "$want" ] && echo "  ✓ events, kinds, caps, order" || { echo "  ✗ events: want
$want
got
$got"; fail=1; }
ses="$(jq -c 'select(.kind == "session") | [.sid, .title, .last - .first]' <<<"$out" 2>&1)"
[ "$ses" = "[\"$sid\",\"Fixture title\",1320]" ] && echo "  ✓ session line" || { echo "  ✗ session: $ses"; fail=1; }
grep -qE 'thanks|Shall I|agent prompt' <<<"$out" && { echo "  ✗ prompt text leaked"; fail=1; } || echo "  ✓ no prompt text"
[ "$fail" = 0 ] && echo PASS || exit 1
