#!/usr/bin/env bash
# PreCompact: write a deterministic snapshot of the active task so the next
# context (after compaction) resumes from files, not from a lossy summary.
. "$(dirname "$0")/lib.sh"
flow_init pre-compact
flow_enabled handoff || exit 0
[ -n "$FLOW_TASK_DIR" ] || exit 0

out="$FLOW_STATE_DIR/HANDOFF.auto.md"
{
  printf '# Auto handoff · %s · %s\n\n' "$FLOW_TASK" "$(date -u +%FT%TZ)"
  printf 'Written by the PreCompact hook. HANDOFF.md (hand-written) wins when newer.\n\n'

  printf '## Goal\n'
  awk '/<!--/{c=1} c{if(/-->/)c=0; next} /^## Goal/{on=1;next} on && /^## /{exit} on && NF{print}' "$FLOW_TASK_DIR/INTENT.md" 2>/dev/null | head -n 5
  printf '\n## Slices\n'
  awk '/^## /{h=$0; sub(/^## /,"",h)} /^status:/{s=$2; print "- " s " · " h}' "$FLOW_TASK_DIR/SLICES.md" 2>/dev/null

  printf '\n## Latest evidence\n'
  grep -E '^### ' "$FLOW_STATE_DIR/EVIDENCE.md" 2>/dev/null | tail -n 5 | sed 's/^### /- /'

  printf '\n## Recent decisions\n'
  tail -n +2 "$FLOW_TASK_DIR/DECISIONS.tsv" 2>/dev/null | tail -n 5 | awk -F'\t' '{print "- [" $2 "] " $3 " · " $4}'

  printf '\n## Working tree\n```\n'
  git -C "$FLOW_ROOT" status --short 2>/dev/null | head -n 30
  printf '```\n\n## Last 15 actions\n'
  tail -n 15 "$FLOW_STATE_DIR/trail.jsonl" 2>/dev/null | jq -r '"- " + .tool + " · " + (.target | .[0:120])' 2>/dev/null

  printf '\n## Resume\nRead INTENT.md and SLICES.md in .flow/tasks/%s/, then continue the slice marked `doing`.\n' "$FLOW_TASK"
} >"$out"
exit 0
