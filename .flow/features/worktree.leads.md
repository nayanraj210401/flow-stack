---
id: worktree.leads
title: Parallel leads in linked worktrees
owns: plugins/flow-stack/hooks/roots.sh plugins/flow-stack/skills/flow/scripts/task.sh plugins/flow-stack/skills/board/scripts/collect.sh .claude/skills/verify-flow-stack/scripts/worktree.leads.sh
entries: cli task.sh new|switch|close from a linked worktree | hook any, in a worktree with a flow-active pointer | cli skills/board/scripts/collect.sh
scenario: bash .claude/skills/verify-flow-stack/scripts/worktree.leads.sh
status: verified
verified: 2026-10-29 2d69405
---
# Parallel leads in linked worktrees

A linked worktree whose git dir holds `flow-active` leads its own task. Its fence, seals, anchor, evidence, and status follow that task; main and other worktrees keep theirs. A worktree with no pointer is still a lane of main's task.

## Sub-features
- worktree.leads.resolve · hooks and scripts in a pointed worktree resolve its task; `.flow/` stays the main checkout's
- worktree.leads.isolation · fence, seal, anchor, and Stop check see only the worktree's own task; the pointer survives a branch switch
- worktree.leads.owner · one owner per task: `new`/`switch` refuse a slug main or another worktree holds; `close` removes only its own pointer
- worktree.leads.board · the board marks every task active anywhere (main's ACTIVE plus each worktree's flow-active) with `owner` = the checkout

## How to get to it
- Run `task.sh new <slug>` (or `/flow`) inside a linked worktree.

## Driving it
bash .claude/skills/verify-flow-stack/scripts/worktree.leads.sh
bash .claude/skills/verify-flow-stack/scripts/board.publish.sh   # the board part

## Proof
`== worktree.leads · PASS`; board.publish shows "main's task and a worktree lead's task are both active".

## Gotchas
Verify artifacts land in the main checkout's `.flow/artifacts`, not the worktree's.
