---
id: ready.gate
title: Ready-for-review gate
owns: plugins/flow-stack/skills/review/scripts/ready.sh .claude/skills/verify-flow-stack/scripts/ready.gate.sh
entries: hook PreToolUse Bash gh pr create|gh pr ready | cli skills/review/scripts/ready.sh | config review_gate (profile, .flow/config.json) | config .flow/config.json ready[]
scenario: bash .claude/skills/verify-flow-stack/scripts/ready.gate.sh
status: broken
verified: 2026-10-11 fd4429b
---
# Ready-for-review gate

Human review is the expensive step. A PR can be opened as ready (or marked ready) only after ready.sh stamps its exact HEAD, unless review_gate is yolo.

## Sub-features
- ready.gate.block · non-draft gh pr create and gh pr ready are denied without a stamp; drafts and --undo pass
- ready.gate.bar · the stamp needs clean tree, lint/typecheck, impacted scenarios, task acceptance checks, seals, blind checks, review=ship, deslop, tour
- ready.gate.custom · .flow/config.json ready[]: a `run` entry is a live check; a `do` entry (MCP scan, manual step) blocks until `ready.sh record <id> done` for HEAD; record refuses unknown and `run` ids
- ready.gate.stale · a new commit needs a new stamp
- ready.gate.mode · review_gate: yolo disables it; repo config overrides the profile

## How to get to it
- review skill → ready.sh; the guard hook on gh pr create/ready

## Driving it
bash .claude/skills/verify-flow-stack/scripts/ready.gate.sh

## Proof
All ✓ and `== ready.gate · PASS`; decisions.tsv holds each hook verdict.

## Gotchas
Only repos with a .flow/ directory are gated.
- Broken on purpose (tend 2026-10-27): the scenario asserts review rounds from `feat-stronger-reviewer` and the wrapped-draft guard from `self-healer/fix-159-pkg-literal-text`, neither merged yet. It turns green when both land.
