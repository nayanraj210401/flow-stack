#!/usr/bin/env bash
# status.sh [dir]: the active task's state as one JSON line, for the flow band (hooks/register.tsx).
#   {"task":"","slice":{"id":"","title":""},"done":0,"total":0,"tdd":"",
#    "evidence":{"label":"","verdict":"","ts":""},"stale":false}
# The slice is this lane's TDD slice when the lock is on, else the first `doing` one.
# Prints {} when no task is active. Reads only; never fails the caller.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../../../hooks/roots.sh"; flow_roots "${1:-$PWD}"; flow_task
command -v jq >/dev/null 2>&1 && [ -n "$FLOW_TASK_DIR" ] || { echo '{}'; exit 0; }

d="$FLOW_TASK_DIR"; st="$(flow_state_dir "$d")"
read -r tdd_id tdd _ 2>/dev/null <"$st/TDD" || { tdd_id=""; tdd=""; }
slice="$(awk -v id="$tdd_id" '/^## /{h=substr($0,4); cur=$2} id != "" && cur == id {print h; exit} id == "" && /^status: doing/{print h; exit}' "$d/SLICES.md" 2>/dev/null)"
total="$(grep -c '^status:' "$d/SLICES.md" 2>/dev/null)"
done_n="$(grep -c '^status: done' "$d/SLICES.md" 2>/dev/null)"
# "### <ts> · <label> · <verdict> · exit=<n>" (conventions.md); output inside a block can hold "### " too
ev="$(grep -E '^### [^ ]+ · [^ ]+ · [A-Z]+ · exit=' "$st/EVIDENCE.md" 2>/dev/null | tail -n1 | awk -F' · ' '{sub(/^### /,"",$1); print $1 "\t" $2 "\t" $3}')"
IFS=$'\t' read -r ev_ts ev_label ev_verdict <<<"$ev"
last_edit="$(jq -r 'select(.tool=="Edit" or .tool=="Write" or .tool=="MultiEdit") | .ts' "$st/trail.jsonl" 2>/dev/null | tail -n1)"
stale=false
[ -n "${ev_ts:-}" ] && [ -n "$last_edit" ] && [[ "$ev_ts" < "$last_edit" ]] && stale=true

jq -nc --arg task "$FLOW_TASK" --arg slice "$slice" \
  --arg done "${done_n:-0}" --arg total "${total:-0}" --arg tdd "$tdd" \
  --arg ts "${ev_ts:-}" --arg label "${ev_label:-}" --arg verdict "${ev_verdict:-}" --argjson stale "$stale" '
  # repo files are untrusted: no control characters (terminal escapes) reach the band or spinner
  def clean: gsub("[\u0001-\u001f\u007f-\u009f]"; "");
  {task: ($task | clean),
   slice: ($slice | if . == "" then null else {id: (split(" · ")[0] | clean), title: (split(" · ")[1:] | join(" · ") | clean)} end),
   done: ($done | tonumber), total: ($total | tonumber), tdd: ($tdd | clean),
   evidence: (if $ts == "" then null else {label: ($label | clean), verdict: ($verdict | clean), ts: ($ts | clean)} end),
   stale: $stale}'
