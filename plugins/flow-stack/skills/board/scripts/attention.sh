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
days=14; cap=300; file=""; out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --days) days="${2:?--days needs a value}"; shift 2 ;;
    --cap) cap="${2:?--cap needs a value}"; shift 2 ;;
    --out) out="$2"; shift 2 ;;                            # internal: the worker's output dir
    --one) [ $# -ge 2 ] || exit 0; file="$2"; shift 2 ;;   # internal: one transcript (GNU xargs calls once with none)
    *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  esac
done
waits="${FLOW_STACK_HOME:-$HOME/.flow-stack}/waits.jsonl"

prog='
def t: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
def tool_result: (.message.content | type) == "array" and any(.message.content[]; .type == "tool_result");
def body: if (.message.content | type) == "string" then .message.content
          else [.message.content[]? | select(.type == "text") | .text] | join("\n") end;
def noise: test("^\\s*<(local-command|task-notification|system-reminder|bash-stdout|bash-stderr)") or test("^Another Claude session sent a message|^\\[Request interrupted");
def human: .type == "user" and (.isCompactSummary | not) and ((.origin.kind // "human") == "human") and (tool_result | not) and (body | test("\\S")) and (body | noise | not);
def ev($k; $at; $w): ([$w, 0] | max) as $w | {sid: $sid, ts: $at, kind: $k, secs: ([$w, $cap] | min), wait: $w};
def asks: [body | gsub("```[^`]*```"; "") | split("\n\n") | map(select(test("\\S"))) | last // "" | split("\n")[] | select(test("\\?\\s*$"))] | length > 0;
[inputs | select(.timestamp != null)] as $all
# a permission prompt ends at the first record of any kind after it (hook and attachment records land at approval)
| ([$all[].timestamp | t] | sort) as $stamps
| [$waits[] as $w | first($stamps[] | select(. > $w)) as $end | ev("permission"; $end; $end - $w)] as $perms
| reduce ($all | map(select((.isSidechain | not) and (.isMeta | not) and (.type == "user" or .type == "assistant"))) | sort_by(.timestamp | t))[] as $r
  ({last: null, first: null, asks: {}, ask: false, out: []};
   ($r.timestamp | t) as $now
   | if ($r | human) and .last != null then .out += [ev(if .ask then "answer" else "prompt" end; $now; $now - .last)] | .ask = false
     elif $r.type == "assistant" then (if ($r | body | test("\\S")) then .ask = ($r | asks) else . end) | .asks += ([$r.message.content[]? | select(.type == "tool_use" and .name == "AskUserQuestion") | {(.id): $now}] | add // {})
     elif $r.type == "user" and ($r | tool_result) then
       reduce ($r.message.content[] | select(.type == "tool_result") | .tool_use_id) as $id (.;
           if .asks[$id] then .out += [ev("question"; $now; $now - .asks[$id])] | del(.asks[$id]) else . end)
     else . end
   | .last = $now | .first //= $now)
| ((.out + $perms) | sort_by(.ts)[]), {sid: $sid, kind: "session", first, last}'

one() { # one <transcript>: its events and session line
  local f="$1" sid w title; sid="$(basename "$f" .jsonl)"
  w="[]"; [ -s "$waits" ] && w="$(jq -sc --arg s "$sid" '[.[] | select(.sid == $s) | .ts | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601] | sort' "$waits" 2>/dev/null || echo "[]")"
  title="$(grep -F '"type":"ai-title"' "$f" 2>/dev/null | tail -n1 | jq -r '.aiTitle // empty' 2>/dev/null || true)"
  jq -nc --arg sid "$sid" --argjson cap "$cap" --argjson waits "${w:-[]}" "$prog" "$f" |
    jq -c --arg title "$title" 'if .kind == "session" then . + {title: $title} else . end' || true
}
[ -n "$file" ] && { one "$file" >"$out/$(basename "$file")"; exit 0; }
# one transcript per process, one process per CPU, each into its own file: jq flushes in blocks
# that split lines, so workers sharing one output would splice each other's lines
out="$(mktemp -d)"; trap 'rm -rf "$out"' EXIT
find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" -mindepth 2 -maxdepth 2 -name '*.jsonl' -mtime -"$days" -print0 2>/dev/null |
  xargs -0 -n1 -P "$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)" bash "$0" --cap "$cap" --out "$out" --one || true
cat "$out"/* 2>/dev/null || true
