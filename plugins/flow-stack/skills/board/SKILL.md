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

**Sessions and attention.** Each task lists the Claude sessions that worked on it: every distinct session id in its `trail.jsonl`, with the transcript's title, tool calls, and the minutes of you it cost. `scripts/attention.sh` reads your transcripts from the last 14 days (all repos on this machine; timestamps and titles only, never prompt text) and `~/.flow-stack/waits.jsonl` (permission prompts, logged by the Notification hook). Every human event counts its wait, capped at 5 min, since a longer gap means you stepped away:

| Event | Wait |
|---|---|
| prompt | Claude's last output → your prompt |
| answer | the same, when Claude's turn ended on a question; counts as blocked on you |
| question | AskUserQuestion asked → answered; blocked on you |
| permission | permission prompt shown → resolved; blocked on you |

Per day the board shows minutes against `attention.review_minutes_per_day`, blocked-on-you minutes, switches (consecutive events in different sessions ≤ 10 min apart), and peak (most sessions with an event in one 30 min window). Today's warnings: over budget (🔴), over 80% of it, peak ≥ 3, or ≥ 15 switches (🟡; two or more make all 🔴). They also land in Needs you. `--no-attention` skips the transcript read.

**Factory.** Opt-in: a profile with `factory:` then `  project: <owner>/<n>` names the GitHub Project that is the factory's live board (columns Triage, Ready, Building, Rework, Review, Merged, Blocked). `collect.sh` then adds `board.factory` from `scripts/factory.sh json`: the cards by column, median issue → PR and PR → merge hours, PRs sent to `rework`, escaped bugs (a `bug` or `type:bug` issue naming a merged PR on the board), and risk misses (a PR's `risk:` label above its issue's). Blocked cards go to Needs you. With no `factory:` there is no `factory` key and the board is unchanged. Reading a user-owned Project needs a token with the `project` scope.

`scripts/factory.sh dry-run` prints the card moves the issue and PR states imply; `apply` makes them. Merged PR or any closed issue or PR → Merged (the done column); `needs-human` → Blocked; open PR with `rework` → Rework, non-draft or a passing `flow/ready` check run (posted once the factory PR loop, #184, lands) → Review, else Building; a card with no column → Triage. Ready is the intake gate: a human dragging a card from Triage to Ready approves it to be built. Nothing reads Ready yet: today self-heal picks issues by label; the shift's `start` and self-heal are planned to read it, and Project write access is a different trust boundary from that label rule, and the sync never moves a card into Ready. An open issue a human put in a column stays there. Re-running moves nothing.

## 2. Render

```bash
scripts/render.sh .flow/board/board.json .flow/board/board.html
```

It fills `templates/board.html` with the JSON, and the page draws every panel from that data. To change the look, edit the template. To change the data, edit `collect.sh`. Never hand-edit the rendered file, and never add data that `collect.sh` didn't produce: the board shows real data only, and an empty panel says so. The template already meets the artifact page contract (tokens for both themes, a phone-width layout, no external scripts), so a run doesn't need a design pass.

## Customize: the profile's `# Board` section

Personal board preferences live in `${FLOW_STACK_HOME:-~/.flow-stack}/profile.md` under `# Board`, one `- key: value` line each. `collect.sh` reads them into `board.json.prefs` and the template applies them, so every lead's run renders the same board. When the human asks for a change ("hide spend", "open on All repos", "add a panel of stale tasks"), edit these lines, show the diff, then run 1–3. A profile without the section (anyone set up before it existed) renders the default board; on the first ask, append `# Board` at the end of the profile with just the asked lines. Never put a personal ask into `templates/board.html`; that file is everyone's.

| Key | Value |
|---|---|
| `theme` | `auto` · `light` · `dark` |
| `tab` | `current` · `all` · a repo name |
| `hide`, `order`, `wide` | panel ids, comma-separated. `order` puts the listed panels first; `wide` makes them full width |
| `accent` | `#rrggbb` |
| `view` | `<title> · <jq over board.json> · table\|list\|count`, repeatable: a custom panel built from data the board already has |

Panel ids are stable; renaming one breaks people's profiles: `needs spend attention tasks features quality decisions debt shipped estimate repos factory`. Views run with an empty environment, return at most 50 rows, and may not `import` or `include`. A view that needs data `collect.sh` doesn't gather is a `collect.sh` change, not a pref. Unknown keys, unknown panel ids, and bad values are skipped and listed in a footer on the board.

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

The link, the needs-you count with the top three items, today's attention minutes vs budget and any attention warning, each repo's quality score with its lowest row, any `# Board` warnings (or, when the profile has no `# Board` section, one line: "customize: ask, e.g. 'hide spend' or 'open on All repos'"), and anything not collected (cost, PRs). The artifact is private. It shows repo names, PR titles, commit subjects, and debt text, so mention that before the human shares it.
