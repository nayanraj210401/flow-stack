---
id: evidence.record
title: Record evidence for a check
owns: plugins/flow-stack/skills/verify/scripts/evidence.sh .claude/skills/verify-flow-stack/scripts/evidence.record.sh
entries: cli evidence.sh <label> "<cmd>" [artifact ...] | skill /flow-stack:verify
scenario: bash .claude/skills/verify-flow-stack/scripts/evidence.record.sh
status: verified
verified: 2026-10-26 b6cdf74
---
# Record evidence for a check

Every check the agent runs to prove something is recorded, with command, commit, and output, so "done" can be audited later.

## Sub-features
- evidence.record.record · appends `### <ts> · <label> · PASS|FAIL · exit=<n>` with cmd, head/dirty, artifacts, and output tail to the active EVIDENCE.md
- evidence.record.verdict · ends with `flow-evidence: PASS` or `FAIL sig=<hash>` and passes the exit code through
- evidence.record.sig · the same failure shape (numbers and tmp paths aside) gives the same sig; a different failure gives another
- evidence.record.notask · with no active task it still runs and says it did not record

## How to get to it
- CLI: `plugins/flow-stack/skills/verify/scripts/evidence.sh C1 "bash tests/test_add.sh"`
- Skill: `/flow-stack:verify`; also called by `features.sh run`

## Driving it
`.claude/skills/verify-flow-stack/scripts/evidence.record.sh` runs in a throwaway toy repo with a sandboxed FLOW_STACK_HOME, drives every entry point above, and prints one ✓/✗ per sub-feature.

## Proof
- EVIDENCE.md row `· C1 · PASS · exit=0`; exit 3 passed through; equal sigs for two failures differing only in numbers/paths
- absence: nothing written when no task is active

## Gotchas
None known.
