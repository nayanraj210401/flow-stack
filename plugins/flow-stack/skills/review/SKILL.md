---
name: review
description: Fresh-context reviewer grades the diff against INTENT, evidence, and your taste; flags code that could be smaller. Findings are verified by vote, depth scales with risk, and fix rounds are capped. Use for /review, "second opinion", before a merge gate.
---

# review: a second pair of eyes with no stake in the code

The builder can't see its own blind spots. The reviewer starts from zero context, so it only knows what the artifacts say. The goal is the fewest rounds that still catch the real bugs: a nit costs a commit and another round, so noise is not free.

## Depth: the change sets it, not the author

| Depth | When | Reviewers | Vote |
|---|---|---|---|
| Quick | rigor `lean` and no deep path touched | one | no |
| Standard | default | one | yes |
| Deep | rigor `strict`, diff > 800 lines, or a `deep:` path from `.flow/review.md` | one per lens, in parallel: correctness, blast radius, tests and gaming, security (when the diff touches hooks, auth, or shell-out code) | yes |

Reviewers cost tokens, not human minutes, so the attention budget does not apply here. Say the depth in the route line.

`.flow/review.md` is optional, written by the repo owner, and read by the reviewer:

```
# Review
fails-when: a hook silently allows what it should block · a script exits 0 on error
skip: docs/** · evals/results/**
deep: plugins/*/hooks/guard*.sh · plugins/*/skills/review/scripts/ready.sh
```

## Run

Spawn the `reviewer` agent (flow-stack:reviewer, `design_model`) with:
- the path of the task folder,
- the diff range (`git diff <base>...HEAD` plus uncommitted changes),
- the lens, at Deep,
- nothing else. Don't summarize your work for it; the point is that it forms its own view.

**A model that didn't write it.** A reviewer on the author's model shares the author's blind spots. When `design_model` is your own model, the two verify-mode reviewers in the vote run on `build_model` and `subagent_model`, and at Deep the correctness lens runs on `build_model`.

**Vote** (Standard and Deep). For each blocker and should, spawn two reviewers in verify mode (`subagent_model`, or the two models above; in parallel, all findings at once). Each gets the task folder and that one finding line, nothing else.
- both `real`: keep it.
- split: keep it, marked `contested`, and read the code yourself before acting.
- neither `real`: drop it, logged as `wrong` or `intentional` (below).

**Re-review.** After fixes, check `scripts/ready.sh rounds`. Below 3, spawn the reviewer in re-review mode with the previous findings and the last-reviewed commit, so it reviews only what changed and doesn't repeat itself. At round 3 without ship, stop: run `challenge` on the approach before another fix round. Repeated findings on a third pass mean the shape is wrong, not the lines.

## What comes back

A count line, a verdict (`ship` / `fix-first` / `rethink`), and findings with an id, `file:line` (every instance of the class), a severity (`blocker` / `should` / `nit`), the evidence, and the INTENT item or Taste entry it relates to. `pre-existing` findings are bugs the diff didn't introduce.

## Triage

- **blocker**: fix every listed instance through `loop`, then re-review.
- **should**: fix it if cheap. Otherwise record it as `debt` and list it for the human.
- **nit**: fix it only if it's in the profile or repo Taste. Otherwise drop it.
- **pre-existing**: never blocks this diff. Record it as `debt` (or an issue, at the merge gate).
- Disagree? Dismiss it with a concrete reason. Don't churn code to appease a wrong finding.

**Every blocker and should gets a fate**, logged once it's settled:

```bash
../flow/scripts/task.sh decide reviewer yes "finding <fixed|wrong|intentional|didnt-matter|pre-existing> · <class> · <path:line>" "<why>" "<evidence>"
```

`reflect` reads these rows: a class that keeps coming back `wrong` or `intentional` is noise to tune out of the reviewer or `.flow/review.md`.

Show the human only the verdict and the blockers and shoulds that remain. Nits never reach them.

Record the verdict for the ready-for-review bar, once the blockers are fixed and the last review ran on the current HEAD: `scripts/ready.sh record review ship|fix-first|rethink "<n blockers, n shoulds>"`. Each record prints the round (reviewed commits on this branch) and the re-review range; round 3 without ship says to run `challenge`.

## Ready for review

A PR goes to a human only after `scripts/ready.sh` passes for its exact HEAD, unless `review_gate: yolo` is set (repo `.flow/config.json` beats the profile). It runs the live checks (clean tree, lint, typecheck, the repo's own `ready` gates from `.flow/config.json`, impacted feature scenarios, and with a task: acceptance checks, seals, blind checks), then requires each `ready` gate's `do` step recorded (`scripts/ready.sh record <id> done`, only after you ran it), and `review ship`, `deslop`, and `tour` recorded for HEAD. On a pass it stamps HEAD. The guard hook denies a non-draft `gh pr create` and `gh pr ready` without that stamp, and any new commit needs a new stamp. Drafts are always fine. If it fails, fix what it lists; never record a step you didn't do.
