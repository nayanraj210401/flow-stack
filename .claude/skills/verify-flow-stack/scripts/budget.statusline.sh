#!/usr/bin/env bash
# budget.statusline: the status line shows model · context % · session $ · active task,
# and chains after the user's previous status line.
. "$(dirname "$0")/lib.sh"; sandbox budget.statusline
SL="$S/budget/scripts/statusline.sh"
payload() { jq -nc --arg d "$PWD" '{model:{display_name:"Opus"}, workspace:{current_dir:$d}, cost:{total_cost_usd:1.234}, context_window:{used_percentage:41.6}}'; }
out="$(payload | "$SL")"
[ "$out" = 'Opus · ctx 42% · $1.23' ] && ok "no task: $out" || bad "got: $out"
toy_task demo "mul multiplies" "no division"
out="$(payload | "$SL")"
[ "$out" = 'Opus · ctx 42% · $1.23 · flow:demo' ] && ok "with task: $out" || bad "got: $out"
out="$(payload | FLOW_STATUSLINE_CHAIN='echo previous-line' "$SL")"
[ "$out" = 'previous-line │ Opus · ctx 42% · $1.23 · flow:demo' ] && ok "chained: $out" || bad "got: $out"
out="$(echo '{}' | "$SL")"; [ -n "$out" ] && ok "sparse input still prints ($out)" || bad "empty output"
echo "$out" >"$ART/statusline.txt"
finish
