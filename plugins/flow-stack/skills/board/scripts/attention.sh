#!/usr/bin/env bash
# attention.sh: the human's time, read from Claude Code transcripts. One JSON line per event:
#   {"sid","ts","kind","secs","wait"}   ts = epoch seconds when the human acted
#   kind prompt      a prompt they typed; wait = time since Claude's last output (reading + typing)
#   kind answer      a prompt replying to a turn whose final paragraph (code fences stripped) has a line ending in "?"
#   kind question    an AskUserQuestion they answered; wait = asked → answered
#   kind permission  a permission prompt (logged by notify.sh to waits.jsonl); wait = shown → resolved
# secs = min(wait, cap): longer than the cap means they stepped away, so only the cap is attention.
# Then one {"sid","kind":"session","title","first","last"} line per transcript.
#   attention.sh [--days N] [--cap SECS]     transcripts touched in the last N days (default 14), cap 300
# Transcripts: ${CLAUDE_CONFIG_DIR:-~/.claude}/projects/*/<sid>.jsonl · waits: ${FLOW_STACK_HOME:-~/.flow-stack}/waits.jsonl
set -euo pipefail
days=14; cap=300
while [ $# -gt 0 ]; do
  case "$1" in
    --days) days="${2:?--days needs a value}"; shift 2 ;;
    --cap) cap="${2:?--cap needs a value}"; shift 2 ;;
    *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  esac
done
waits="${FLOW_STACK_HOME:-$HOME/.flow-stack}/waits.jsonl"

prog='
def t: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
def tool_result: (.message.content | type) == "array" and any(.message.content[]; .type == "tool_result");
def body: if (.message.content | type) == "string" then .message.content
          else [.message.content[]? | select(.type == "text") | .text] | join("\n") end;
def noise: test("^\\s*<(local-command|task-notification|system-reminder)") or test("^Another Claude session sent a message");
def human: .type == "user" and ((.origin.kind // "human") == "human") and (tool_result | not) and (body | test("\\S")) and (body | noise | not);
def ev($k; $at; $w): ([$w, 0] | max) as $w | {sid: $sid, ts: $at, kind: $k, secs: ([$w, $cap] | min), wait: $w};
def asks: [body | gsub("```[^`]*```"; "") | split("\n\n") | map(select(test("\\S"))) | last // "" | split("\n")[] | select(test("\\?\\s*$"))] | length > 0;
reduce ([inputs | select(.timestamp != null and (.isSidechain | not) and (.isMeta | not) and (.type == "user" or .type == "assistant"))] | sort_by(.timestamp | t))[] as $r
  ({last: null, first: null, asks: {}, ask: false, waits: $waits, out: []};
   ($r.timestamp | t) as $now
   # a permission prompt shown before this record was resolved by it
   | .out += [.waits[] | select(. <= $now) | ev("permission"; $now; $now - .)] | .waits |= map(select(. > $now))
   | if ($r | human) and .last != null then .out += [ev(if .ask then "answer" else "prompt" end; $now; $now - .last)] | .ask = false
     elif $r.type == "assistant" then (if ($r | body | test("\\S")) then .ask = ($r | asks) else . end) | .asks += ([$r.message.content[]? | select(.type == "tool_use" and .name == "AskUserQuestion") | {(.id): $now}] | add // {})
     elif $r.type == "user" and ($r | tool_result) then
       reduce ($r.message.content[] | select(.type == "tool_result") | .tool_use_id) as $id (.;
           if .asks[$id] then .out += [ev("question"; $now; $now - .asks[$id])] | del(.asks[$id]) else . end)
     else . end
   | .last = $now | .first //= $now)
| (.out[]), {sid: $sid, kind: "session", first, last}'

find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" -mindepth 2 -maxdepth 2 -name '*.jsonl' -mtime -"$days" 2>/dev/null |
while IFS= read -r f; do
  sid="$(basename "$f" .jsonl)"
  w="[]"; [ -s "$waits" ] && w="$(jq -sc --arg s "$sid" '[.[] | select(.sid == $s) | .ts | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601] | sort' "$waits" 2>/dev/null || echo "[]")"
  title="$(grep -F '"type":"ai-title"' "$f" 2>/dev/null | tail -n1 | jq -r '.aiTitle // empty' 2>/dev/null || true)"
  jq -nc --arg sid "$sid" --argjson cap "$cap" --argjson waits "${w:-[]}" "$prog" "$f" |
    jq -c --arg title "$title" 'if .kind == "session" then . + {title: $title} else . end' || true
done
