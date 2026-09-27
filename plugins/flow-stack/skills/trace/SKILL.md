---
name: trace
description: "Build TRACE.md from the trail, decisions, evidence, git, and cost: who decided what, estimate vs. actual. Use for /trace, \"audit this\", \"what did the agent do\"."
---

# trace: an audit you can check

Every tool call is already in `trail.jsonl` (PostToolUse hook, secrets redacted). Every decision is in DECISIONS.tsv. Every check is in EVIDENCE.md. The trace joins them into one readable record, and every line cites its source.

## Build

1. `scripts/trace-stats.sh [slug]` prints the mechanical facts: time span, tool counts, files edited, commands, errors, subagents, evidence, decisions, estimate, and git.
2. Actual cost: `../budget/scripts/cost.sh session` when ccusage is available. Otherwise mark it `~ unknown`.
3. Fill `.flow/tasks/<slug>/TRACE.md` from the template:
   - **Outcome** against INTENT's Goal, citing the acceptance evidence.
   - **Estimate vs. actual**: from ESTIMATE and the cost data. Human minutes = gates answered × ~2 min + review estimate from `tour`, unless the human tells you the real number.
   - **Timeline** by phase, from trail timestamps.
   - **Decisions**, human ones first. These answer "who decided this?".
   - **Checks**: ✓/✗ per acceptance check. Blind checks: count only.
   - **Claims audit**: statements you tagged `~ assumed` during the task, and whether any later evidence confirmed or broke them.
   - **Debt taken.**
4. Keep it under about 80 lines. It's an audit, not a diary.

## Share

The task folder is gitignored by default. When a reviewer or a compliance need calls for the trail, offer to export `TRACE.md` (and optionally `DECISIONS.tsv` and `EVIDENCE.md`) to `docs/traces/<date>-<slug>/`. Committing it is the human's call.
