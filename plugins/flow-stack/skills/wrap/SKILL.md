---
name: wrap
description: "End-of-day digest across your repos: shipped, waiting on you, in flight, debt due, first step tomorrow. /flow-stack:wrap."
disable-model-invocation: true
---

# wrap: close the day in one screen

Long agent days blur together. A short wrap protects tomorrow's morning and tonight's sleep.

## Gather (subagent when more than 2 repos)

For each repo in the profile's `# Repos` (plus the current one):
- Today's commits: `git log --since=midnight --author="$(git config user.email)" --oneline`.
- Open flow tasks: `.flow/tasks/*/` with slice progress, and an open GATE or HANDOFF in each.
- Open PRs with the human's review requested, or their own PRs with new comments (`gh pr status`, if authed).
- Debt entries whose trigger may have fired.

Today's cost: `../budget/scripts/cost.sh`.

## Output (≤ 15 lines)

```
wrap · <date> · $<today>
SHIPPED
  - <repo>: <what, in behavior terms> (<n> commits)
WAITING ON YOU
  - <repo>/<task>: GATE · <question>
  - <repo>: PR #<n> review requested
IN FLIGHT
  - <repo>/<task>: S3/5 · handoff written
DEBT DUE
  - D4 · <shortcut> · trigger fired: <why>
TOMORROW, FIRST
  - <one concrete action>
```

Then offer `reflect` if today had corrections worth keeping, and stop. No motivational sign-off.
