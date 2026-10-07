#!/usr/bin/env bash
# status.sh [dir]: the active task's state as one JSON line, for the flow band (hooks/register.ts).
#   {"task":"","goal":"","slice":{"id":"","title":""},"done":0,"total":0,"tdd":"",
#    "evidence":{"label":"","verdict":"","ts":""},"stale":false}
# Prints {} when no task is active. Reads only; never fails the caller.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../../../hooks/roots.sh"; flow_roots "${1:-$PWD}"; flow_task
command -v jq >/dev/null 2>&1 && [ -n "$FLOW_TASK_DIR" ] || { echo '{}'; exit 0; }

d="$FLOW_TASK_DIR"; st="$(flow_state_dir "$d")"
goal="$(awk '/<!--/{c=1} c{if(/-->/)c=0; next} $0=="## Goal"{on=1; next} on && /^## /{exit} on && NF {print; exit}' "$d/INTENT.md" 2>/dev/null)"
slice="$(awk '/^## /{h=substr($0,4)} /^status: doing/{print h; exit}' "$d/SLICES.md" 2>/dev/null)"
total="$(grep -c '^status:' "$d/SLICES.md" 2>/dev/null)"
done_n="$(grep -c '^status: done' "$d/SLICES.md" 2>/dev/null)"
tdd="$(awk '{print $2; exit}' "$st/TDD" 2>/dev/null)"
# "### <ts> · <label> · <verdict> · exit=<n>"
ev="$(grep '^### ' "$st/EVIDENCE.md" 2>/dev/null | tail -n1 | awk -F' · ' '{sub(/^### /,"",$1); print $1 "\t" $2 "\t" $3}')"
IFS=$'\t' read -r ev_ts ev_label ev_verdict <<<"$ev"
last_edit="$(jq -r 'select(.tool=="Edit" or .tool=="Write" or .tool=="MultiEdit") | .ts' "$st/trail.jsonl" 2>/dev/null | tail -n1)"
stale=false
[ -n "${ev_ts:-}" ] && [ -n "$last_edit" ] && [[ "$ev_ts" < "$last_edit" ]] && stale=true

jq -nc --arg task "$FLOW_TASK" --arg goal "$goal" --arg slice "$slice" \
  --arg done "${done_n:-0}" --arg total "${total:-0}" --arg tdd "$tdd" \
  --arg ts "${ev_ts:-}" --arg label "${ev_label:-}" --arg verdict "${ev_verdict:-}" --argjson stale "$stale" '
  {task: $task, goal: $goal,
   slice: ($slice | if . == "" then null else {id: (split(" · ")[0]), title: (split(" · ")[1:] | join(" · "))} end),
   done: ($done | tonumber), total: ($total | tonumber), tdd: $tdd,
   evidence: (if $ts == "" then null else {label: $label, verdict: $verdict, ts: $ts} end),
   stale: $stale}'
