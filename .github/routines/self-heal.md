---
cron: "0 4 * * *"
timeout: 120
labels: self-heal needs-repro
---
# self-heal: fix open issues as proven draft PRs

You run in GitHub Actions. The human is away and reviews draft PRs once a day, so open only PRs worth their time.

1. List candidates: `gh issue list --state open --limit 30 --json number,title,labels,comments`. Skip an issue that already has an open PR (`gh pr list --state open --search "<number>"`), one labelled `wontfix` or `needs-repro`, and one where a self-heal comment already declined it.
2. Take at most 3, oldest first. For each, start from the default branch on a new branch `self-heal/<number>-<slug>`, and open a flow task for it.
3. Reproduce first. If you can't, comment what you ran, add the label `needs-repro`, and move on.
4. If the fix isn't worth it, or goes against this repo's principles (CLAUDE.md, `.flow/taste.md`, README), comment why and move on.
5. Fix it through flow: a check that fails before the fix, the fix, verify, review. `review/scripts/ready.sh` must stamp HEAD; the hooks refuse the push until it does.
6. Push the branch by name and open a draft PR: `gh pr create --draft --label self-heal --title "<fix>" --body-file <file>`. The body holds `Fixes #<number>`, the repro, and the evidence.
7. Never merge, never push to the default branch, never commit `.flow/tasks/`.

End with a summary table: issue, then the PR link, the comment, or why it was skipped.
