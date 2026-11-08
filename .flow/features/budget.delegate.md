---
id: budget.delegate
title: Delegate once a session is long
owns: plugins/flow-stack/hooks/delegate-nudge.sh plugins/flow-stack/hooks/hooks.json .claude/skills/verify-flow-stack/scripts/delegate.nudge.sh
entries: hook PostToolUse Read|Grep|Glob | profile budget: delegate_after_turns:|delegate_after_tokens: | config hooks.delegate
scenario: bash .claude/skills/verify-flow-stack/scripts/delegate.nudge.sh
status: unverified
verified:
---
# Delegate once a session is long

Once the main thread is long (human turn ≥ `budget:delegate_after_turns`, default 7, or context ≥ `budget:delegate_after_tokens`, default 120K, whichever first), a PostToolUse hook injects a one-line nudge to hand bulk reading off to a subagent. It fires at most once every few turns, only on the 4th-or-later read in a row, and never for a subagent's own reads. Fresh and short sessions stay quiet.

## Sub-features
- budget.delegate.trigger · the nudge needs turn ≥ delegate_after_turns or context ≥ delegate_after_tokens
- budget.delegate.bulk · it fires only on a run of Read/Grep/Glob (4th in a row), not on a single look-up
- budget.delegate.once · at most one nudge every few turns; a subagent's reads never nudge the main thread

## How to get to it
- Automatic: PostToolUse on Read/Grep/Glob. `hooks.delegate: false` in config.json turns it off; the `budget:` keys set the trigger.

## Driving it
`.claude/skills/verify-flow-stack/scripts/delegate.nudge.sh` builds a throwaway transcript and asserts the nudge appears at turn 8 + 4 reads, is absent at turn 3, and isn't repeated.

## Proof
- output contains `hookSpecificOutput.additionalContext` naming `flow-agent`, and nothing at turn 3 or for a subagent.

## Gotchas
- The turn count is over the whole transcript (monotonic), while the read run and context come from the last 3000 lines. Prompts with origin.kind human/person or turnOrigin sdk count; tool_result lines do not.
- Bash is not matched: a Bash call would reset the read run and never nudge.
- Slash-command, meta, compact-summary, task-notification and interrupted lines are not human turns (same filter as the board's attention.sh).
