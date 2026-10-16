#!/usr/bin/env bash
# recall-backslash.test.sh: a literal backslash-n / backslash-t in a message is shown as written (#97).
set -uo pipefail
R="$(cd "$(dirname "$0")" && pwd)/recall.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/recall-backslash.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export CLAUDE_CONFIG_DIR="$SB/claude" FLOW_STACK_HOME="$SB/home" HOME="$SB/hm"
mkdir -p "$SB/repo" "$SB/hm"
cd "$SB/repo" && git init -q
dir="$CLAUDE_CONFIG_DIR/projects/$(printf '%s' "$PWD" | sed 's/[^A-Za-z0-9]/-/g')"
mkdir -p "$dir"
msg='use printf "a\nb" and path C:\temp\new'
jq -nc --arg m "$msg" '{type:"user",timestamp:"2026-10-13T00:00:00Z",message:{content:$m}}' >"$dir/abcd1234.jsonl"
jq -nc --arg m $'line one\nline two\tafter tab\r\nend' '{type:"assistant",timestamp:"2026-10-13T00:01:00Z",message:{content:[{type:"text",text:$m}]}}' >>"$dir/abcd1234.jsonl"

out="$("$R" show abcd)"
grep -qF "you: $msg" <<<"$out" && ok "show keeps literal \\n and \\t" || bad "show: $out"
grep -qF 'claude: line one line two after tab end' <<<"$out" && ok "real newline/tab/CRLF still become spaces" || bad "newline: $out"
out="$("$R" grep 'temp\\new')"
[[ "$out" == *" · abcd1234 · you: $msg" ]] && ok "grep finds what was typed" || bad "grep: $out"
out="$("$R" sessions)"
grep -qF "first: $msg" <<<"$out" && ok "sessions shows the prompt as written" || bad "sessions: $out"
[ "$FAILS" = 0 ] || { echo "$FAILS failed"; exit 1; }
echo "all passed"
