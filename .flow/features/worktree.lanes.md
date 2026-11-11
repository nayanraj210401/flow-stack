---
id: worktree.lanes
title: Guards and state in delegate worktrees
owns: plugins/flow-stack/hooks/roots.sh plugins/flow-stack/agents/worker.md plugins/flow-stack/skills/delegate/SKILL.md .claude/skills/verify-flow-stack/scripts/worktree.lanes.sh
entries: hook PreToolUse Edit|Read from a linked worktree | cli task.sh accept <lane> | cli evidence.sh/probe.sh/seal.sh from a worktree
scenario: bash .claude/skills/verify-flow-stack/scripts/worktree.lanes.sh
status: verified
verified: 2026-10-26 b6cdf74
---
# Guards and state in delegate worktrees

A delegate worker runs in its own git worktree. It sees the main checkout's task, is held to the same seal and fence rules, and writes only to its own lane; the delegate imports that lane's evidence.

## Sub-features
- worktree.lanes.guards · sealed-check edit asks, out-of-fence edit denies, plan-file edits ask, blind reads deny, all from a worktree
- worktree.lanes.writes · evidence, trail, and circuit state land in lanes/<branch>/, never the shared files
- worktree.lanes.readonly · slice, close, seal add/reseal/rm are refused in a lane
- worktree.lanes.accept · task.sh accept <lane> imports lane evidence in the main checkout

## How to get to it
- /flow-stack:delegate spawns flow-stack:worker with isolation: worktree.

## Driving it
bash .claude/skills/verify-flow-stack/scripts/worktree.lanes.sh

## Proof
20 ✓ lines and `== worktree.lanes · PASS`; decisions.tsv holds every hook verdict.

## Gotchas
Lane names are the worktree's branch with / replaced by _.
