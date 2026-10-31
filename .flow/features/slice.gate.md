---
id: slice.gate
title: Proof-gated slice completion
owns: plugins/flow-stack/skills/flow/scripts/task.sh plugins/flow-stack/skills/loop/scripts/diffstat.sh .claude/skills/verify-flow-stack/scripts/slice.gate.sh
entries: cli task.sh slice <id> done | cli task.sh proofs <id> | cli diffstat.sh | hook PreToolUse Bash|Edit on SLICES.md
scenario: bash .claude/skills/verify-flow-stack/scripts/slice.gate.sh
status: verified
verified: 2026-10-26 b6cdf74
---
# Proof-gated slice completion

A slice can only be marked done when its check failed first, passes after the last edit, has teeth, and fits its line budget. Overrides are logged.

## Sub-features
- slice.gate.proofs · `task.sh proofs <id>` lists ✓/✗ for red first, green, teeth, budget
- slice.gate.refuse · `slice <id> done` exits non-zero and leaves status unchanged while any proof is missing
- slice.gate.stale · a PASS older than the last Edit in the trail no longer counts
- slice.gate.force · `--force "<reason>"` marks done and logs the reason in DECISIONS.tsv; no reason is refused
- slice.gate.nohand · sed on SLICES.md or an Edit that adds `status: done` is denied; other SLICES.md edits are allowed
- slice.gate.budget · diffstat.sh counts changed lines within the fence against `budget:`

## How to get to it
- CLI: `plugins/flow-stack/skills/flow/scripts/task.sh slice S1 done` (the loop skill calls it)
- Hooks: guard.sh and edit-guard.sh block the hand-edit route

## Driving it
`.claude/skills/verify-flow-stack/scripts/slice.gate.sh` runs in a throwaway toy repo with a sandboxed FLOW_STACK_HOME, drives every entry point above, and prints one ✓/✗ per sub-feature.

## Proof
- refused with `✗ red first` before proofs; accepted after `S1:before` FAIL + `S1` PASS + `probe:S1` TEETH; SLICES.md then shows `status: done`
- absence: status stays `doing` after every refusal

## Gotchas
- Timestamps are second-resolution strings; a PASS in the same second as an edit counts as fresh.
