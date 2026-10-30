#!/usr/bin/env bash
# recall: recall.sh reads this repo's past Claude Code conversations and keeps only the human's
# prompts and Claude's replies (no tool output, skill text, agent hand-backs, notifications),
# redacted, scoped to this repo and the --days window.
. "$(dirname "$0")/lib.sh"; sandbox recall
R="$S/recall/scripts/recall.sh"
proj() { printf '%s/projects/%s' "$CLAUDE_CONFIG_DIR" "$(printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g')"; }
P="$(proj "$PWD")"; mkdir -p "$P"
line() { jq -nc "$@"; }
{
  line '{type:"ai-title", aiTitle:"Rate limit work", sessionId:"aaaa1111"}'
  line '{type:"user", timestamp:"2026-09-28T09:59:00Z", origin:{kind:"human"}, message:{role:"user", content:"<command-name>/clear</command-name>\n<command-args></command-args>"}}'
  line '{type:"user", timestamp:"2026-09-28T10:00:00Z", origin:{kind:"human"}, message:{role:"user", content:"add a rate-limit to login; token=sk-abcd1234567890XYZ"}}'
  line '{type:"user", timestamp:"2026-09-28T10:00:01Z", isMeta:true, message:{role:"user", content:[{type:"text", text:"SKILLTEXT rate-limit playbook body"}]}}'
  line '{type:"assistant", timestamp:"2026-09-28T10:00:02Z", message:{role:"assistant", content:[{type:"thinking", thinking:"THINKING rate-limit"}, {type:"text", text:"Plan: a token bucket for the rate-limit."}, {type:"tool_use", name:"Bash", input:{command:"TOOLCALL rate-limit"}}]}}'
  line '{type:"user", timestamp:"2026-09-28T10:00:03Z", message:{role:"user", content:[{type:"tool_result", content:"TOOLOUTPUT rate-limit"}]}}'
  line '{type:"user", timestamp:"2026-09-28T10:00:04Z", origin:{kind:"peer"}, message:{role:"user", content:"Another Claude session sent a message: PEER rate-limit"}}'
  line '{type:"user", timestamp:"2026-09-28T10:00:05Z", message:{role:"user", content:"<task-notification>NOTIFY rate-limit</task-notification>"}}'
  line '{type:"user", timestamp:"2026-09-28T10:00:06Z", origin:{kind:"human"}, message:{role:"user", content:"<command-message>flow</command-message>\n<command-name>/flow-stack:flow</command-name>\n<command-args>ship the rate-limit, no redis</command-args>"}}'
  line '{type:"user", timestamp:"2026-09-28T10:00:07Z", isSidechain:true, message:{role:"user", content:"SIDECHAIN rate-limit"}}'
  line --arg p "$(printf 'x%.0s' $(seq 1 222)) LONGKEY sk-zyxw9876543210ABC" '{type:"user", timestamp:"2026-09-28T10:00:08Z", origin:{kind:"human"}, message:{role:"user", content:$p}}'
  line '{type:"pr-link", prNumber:42, sessionId:"aaaa1111"}'
} >"$P/aaaa1111-0000.jsonl"
line '{type:"user", timestamp:"2026-09-01T10:00:00Z", origin:{kind:"human"}, message:{role:"user", content:"OLD rate-limit idea"}}' >"$P/bbbb2222-0000.jsonl"
touch -t 202001010000 "$P/bbbb2222-0000.jsonl"
O="$(proj "$SB/other")"; mkdir -p "$O"
line '{type:"user", timestamp:"2026-09-28T10:00:00Z", origin:{kind:"human"}, message:{role:"user", content:"OTHERREPO rate-limit"}}' >"$O/cccc3333-0000.jsonl"

echo "-- sessions"
out="$("$R" sessions 2>&1)"
has "$out" "aaaa1111 · Rate limit work · 4 prompts · PRs #42" && ok "lists the conversation with title, prompt count, PR" || bad "sessions line: $out"
has "$out" "first: add a rate-limit to login" && ok "first prompt skips a bare /clear" || bad "first prompt: $out"
has "$out" "bbbb2222" && bad "older than --days is skipped" || ok "older than --days is skipped"
has "$("$R" sessions --days 100000 2>&1)" "bbbb2222" && ok "--days widens the window" || bad "--days widens the window"

echo "-- grep keeps the human and Claude, drops the noise"
out="$("$R" grep 'rate-limit' 2>&1)"
has "$out" "you: add a rate-limit to login" && ok "human prompt" || bad "human prompt: $out"
has "$out" "claude: Plan: a token bucket" && ok "Claude's reply" || bad "Claude's reply"
has "$out" "you: /flow-stack:flow ship the rate-limit, no redis" && ok "slash command shown as command + args" || bad "slash command: $out"
for n in SKILLTEXT THINKING TOOLCALL TOOLOUTPUT PEER NOTIFY SIDECHAIN OTHERREPO OLD; do
  has "$out" "$n" && bad "drops $n" || ok "drops $n"
done
has "$out" "abcd1234567890XYZ" && bad "secret redacted" || ok "secret redacted"
has "$("$R" grep 'rate-limit' --skip aaaa 2>&1)" "aaaa1111" && bad "--skip drops a conversation" || ok "--skip drops a conversation"

echo "-- show"
out="$("$R" show aaaa 2>&1)"
[ "$(grep -c ': ' <<<"$out")" = 5 ] && ok "show prints the 5 real messages in order" || bad "show: $out"
fails "show refuses an unknown id" "$R" show zzzz
has "$("$R" grep LONGKEY 2>&1)" "sk-zyxw98" && bad "a key cut by truncation still can't leak" || ok "a key cut by truncation still can't leak"
git worktree add -q "$SB/lane" -b lane 2>/dev/null
has "$(cd "$SB/lane" && "$R" sessions 2>&1)" "aaaa1111" && ok "from a worktree lane, reads the main checkout's conversations" || bad "worktree lane"
has "$("$R" sessions --repo "$SB/other" 2>&1)" "cccc3333" && ok "--repo reads another repo when asked" || bad "--repo"
finish
