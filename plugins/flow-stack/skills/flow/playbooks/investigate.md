# Playbook: investigate

Use when: a question. "How does X work", "why is Y like this", "what changed", "where should Z live".
Principles: spend-cheap-save-expensive, reader-first.

1. Pick the lens: `how` (runtime flow, ownership), `why` (rationale from git, PRs, issues, docs), `what` (a diff, PR, branch, or unfamiliar module), or `teach` (they want to understand it deeply).
2. Read `.flow/map.md` first if it exists. Route reading of more than about 5 files to an Explore subagent and keep only its cited conclusions.
3. Answer with `brief`: the answer in the first line, then at most 4 supporting lines, each with a `file:line` or commit citation. Offer depth ("want the full flow?") instead of dumping it.
4. No task folder, no gates. If the answer reveals a defect, say so and offer the bug playbook.
