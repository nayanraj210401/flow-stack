---
name: board
description: "Publish the flow-stack board: a dashboard artifact built from real data across your repos (what needs you, open tasks, feature health, agent decisions, debt, shipped work, spend). Every run updates the same link. Use for /flow-stack:board, \"dashboard\", \"show the board\", \"refresh the board\"."
---

# board: one page for everything flow-stack knows

The board is an Artifact: one private link that each run republishes with fresh data. Paths are relative to this skill's base directory.

## 1. Collect

```bash
mkdir -p .flow/board && scripts/collect.sh > .flow/board/board.json
```

It reads the profile's `# Repos` plus the current repo: `.flow/tasks/*`, `.flow/features/`, `.flow/debt.md`, and each task's DECISIONS.tsv, plus git, `gh pr status`, and ccusage. Each repo also gets a quality score (0–100): features verified, checks passing, checks with teeth, open debt, the review stamp on HEAD, test files per source file, oversized files, and TODO markers. A row with no data is null (n/a), never 0, and the overall is the mean of the rest. It runs no repo commands. Add `--no-cost` when ccusage is missing or slow, and `--no-prs` when gh isn't authed. Say which one you skipped.

## 2. Render

```bash
scripts/render.sh .flow/board/board.json .flow/board/board.html
```

It fills `templates/board.html` with the JSON, and the page draws every panel from that data. To change the look, edit the template. To change the data, edit `collect.sh`. Never hand-edit the rendered file, and never add data that `collect.sh` didn't produce: the board shows real data only, and an empty panel says so. The template already meets the artifact page contract (tokens for both themes, a phone-width layout, no external scripts), so a run doesn't need a design pass.

## 3. Publish as the Artifact

There is one board per person. Every run updates it, and a run creates a new one only when none exists anywhere. Find it in this order, and stop at the first hit:

1. **Saved link:** `${FLOW_STACK_HOME:-~/.flow-stack}/board/url`.
2. **Your artifacts:** Artifact `list` (scope `mine`), then take the newest one titled exactly **Flow Board**. That title comes from `templates/board.html`; keep it stable. This recovers the board on a new machine or after `~/.flow-stack` was reset.
3. **None found:** only now publish `.flow/board/board.html` as a new artifact (icon `chart`, description "flow-stack board: what needs you, tasks, features, decisions, debt, and spend across your repos.").

To update a found board: if this conversation hasn't read or published it yet, `read` it first, since the tool refuses otherwise. If the read fails because it was deleted or isn't yours, drop to the next step. Then publish `.flow/board/board.html` with `url` set to it and a `label` like "refresh <date>". Never publish without `url` when steps 1 or 2 found a board.

After any successful publish, write the URL back to the saved-link file, so the next run hits step 1.

If there is no Artifact tool in this environment, say so in one line and stop. The board is an artifact by design; don't hand over the local file as a substitute.

`.flow/board/` is only the staging area for the publish, and it's gitignored with the rest of `.flow/`.

## 4. Reply (≤ 5 lines)

The link, the needs-you count with the top three items, each repo's quality score with its lowest row, and anything not collected (cost, PRs). The artifact is private. It shows repo names, PR titles, commit subjects, and debt text, so mention that before the human shares it.
