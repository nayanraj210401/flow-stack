---
id: seal
title: Seal acceptance checks
owns: plugins/flow-stack/skills/seal/** plugins/flow-stack/hooks/edit-guard.sh .claude/skills/verify-flow-stack/scripts/seal.sh
entries: cli seal.sh add|verify|list|reseal|rm | skill /flow-stack:seal | hook PreToolUse Edit|Write | hook PreToolUse Bash
scenario: bash .claude/skills/verify-flow-stack/scripts/seal.sh
status: verified
verified: 2026-10-29 90da7be
---
# Seal acceptance checks

Once the human approves the acceptance checks, they are sealed: the agent cannot weaken a check (or INTENT.md) to get a pass without the human saying yes.

## Sub-features
- seal.lock · `seal.sh add` hashes files; `verify` reports CHANGED/MISSING and exits 1
- seal.edit · Edit/Write to a sealed file or the task INTENT.md asks the human
- seal.shell · sed -i / redirect / tee / mv on a sealed file, SEALS, or INTENT.md, and `seal.sh reseal|rm`, ask the human
- seal.reseal · `reseal` re-hashes after an approved change; `rm` unseals one file
- seal.toggle · `hooks.seal: false` disables the edit guard

## How to get to it
- CLI: `plugins/flow-stack/skills/seal/scripts/seal.sh add <path>` (the intent skill runs it after approval)
- Skill: `/flow-stack:seal`
- Hooks: edit-guard.sh (Edit/Write), guard.sh (Bash)

## Driving it
`.claude/skills/verify-flow-stack/scripts/seal.sh` runs in a throwaway toy repo with a sandboxed FLOW_STACK_HOME, drives every entry point above, and prints one ✓/✗ per sub-feature.

## Proof
- `seals intact (1 files)`, then `CHANGED  tests/test_mul.sh` after tampering
- `ask` for Edit/sed on the sealed check; absence: Edit of `src/calc.sh` and `cat` of the check get no decision

## Gotchas
- Needs an active task (`.flow/ACTIVE`); with none, seal.sh exits 2.
