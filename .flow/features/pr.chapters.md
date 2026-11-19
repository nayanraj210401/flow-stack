---
id: pr.chapters
title: Tell a PR's story as chapters
owns: plugins/flow-stack/skills/pr-chapters/**
entries: skill /flow-stack:pr-chapters | cli skills/pr-chapters/scripts/collect.sh | cli skills/pr-chapters/scripts/render.sh | cli skills/settings/scripts/settings.sh chapters format
scenario: bash plugins/flow-stack/skills/pr-chapters/scripts/chapters.test.sh
status: unverified
verified:
---
# Tell a PR's story as chapters

The user runs /flow-stack:pr-chapters on a PR, a GitHub issue, or several PRs and gets one private artifact page a reviewer reads before the diff: core-first chapters with their hunks and a read/skim/skip tier, every why linked to where it is written, and a list of questions for the author.

## Sub-features
- pr.chapters.collect · collect.sh turns a PR (12, #12, owner/repo#12, URL), an issue (its closing PRs), or a PR list into one JSON: PRs in time order, commits, files with hunks, reviews, inline comments, closed issues, the flow task named by TICKET or --task
- pr.chapters.check · render.sh refuses an uncited why with no question, an uncovered file, a hunk/file/commit/review/issue/task the story didn't collect, and a quote that isn't in its source
- pr.chapters.render · the page in scroll, slides (claim slide per chapter, a slide per hunk, progress bar, question checklist), or rounds (each review's verdict, findings with sourced status, the commits after it; merge commits hidden); values escaped
- pr.chapters.rounds · render.sh refuses a finding not quoted from its review, and a status other than unknown without a later commit, review or comment quoting it
- pr.chapters.format · settings.sh chapters format scroll|slides|rounds; collect --format overrides
- pr.chapters.artifact · the skill publishes one artifact per story, its link kept in ~/.flow-stack/chapters/urls.tsv (model-only; not driven)

## How to get to it
- /flow-stack:pr-chapters <pr> | <issue> | <pr> <pr> …

## Driving it
bash plugins/flow-stack/skills/pr-chapters/scripts/chapters.test.sh (stub gh, toy repo with a flow task)

## Proof
"chapters (all): N passed".

## Gotchas
Not driven: live gh (run collect.sh on a real PR), the chapter writing itself (the model), and the Artifact publish.
