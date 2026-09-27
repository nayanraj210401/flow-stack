---
name: what
description: "Summarize what changed or what something is: a diff, PR, branch, module, or what the agent did. Use for \"what changed\", \"summarize this PR\", \"catch me up\"."
---

# what

The human wants the shape, not the details. Save their attention.

## Target

- **A diff, branch, or PR:** `git diff --stat <base>...<head>`, then the actual hunks for the top files by churn. For a PR, `gh pr view <n>` and `gh pr diff <n>`.
- **A module:** its public surface (exports, routes, commands), what it depends on, and who calls it.
- **"What did you/the agent do":** the task's `trail.jsonl` and DECISIONS.tsv, or `git log` since a time.

## Answer shape (≤ 8 lines)

```
<one-sentence summary of the intent of the change>
- <area>: <what changed, in behavior terms> (files)
- <area>: …
risk: <the one thing most worth a human look, with file:line>
not covered: <what was not tested / verified>, if anything
```

Behavior terms beat code terms: "login now locks after 5 failures", not "added counter to AuthService". For a deeper walkthrough, offer `tour` (risk-ranked, for review) or `teach` (to understand it deeply).
