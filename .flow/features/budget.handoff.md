---
id: budget.handoff
title: Handoff at an absolute context size
owns: plugins/flow-stack/hooks/handoff-nudge.sh plugins/flow-stack/hooks/hooks.json plugins/flow-stack/skills/budget/SKILL.md plugins/flow-stack/skills/handoff/SKILL.md plugins/flow-stack/templates/profile.md .claude/skills/verify-flow-stack/scripts/handoff.nudge.sh
entries: hook UserPromptSubmit | hook PostToolUse Bash (task.sh slice <id> done) | profile budget: handoff_at_tokens: | skill /flow-stack:budget
scenario: bash .claude/skills/verify-flow-stack/scripts/handoff.nudge.sh
status: unverified
verified:
---
# Handoff at an absolute context size

Every request re-sends the whole context, so a session's cost grows with its size. `budget:handoff_at_tokens` (default 100K) is the size past which a fresh session is cheaper. A hook reads the latest request's context from the transcript and injects one line: once per crossing when a prompt arrives, and at every successful `task.sh slice <id> done` while past it, since the slice boundary is the clean place to stop and an `--auto` run may never see a prompt. Under `--auto` the slice-done line says to write the handoff and end the turn.

## Sub-features
- budget.handoff.nudge · latest context ≥ `handoff_at_tokens` on a prompt → one `additionalContext` nudge naming handoff
- budget.handoff.once · on prompts, staying over the threshold does not repeat; dropping back below re-arms it
- budget.handoff.slice · a successful `task.sh slice <id> done` past the threshold nudges every time (PostToolUse); a refused slice gate, any other Bash call, or a context below the threshold stays quiet
- budget.handoff.auto · under `--auto` the slice-done nudge says to write the handoff and end the turn
- budget.handoff.subagent · a subagent's own calls (`agent_id` set) never nudge
- budget.handoff.config · the `budget:` key overrides the 100K default

## How to get to it
- Automatic: UserPromptSubmit, and PostToolUse on Bash. `hooks.handoff: false` in config.json turns both off.

## Driving it
`.claude/skills/verify-flow-stack/scripts/handoff.nudge.sh` builds transcripts with a known last usage and drives both events: one prompt nudge over the threshold, none below it, a second only on a fresh crossing; slice-done nudges every time past the threshold, with the `--auto` wording when the session's auto flag is set.

## Proof
- output contains `hookSpecificOutput.additionalContext` with "handoff" and the matching `hookEventName`, and nothing on the repeat prompt, on other Bash calls, or for a subagent.

## Gotchas
- Sidechain (sub-agent), `<synthetic>` and zero-usage assistant lines are skipped: they would hide a real crossing or re-arm the flag.
- A non-numeric `handoff_at_tokens` (e.g. `100k`) falls back to 100000.
- Usage is read from the latest real assistant request; unknown/missing usage stays quiet.
- PostToolUse runs on every Bash call, so the hook checks the command and the `→ done` line before loading lib.sh.
- `budget:handoff_at_context_pct` is gone: no code read it. Claude Code's own `autoCompactWindow` is the hard backstop.
