---
name: recall
description: "Rebuild working context from past Claude Code conversations in this repo plus flow's own records, then hand back a short current-state brief. Use for /recall, \"recall my work on X\", \"what did we decide about X\", \"where did I leave off\", before resuming work, and before saying something was never recorded."
---

# recall: what happened before this conversation

A new session starts blank. What you decided last week lives in two places: flow's records (written on purpose, trustworthy) and past conversations (complete, noisy). Read the first, then search the second.

If the profile's `# Toolchain` has a `recall:` line (for example `- recall: pstack:recall`), invoke that provider and fold its brief into the output below.

## 1. Lock the scope

Say it back in one line: the topic (or "all activity"), the window (default the last 7 days), and the repo (default this one). Never read another repo's conversations unless asked.

## 2. flow's records first

- `../flow/scripts/task.sh list`, then for the tasks that match: HANDOFF.md, GATES.md, DECISIONS.tsv, TRACE.md.
- `.flow/debt.md` entries that mention the topic.
- `git log --since=<window> --oneline` and `gh pr list --state all --search <topic>` for what shipped.

## 3. Then past conversations

```bash
scripts/recall.sh sessions --days 7            # which conversations exist: date · id · title · prompts · PRs
scripts/recall.sh grep '<topic regex>' --days 30
scripts/recall.sh show <id>                    # one conversation, your prompts and Claude's replies only
```

The script keeps only your own prompts and Claude's replies. It drops tool output, skill text, agent hand-backs, and task notifications, and redacts secrets. Pass `--skip <current session id>` when you know it. Grep first, then `show` only the conversations that matched. With more than 5 matching conversations, hand them to `flow-agent` subagents on `budget.subagent_model`, one slice each, and take back only the brief fields below.

What counts as a decision: something **you** said (`you:` lines). A `claude:` line is a proposal until you agreed to it. Quote your words when the exact scope matters.

## 4. Check against live state

Every PR, branch, and task the search turned up gets checked with `git` and `gh` before it goes in the brief. A merged PR beats a conversation that said "will merge".

## Output (≤ 12 lines)

```
recall · <topic> · <window>
CAPSULE    ≤ 3 lines: what this work is and where it stands
THREADS    one line each: [merged #N] [open PR #N] [in flight <branch>] [queued in GATES.md] [planned]
DECIDED    your rulings, quoted, with the conversation id
OPEN       what's unresolved or failed before, so the next attempt starts there
NEXT       one concrete action
```

Cite conversations by their 8-character id. Nothing found is a finding: say where you looked.
