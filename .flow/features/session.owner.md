---
id: session.owner
title: A task belongs to the session that started it
owns: plugins/flow-stack/hooks/roots.sh plugins/flow-stack/hooks/host.sh plugins/flow-stack/hooks/holds.sh plugins/flow-stack/hooks/session-start.sh plugins/flow-stack/skills/flow/scripts/task.sh plugins/flow-stack/skills/flow/scripts/status.sh .claude/skills/verify-flow-stack/scripts/session.owner.sh
entries: cli task.sh new|switch [--take]|close|list | hook SessionStart session-start.sh | hook any, in a checkout whose task another live session owns | cli status.sh --full (tasks, foreign)
scenario: bash .claude/skills/verify-flow-stack/scripts/session.owner.sh
status: verified
verified: 2026-10-27 b6cdf74
---
# A task belongs to the session that started it

A task pointer's line 2 is the pid of the Claude session that made it active (found up the process tree in Claude Code's `~/.claude/sessions/<pid>.json`). While that session lives, other sessions in the checkout have no task there: no anchor, fence, Stop check, band, or host sidebar row.

## Sub-features
- session.owner.claim · `new`/`switch` record the calling session; a write (slice, decide, tdd, ...) claims a pointer with no live owner
- session.owner.foreign · another live session's task: no task here, session start says whose it is, `new`/`switch`/`close` refused with EnterWorktree advice
- session.owner.take · `switch <slug>` moves your own task into this checkout; `--take` takes a live owner's, or moves one with no live owner
- session.owner.live · live = process runs and its start time matches the registry row (a crashed session's recycled pid is not an owner)
- session.owner.list · `task.sh list` and the pane's TASKS name each task's owner, busy/idle, live
- session.owner.cleanup · session start removes the old `~/.flow-stack/leads/` and push records older than 3 days

## How to get to it
Open two Claude sessions in one checkout; start a task in one.

## Driving it
`bash .claude/skills/verify-flow-stack/scripts/session.owner.sh`

## Proof

## Gotchas
Outside Claude (no session pid) the human sees every task. Lanes (`flow-lane`) never have an owner: workers share their lead's task.
