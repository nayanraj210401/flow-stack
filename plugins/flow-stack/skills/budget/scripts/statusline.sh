#!/usr/bin/env bash
# statusline.sh: Claude Code status line. Shows model · context % · session $ · active flow task.
# Install via setup (it chains with an existing status line if you have one:
#   FLOW_STATUSLINE_CHAIN="<your old command>").
input="$(cat)"
command -v jq >/dev/null 2>&1 || { echo "flow"; exit 0; }
model="$(jq -r '.model.display_name // .model.id // "?"' <<<"$input")"
cwd="$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input")"
cost="$(jq -r '.cost.total_cost_usd // empty' <<<"$input")"
pct="$(jq -r '.context_window.used_percentage // .context_window.percent_used // empty' <<<"$input")"
root="$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null || echo "${cwd:-.}")"
task="$(head -n1 "$root/.flow/ACTIVE" 2>/dev/null | tr -d '[:space:]')"
out="$model"
[ -n "$pct" ] && out="$out · ctx $(printf '%.0f' "$pct")%"
[ -n "$cost" ] && out="$out · \$$(printf '%.2f' "$cost")"
[ -n "$task" ] && out="$out · flow:$task"
if [ -n "${FLOW_STATUSLINE_CHAIN:-}" ]; then
  prev="$(bash -c "$FLOW_STATUSLINE_CHAIN" <<<"$input" 2>/dev/null | head -n1)"
  [ -n "$prev" ] && out="$prev │ $out"
fi
echo "$out"
