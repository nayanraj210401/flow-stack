---
id: tdd.phase
title: Opt-in TDD lock (red edits tests, green edits code)
owns: plugins/flow-stack/skills/tdd/SKILL.md plugins/flow-stack/hooks/edit-guard.sh plugins/flow-stack/hooks/guard.sh plugins/flow-stack/hooks/lib.sh plugins/flow-stack/skills/flow/scripts/task.sh .claude/skills/verify-flow-stack/scripts/tdd.phase.sh
entries: cli task.sh tdd <id> red|green|off | hook PreToolUse Edit|Write | hook PreToolUse Bash
scenario: bash .claude/skills/verify-flow-stack/scripts/tdd.phase.sh
status: verified
verified: 2026-10-29 90da7be
---
# Opt-in TDD lock (red edits tests, green edits code)

## Sub-features
- tdd.phase.red · red denies non-test edits
- tdd.phase.green · green needs a new red FAIL, then locks tests against Edit, Write, and shell writes
- tdd.phase.escape · back to red, --force, and off are logged

## How to get to it
See the scenario.

## Driving it
`bash .claude/skills/verify-flow-stack/scripts/tdd.phase.sh`

## Proof

## Gotchas
