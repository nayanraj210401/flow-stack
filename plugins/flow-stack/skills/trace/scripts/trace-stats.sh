#!/usr/bin/env bash
# trace-stats.sh: mechanical facts for TRACE.md from the active task's trail,
# evidence, decisions, and git. The trace skill turns them into the narrative.
set -uo pipefail
. "$(dirname "$0")/../../../hooks/roots.sh"; flow_roots; flow_task
root="$FLOW_ROOT"
slug="${1:-$FLOW_TASK}"
d="${FLOW_TASK_HOME:-$FLOW_MAIN}/.flow/tasks/$slug"
[ -d "$d" ] || { echo "trace-stats: no task '$slug'" >&2; exit 2; }
t="$(mktemp)"; trap 'rm -f "$t"' EXIT
cat "$d"/trail.jsonl "$d"/lanes/*/trail.jsonl 2>/dev/null | jq -sc 'sort_by(.ts) | .[]' >"$t" 2>/dev/null || true
[ -s "$t" ] || rm -f "$t"

echo "# facts · $slug"
if [ -f "$t" ]; then
  echo "## span"
  jq -rs 'if length > 0 then "first: \(.[0].ts)\nlast:  \(.[-1].ts)\ntool calls: \(length)\nsessions: \(map(.sid) | unique | length)" else "empty trail" end' "$t"
  echo "## tools"
  jq -r '.tool' "$t" | sort | uniq -c | sort -rn
  echo "## files edited"
  jq -r 'select(.tool == "Edit" or .tool == "Write" or .tool == "MultiEdit") | .target' "$t" | sed "s#^$root/##" | sort | uniq -c | sort -rn | head -n 30
  echo "## commands (top 20 by count)"
  jq -r 'select(.tool == "Bash") | .target' "$t" | cut -c1-100 | sort | uniq -c | sort -rn | head -n 20
  echo "## errors"
  jq -r 'select(.err == true) | "\(.ts) \(.tool) \(.target[0:100])"' "$t" | tail -n 20
  echo "## subagents"
  jq -r 'select(.tool == "Agent" or .tool == "Task") | "\(.ts) \(.target[0:100])"' "$t"
fi
echo "## evidence"
grep -E '^### ' "$d/EVIDENCE.md" 2>/dev/null | sed 's/^### //'
echo "## decisions"
tail -n +2 "$d/DECISIONS.tsv" 2>/dev/null
echo "## estimate"
cat "$d/ESTIMATE" 2>/dev/null || echo "none"
echo "## git"
git -C "$root" diff --stat HEAD 2>/dev/null | tail -n 1
git -C "$root" log --oneline --since="$(jq -rs '.[0].ts // empty' "$t" 2>/dev/null)" 2>/dev/null | head -n 20
