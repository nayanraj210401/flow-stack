---
id: slice.fence
title: Keep edits inside the slice fence
owns: plugins/flow-stack/hooks/edit-guard.sh .claude/skills/verify-flow-stack/scripts/slice.fence.sh
entries: hook PreToolUse Edit|Write|MultiEdit|NotebookEdit | file .flow/tasks/<slug>/SLICES.md fence: | config hooks.fence
scenario: bash .claude/skills/verify-flow-stack/scripts/slice.fence.sh
status: verified
verified: 2026-10-29 90da7be
---
# Keep edits inside the slice fence

While a slice is `doing`, the agent can only edit files inside that slice's fence globs; widening it is a deliberate, logged act.

## Sub-features
- slice.fence.deny · Edit/Write outside the doing slice's fence is denied, naming the slice and fence
- slice.fence.allow · paths inside the fence (including `**` globs), .flow/ bookkeeping, and paths outside the repo are allowed
- slice.fence.idle · no `doing` slice or no active task → no fence
- slice.fence.toggle · `hooks.fence: false` disables it

## How to get to it
- Automatic on every Edit/Write while a task is active and a slice in SLICES.md has `status: doing` and a `fence:` line.

## Driving it
`.claude/skills/verify-flow-stack/scripts/slice.fence.sh` runs in a throwaway toy repo with a sandboxed FLOW_STACK_HOME, drives every entry point above, and prints one ✓/✗ per sub-feature.

## Proof
- `deny` for `src/other.sh` with reason "outside slice S1's fence"
- absence: no decision for `src/calc.sh`, `tests/deep/test_x.sh`, `.flow/…`

## Gotchas
- Glob `*` crosses directories (lib.sh glob_match), so `src/*` also allows `src/a/b.sh`.
