---
id: probe.teeth
title: Test the test (probe)
owns: plugins/flow-stack/skills/probe/** .claude/skills/verify-flow-stack/scripts/probe.teeth.sh
entries: cli probe.sh <label> "<check>" [--keep path] | skill /flow-stack:probe
scenario: bash .claude/skills/verify-flow-stack/scripts/probe.teeth.sh
status: verified
verified: 2026-10-26 b6cdf74
---
# Test the test (probe)

After a check passes, the probe reverts the source change and reruns it. If it still passes, the check proves nothing.

## Sub-features
- probe.teeth.teeth · check fails on reverted source → `flow-probe: TEETH`, exit 0
- probe.teeth.toothless · check still passes → `flow-probe: TOOTHLESS`, exit 1, recorded in EVIDENCE.md
- probe.teeth.restore · every reverted file (modified and untracked) is restored byte-for-byte; test paths, sealed files, and --keep paths are never reverted
- probe.teeth.skip · a clean tree prints `flow-probe: SKIPPED`

## How to get to it
- CLI: `plugins/flow-stack/skills/probe/scripts/probe.sh S1 "bash tests/test_mul.sh"`
- Skill: `/flow-stack:probe`; loop runs it per slice

## Driving it
`.claude/skills/verify-flow-stack/scripts/probe.teeth.sh` runs in a throwaway toy repo with a sandboxed FLOW_STACK_HOME, drives every entry point above, and prints one ✓/✗ per sub-feature.

## Proof
- TEETH for mul + its test; TOOTHLESS for a comment-only change
- absence: no diff in shasums of the touched files after the probe

## Gotchas
- Reverts to HEAD; committed changes are not probed.
