#!/usr/bin/env bash
# collect.sh: everything the board shows, as one JSON document on stdout.
#   collect.sh [--no-cost] [--no-prs] [repo-path ...]
#
# Repos: the given paths, else the profile's `# Repos` paths plus the current repo.
# Reads only what flow-stack already writes (.flow/tasks, features, debt.md) and git;
# PRs come from gh and cost from ccusage when available (both optional, both skippable).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../../../hooks/roots.sh"

cost=1; prs=1; repos=()
while [ $# -gt 0 ]; do
  case "$1" in --no-cost) cost=0 ;; --no-prs) prs=0 ;; *) repos+=("$1") ;; esac; shift
done
home="${FLOW_STACK_HOME:-$HOME/.flow-stack}"; profile="$home/profile.md"

if [ "${#repos[@]}" -eq 0 ]; then
  while IFS= read -r p; do repos+=("${p/#\~/$HOME}"); done < <(
    awk '/^# Repos/{on=1;next} /^# /{on=0} on && /^- path:/{sub(/^- path:[[:space:]]*/,""); sub(/[[:space:]]+$/,""); print}' "$profile" 2>/dev/null)
  git rev-parse --show-toplevel >/dev/null 2>&1 && { flow_roots; repos+=("$FLOW_MAIN"); }
fi
current=""; git rev-parse --show-toplevel >/dev/null 2>&1 && { flow_roots; current="$FLOW_MAIN"; }

# first non-comment line under "## <heading>" in a markdown file
md_first() { awk -v h="## $2" '/<!--/{c=1} c{if(/-->/)c=0; next} $0==h{on=1;next} on&&/^## /{exit} on&&NF&&$0!="- "{print;exit}' "$1" 2>/dev/null; }

task_json() { # task_json <task-dir> <active-slug>
  local d="$1" slug; slug="$(basename "$d")"
  local slices gates est trace_usd
  slices="$(awk '/^## /{if(id!="")print id"\t"t"\t"s; id=$2; t=$0; sub(/^## [^ ]+ · /,"",t); s="todo"} /^status:/{s=$2} END{if(id!="")print id"\t"t"\t"s}' "$d/SLICES.md" 2>/dev/null |
    jq -Rsc 'split("\n") | map(select(length>0) | split("\t") | {id:.[0], title:.[1], status:.[2]}) | map(select(.id | test("^S[0-9]")))')"
  gates="$(grep -E '^(GATE · |- \[ \] )' "$d/GATES.md" 2>/dev/null | sed -E 's/^(GATE · |- \[ \] )//' | jq -Rsc 'split("\n") | map(select(length>0))')"
  est="$(sed -n 's/.*usd=\([0-9.]*\).*/\1/p' "$d/ESTIMATE" 2>/dev/null | head -n1)"
  trace_usd="$(awk -F'|' '$2 ~ /^ *\$ *$/ {gsub(/[ $]/,"",$4); print $4; exit}' "$d/TRACE.md" 2>/dev/null)"
  jq -nc --arg slug "$slug" --arg goal "$(md_first "$d/INTENT.md" Goal)" --arg playbook "$(cat "$d/PLAYBOOK" 2>/dev/null)" \
    --argjson slices "${slices:-[]}" --argjson gates "${gates:-[]}" \
    --arg est "$est" --arg actual "$trace_usd" \
    --argjson active "$([ "$slug" = "$2" ] && echo true || echo false)" \
    --argjson closed "$([ -f "$d/TRACE.md" ] && grep -qv '^<!--' "$d/TRACE.md" && [ -n "$(md_first "$d/TRACE.md" Outcome)" ] && echo true || echo false)" \
    --argjson handoff "$(ls "$d"/HANDOFF*.md >/dev/null 2>&1 && echo true || echo false)" \
    --argjson lanes "$(ls -d "$d"/lanes/*/ 2>/dev/null | wc -l | tr -d ' ')" \
    --argjson repos "$(cut -f1 "$d/REPOS" 2>/dev/null | jq -Rsc 'split("\n") | map(select(length>0))')" \
    '{slug:$slug, goal:$goal, playbook:$playbook, active:$active, closed:$closed, handoff:$handoff, lanes:$lanes, repos:$repos,
      slices:$slices, gates:$gates,
      estimate_usd:($est|tonumber? // null), actual_usd:($actual|tonumber? // null)}'
}

repo_json() {
  local r="$1"; [ -d "$r/.git" ] || [ -f "$r/.git" ] || return 0
  local fd="$r/.flow" active tasks="[]" feats="[]" decs="[]" debt="[]" shipped pr="null"
  active="$(head -n1 "$fd/ACTIVE" 2>/dev/null | tr -d '[:space:]')"
  local linked="null"
  case "$active" in @*) linked="$(jq -nc --arg h "$(basename "${active%:*}")" --arg s "${active##*:}" '{home:$h, slug:$s}')" ;; esac
  local tj=()
  for d in "$fd"/tasks/*/; do [ -d "$d" ] && tj+=("$(task_json "${d%/}" "$active")"); done
  [ "${#tj[@]}" -gt 0 ] && tasks="$(printf '%s\n' "${tj[@]}" | jq -sc .)"
  feats="$(for f in "$fd"/features/*.md; do [ -f "$f" ] && [ "$(basename "$f")" != README.md ] || continue
      awk 'NR==1&&$0=="---"{fm=1;next} fm&&$0=="---"{exit} fm{k=$0; sub(/:.*/,"",k); v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); if(k=="id"||k=="status"||k=="verified") printf "%s\t%s\n", k, v}' "$f" |
      jq -Rsc 'split("\n") | map(select(length>0) | split("\t") | {(.[0]): .[1]}) | add'
    done | jq -sc 'map(select(. != null))')"
  decs="$(for t in "$fd"/tasks/*/DECISIONS.tsv; do [ -f "$t" ] || continue; s="$(basename "$(dirname "$t")")"
      tail -n +2 "$t" | awk -F'\t' -v s="$s" 'NF>=3{print $1"\t"s"\t"$2"\t"$3"\t"$4"\t"$6}'; done |
    jq -Rsc 'split("\n") | map(select(length>0) | split("\t") | {ts:.[0], task:.[1], who:.[2], decision:.[3], why:.[4], reversible:.[5]})
      | map(select(.who != "human")) | sort_by(.ts) | reverse | .[0:8]')"
  debt="$(grep -E '^- \[[ x]\] D[0-9]+' "$fd/debt.md" 2>/dev/null |
    jq -Rsc 'split("\n") | map(select(length>0) | capture("^- \\[(?<x>[ x])\\] (?<id>D[0-9]+) · (?<rest>.*)$")
      | {id, open:(.x==" "), text:(.rest | split(" · ") | .[1] // .[0]),
         trigger:((.rest | capture("repay when: (?<t>[^·]*)").t // "") | sub(" +$";""))})')"
  shipped="$(git -C "$r" log --first-parent --since=7.days --format='%h%x09%cs%x09%s' 2>/dev/null | head -n 12 |
    jq -Rsc 'split("\n") | map(select(length>0) | split("\t") | {sha:.[0], date:.[1], subject:.[2]})')"
  if [ "$prs" = 1 ] && command -v gh >/dev/null 2>&1; then
    pr="$(cd "$r" && gh pr status --json number,title,url,isDraft,reviewDecision 2>/dev/null |
      jq -c '{mine:[.createdBy[]? | {number,title,url,draft:.isDraft,review:.reviewDecision}],
              review_requested:[.needsReview[]? | {number,title,url}]}' 2>/dev/null || echo null)"
  fi
  jq -nc --arg name "$(basename "$r")" --arg path "$r" \
    --arg head "$(git -C "$r" rev-parse --short HEAD 2>/dev/null)" --arg branch "$(git -C "$r" branch --show-current 2>/dev/null)" \
    --argjson dirty "$(git -C "$r" status --porcelain 2>/dev/null | grep -vc '^?? .flow/' || true)" \
    --argjson current "$([ "$r" = "$current" ] && echo true || echo false)" \
    --argjson tasks "$tasks" --argjson features "${feats:-[]}" --argjson decisions "${decs:-[]}" \
    --argjson debt "${debt:-[]}" --argjson shipped "${shipped:-[]}" --argjson prs "${pr:-null}" --argjson linked "$linked" \
    '{name:$name, path:$path, head:$head, branch:$branch, dirty:$dirty, current:$current,
      tasks:$tasks, linked:$linked, features:$features, decisions:$decisions, debt:$debt, shipped:$shipped, prs:$prs}'
}

spend="null"
if [ "$cost" = 1 ]; then
  if command -v ccusage >/dev/null 2>&1; then cu=(ccusage); elif command -v npx >/dev/null 2>&1; then cu=(npx -y ccusage@latest); else cu=(); fi
  if [ "${#cu[@]}" -gt 0 ]; then
    since="$(date -v-13d +%Y%m%d 2>/dev/null || date -d '13 days ago' +%Y%m%d)"
    spend="$("${cu[@]}" daily --json --since "$since" 2>/dev/null |
      jq -c '[.daily[] | {date:(.date // .period), usd:((.totalCost // .cost) * 100 | round / 100)}]' 2>/dev/null || echo null)"
  fi
fi

seen=" "; rj=()
for r in "${repos[@]}"; do
  r="$(cd "$r" 2>/dev/null && pwd -P)" || continue
  case "$seen" in *" $r "*) continue ;; esac; seen="$seen$r "
  j="$(repo_json "$r")"; [ -n "$j" ] && rj+=("$j")
done
[ -n "$current" ] && current="$(cd "$current" && pwd -P)"
printf '%s\n' "${rj[@]:-}" | jq -sc --arg at "$(date +%FT%T%z)" --argjson spend "${spend:-null}" \
  --argjson budget "$(sed -n 's/^[[:space:]]*review_minutes_per_day:[[:space:]]*\([0-9]*\).*/\1/p' "$profile" 2>/dev/null | head -n1 | grep . || echo null)" \
  '{generated:$at, review_minutes_per_day:$budget, spend:$spend, repos:map(select(. != null))}'
