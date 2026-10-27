#!/usr/bin/env bash
# collect-attention.test.sh: collect.sh adds task sessions, today's attention and a parallel-work warning; --no-attention skips them.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
SB="$(mktemp -d "${TMPDIR:-/tmp}/collect-attention.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"; trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" HOME="$SB/hm" CLAUDE_CONFIG_DIR="$SB/claude"
mkdir -p "$HOME" "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/projects/-r" "$SB/r/.flow/tasks/t1"
printf 'review_minutes_per_day: 10\n\n# Board\n- hide: attention\n' >"$FLOW_STACK_HOME/profile.md"
b=$(( $(date +%s) - 1500 )); A=aaaaaaaa-0000-0000-0000-000000000001; B=bbbbbbbb-0000-0000-0000-000000000002; C=cccccccc-0000-0000-0000-000000000003
i=0; for s in $A $B $C; do
  o=$((i * 60)); i=$((i + 1))
  q="ok"; [ "$i" -gt 1 ] && q="ok?"   # B and C end on a question: overlapping waits, blocked once
  jq -nc --argjson b "$b" --argjson o "$o" --arg t "Title $i" --arg q "$q" '
    def at($s): $b + $o + $s | todate;
    {type:"user", timestamp:at(0), origin:{kind:"human"}, message:{content:"hi"}},
    {type:"assistant", timestamp:at(5), message:{content:[{type:"text", text:$q}]}},
    {type:"user", timestamp:at(305), origin:{kind:"human"}, message:{content:"more"}},
    {type:"ai-title", aiTitle:$t}' >"$CLAUDE_CONFIG_DIR/projects/-r/$s.jsonl"
done
{ for k in 10 310; do jq -nc --arg s $A --argjson t $((b + k)) '{ts:($t|todate),sid:$s,tool:"Bash",target:"x",err:false}'; done
  jq -nc --arg s $B --argjson t $((b + 370)) '{ts:($t|todate),sid:$s,tool:"Bash",target:"x",err:false}'; } >"$SB/r/.flow/tasks/t1/trail.jsonl"
cd "$SB/r" && git init -q && git config user.email t@e.x && git config user.name t && git commit -qm init --allow-empty
fail=0; chk() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; else echo "  ✗ $1: want [$3] got [$2]"; fail=1; fi; }
j="$("$H/collect.sh" --no-cost --no-prs "$SB/r" 2>/dev/null)"
chk sessions "$(jq -c '.repos[0].tasks[0].sessions|map([.title,.calls,.min,.blocked_min])' <<<"$j")" '[["Title 2",1,5,5],["Title 1",2,5,0]]'
chk attention_min "$(jq -c '.repos[0].tasks[0].attention_min' <<<"$j")" 10
chk today "$(jq -c '.attention.today|[.min,.prompts,.answers,.switches,.peak,.sessions]' <<<"$j")" '[15,1,2,2,3,3]'
chk blocked_wallclock "$(jq -c '.attention.today.blocked_min' <<<"$j")" 6
chk window "$(jq -c '.attention|[.days,.budget_min,(.by_day|length),(.by_day[-1]==.today)]' <<<"$j")" '[14,10,14,true]'
chk crit "$(jq -c '.attention.warnings|map([.level,(.text|startswith("🔴")),(.sids|length)])' <<<"$j")" '[["crit",true,3],["crit",true,3]]'
chk actions "$(jq -c '.attention.warnings|map(.text|test("Delegate|--auto|Close"))' <<<"$j")" '[true,true]'
chk no_prefs_warning "$(jq -c '.prefs.warnings' <<<"$j")" '[]'
n="$("$H/collect.sh" --no-cost --no-prs --no-attention "$SB/r" 2>/dev/null)"
chk no_attention "$(jq -c '[.attention, (.repos[0].tasks[0].sessions|map([.title,.calls,has("min")]))]' <<<"$n")" '[null,[["",1,false],["",2,false]]]'
bash "$H/collect-quality.test.sh" >/dev/null 2>&1 && echo "  ✓ quality test" || { echo "  ✗ quality test"; fail=1; }
[ "$fail" = 0 ] && echo PASS || exit 1
