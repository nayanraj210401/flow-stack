---
id: budget.handoff
title: Handoff at an absolute context size
owns: plugins/flow-stack/hooks/handoff-nudge.sh plugins/flow-stack/hooks/hooks.json plugins/flow-stack/skills/budget/SKILL.md plugins/flow-stack/templates/profile.md .claude/skills/verify-flow-stack/scripts/handoff.nudge.sh
entries: hook UserPromptSubmit | profile budget: handoff_at_tokens:|handoff_at_context_pct: | skill /flow-stack:budget
scenario: bash .claude/skills/verify-flow-stack/scripts/handoff.nudge.sh
status: unverified
verified:
---
# Handoff at an absolute context size

The handoff threshold used to be a percentage of the window, which never fires on large-window models. Now `budget:handoff_at_tokens` (default 150K) is an absolute backstop: a hook reads the latest request's context from the transcript and, once it crosses the threshold, injects one line to finish the slice and run `handoff` — once per crossing, so it doesn't nag.

## Sub-features
- budget.handoff.nudge · latest context ≥ `handoff_at_tokens` → one `additionalContext` nudge naming handoff
- budget.handoff.once · staying over the threshold does not repeat; dropping back below re-arms it
- budget.handoff.config · the `budget:` key overrides the 150K default

## How to get to it
- Automatic: UserPromptSubmit. `hooks.handoff: false` in config.json turns it off.

## Driving it
`.claude/skills/verify-flow-stack/scripts/handoff.nudge.sh` builds transcripts with a known last usage and asserts one nudge over the threshold, none below it, and a second nudge only on a fresh crossing.

## Proof
- output contains `hookSpecificOutput.additionalContext` with "handoff", and nothing on the repeat call.

## Gotchas
- Sidechain (sub-agent), `<synthetic>` and zero-usage assistant lines are skipped: they would hide a real crossing or re-arm the flag.
- A non-numeric `handoff_at_tokens` (e.g. `150k`) falls back to 150000.
