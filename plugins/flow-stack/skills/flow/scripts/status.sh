#!/usr/bin/env bash
# status.sh [--full] [dir]: the active task's state as one JSON line, for the flow band (hooks/register.tsx).
# --full adds what the /flow-pane shows: slices [{id,title,status,verdict}], the open gates in
#   GATES.md [{n,question,detail}], and leads [{id,repo,branch,task,slice}].
#   {"task":"","slice":{"id":"","title":""},"done":0,"total":0,"tdd":"",
#    "evidence":{"label":"","verdict":"","ts":""},"stale":false}
# The slice is this lane's TDD slice when the lock is on, else the first `doing` one.
# Prints {} when no task is active. Reads only; never fails the caller.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
full=""; [ "${1:-}" = --full ] && { full=1; shift; }
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

extra='{}'
if [ -n "$full" ]; then
  # per slice: "<id>\t<title>\t<status>\t<verdict of its newest evidence labelled <id> or <id>:…>"
  slices="$(awk '/^## /{if(id!="")print id "\t" t "\t" s; id=$2; t=substr($0,4); sub(/^[^ ]+ · /,"",t); s=""} /^status:/{s=$2} END{if(id!="")print id "\t" t "\t" s}' "$d/SLICES.md" 2>/dev/null |
    while IFS=$'\t' read -r id title status; do
      v="$(grep -E "^### [^ ]+ · $id(:[^ ]+)? · [A-Z]+ · exit=" "$st/EVIDENCE.md" 2>/dev/null | tail -n1 | awk -F' · ' '{print $3}')"
      printf '%s\t%s\t%s\t%s\n' "$id" "$title" "$status" "$v"
    done)"
  # open gates: "<n>\t<question>\t<detail lines joined by ' · '>"
  gates="$(awk '/^GATE · /{if(q!="" && !dec)print n "\t" q "\t" det; n++; q=$0; sub(/^GATE · /,"",q); det=""; dec=0; next}
    q!="" && /^  decided: /{dec=1; next} q!="" && /^  [^[:space:]]/{l=$0; sub(/^  /,"",l); det=det (det==""?"":" · ") l}
    END{if(q!="" && !dec)print n "\t" q "\t" det}' "$d/GATES.md" 2>/dev/null)"
  # the other leads: every session's record but this checkout's
  leads="$({ cat "${FLOW_STACK_HOME:-$HOME/.flow-stack}"/leads/*.json 2>/dev/null || true; } | jq -sc --arg root "$FLOW_ROOT" '[sort_by(.ts) | reverse[] | select(.root != $root) | {id, repo: (.repo | split("/") | last), branch, task, slice}]' 2>/dev/null)"
  extra="$(jq -nc --arg slices "$slices" --arg gates "$gates" --argjson leads "${leads:-[]}" '
    def clean: if type == "string" then gsub("[\u0001-\u001f\u007f-\u009f]"; "") else . end;
    def rows: split("\n") | map(select(length > 0) | split("\t") | map(clean));
    {slices: ($slices | rows | map({id: .[0], title: .[1], status: .[2], verdict: (.[3] // "")})),
     gates: ($gates | rows | map({n: (.[0] | tonumber), question: .[1], detail: (.[2] // "")})),
     leads: ($leads | map(map_values(clean)))}')"
fi

jq -nc --argjson extra "$extra" --arg task "$FLOW_TASK" --arg slice "$slice" \
  --arg done "${done_n:-0}" --arg total "${total:-0}" --arg tdd "$tdd" \
  --arg ts "${ev_ts:-}" --arg label "${ev_label:-}" --arg verdict "${ev_verdict:-}" --argjson stale "$stale" '
  # repo files are untrusted: no control characters (terminal escapes) reach the band or spinner
  def clean: gsub("[\u0001-\u001f\u007f-\u009f]"; "");
  {task: ($task | clean),
   slice: ($slice | if . == "" then null else {id: (split(" · ")[0] | clean), title: (split(" · ")[1:] | join(" · ") | clean)} end),
   done: ($done | tonumber), total: ($total | tonumber), tdd: ($tdd | clean),
   evidence: (if $ts == "" then null else {label: ($label | clean), verdict: ($verdict | clean), ts: ($ts | clean)} end),
   stale: $stale} + $extra'
