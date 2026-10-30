---
id: trail.circuit
title: Audit trail and circuit breaker
owns: plugins/flow-stack/hooks/post-tool.sh plugins/flow-stack/skills/trace/** .claude/skills/verify-flow-stack/scripts/trail.circuit.sh
entries: hook PostToolUse | cli trace-stats.sh | skill /flow-stack:trace | config hooks.trail|circuit
scenario: bash .claude/skills/verify-flow-stack/scripts/trail.circuit.sh
status: verified
verified: 2026-10-29 2d69405
---
# Audit trail and circuit breaker

Every tool call leaves a redacted row in the trail, and the agent is stopped when it keeps hitting the same failure or churning one file.

## Sub-features
- trail.circuit.trail · one JSON row per tool call (ts, sid, tool, target) in the task trail, or .flow/trail.jsonl with no task
- trail.circuit.redact · bearer tokens and API keys are redacted in the row
- trail.circuit.repeat · the 3rd identical `flow-evidence: FAIL sig=` blocks with attack-the-premise guidance; a PASS resets
- trail.circuit.churn · the 6th edit of one file since the last PASS blocks; .flow/ edits don't count
- trail.circuit.stats · trace-stats.sh summarises span, tools, edited files, evidence, decisions

## How to get to it
- Automatic after every tool call.
- CLI: `plugins/flow-stack/skills/trace/scripts/trace-stats.sh [slug]`; skill `/flow-stack:trace`

## Driving it
`.claude/skills/verify-flow-stack/scripts/trail.circuit.sh` runs in a throwaway toy repo with a sandboxed FLOW_STACK_HOME, drives every entry point above, and prints one ✓/✗ per sub-feature.

## Proof
- `decision: block` on the 3rd failure and 6th edit
- absence: the raw token/key strings are not in the trail; nothing is written when the repo has no .flow/

## Gotchas
None known.
