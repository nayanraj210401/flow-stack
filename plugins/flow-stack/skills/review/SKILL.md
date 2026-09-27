---
name: review
description: Fresh-context reviewer grades the diff against INTENT, evidence, and your taste; flags code that could be smaller. Use for /review, "second opinion", before a merge gate.
---

# review: a second pair of eyes with no stake in the code

The builder can't see its own blind spots. The reviewer starts from zero context, so it only knows what the artifacts say.

## Run

Spawn the `reviewer` agent (flow-stack:reviewer) with:
- the path of the task folder,
- the diff range (`git diff <base>...HEAD` plus uncommitted changes),
- nothing else. Don't summarize your work for it; the point is that it forms its own view.

For big diffs (over about 800 lines), split by area and spawn one reviewer per area in parallel. The attention budget does not apply here, because reviewers cost tokens, not human minutes.

## What comes back

A verdict (`ship` / `fix-first` / `rethink`) and findings, each with a `file:line`, a severity (`blocker` / `should` / `nit`), the evidence, and the INTENT item or Taste entry it relates to.

## Triage

- **blocker**: fix it through `loop`, then re-run the reviewer on the new diff only.
- **should**: fix it if cheap. Otherwise record it as `debt` and list it for the human.
- **nit**: fix it only if it's in the profile or repo Taste. Otherwise drop it.
- Disagree? Dismiss it with a concrete reason in DECISIONS.tsv. Don't churn code to appease a wrong finding.

Show the human only the verdict and the blockers and shoulds that remain. Nits never reach them.
