---
id: blind.checks
title: Held-out blind checks
owns: plugins/flow-stack/skills/verify/scripts/blind-run.sh plugins/flow-stack/hooks/read-guard.sh .claude/skills/verify-flow-stack/scripts/blind.checks.sh
entries: cli blind-run.sh | hook PreToolUse Read|Grep|Glob | hook PreToolUse Bash | agent flow-stack:checker
scenario: bash .claude/skills/verify-flow-stack/scripts/blind.checks.sh
status: verified
verified: 2026-10-26 b6cdf74
---
# Held-out blind checks

The checker agent writes tests the builder never sees; they run only through blind-run.sh, which reports pass/fail and the failing names.

## Sub-features
- blind.checks.run · installs each MANIFEST file, runs the `run:` command, removes the copies and restores pre-existing targets
- blind.checks.record · appends `· blind · PASS|FAIL` to EVIDENCE.md without assertion bodies
- blind.checks.hidden · Read, Grep, Glob, and shell `cat` on .flow/tasks/*/blind are denied; blind-run.sh itself is allowed

## How to get to it
- Agent: `flow-stack:checker` (spawned by intent) writes `.flow/tasks/<slug>/blind/` + MANIFEST
- CLI: `plugins/flow-stack/skills/verify/scripts/blind-run.sh`

## Driving it
`.claude/skills/verify-flow-stack/scripts/blind.checks.sh` runs in a throwaway toy repo with a sandboxed FLOW_STACK_HOME, drives every entry point above, and prints one ✓/✗ per sub-feature.

## Proof
- FAIL naming `mul-square` before mul exists, PASS after; tree has no `tests/blind_square.sh` afterwards
- absence: `mul 3 3` never appears in EVIDENCE.md

## Gotchas
- Failing-line names are cut at 100 chars; a check that prints its expected value in the FAIL line leaks it.
