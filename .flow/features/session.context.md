---
id: session.context
title: Session primer, anchor, and handoff
owns: plugins/flow-stack/hooks/session-start.sh plugins/flow-stack/hooks/anchor.sh plugins/flow-stack/hooks/pre-compact.sh .claude/skills/verify-flow-stack/scripts/session.context.sh
entries: hook SessionStart | hook UserPromptSubmit | hook PreCompact | config hooks.session-start|anchor|handoff
scenario: bash .claude/skills/verify-flow-stack/scripts/session.context.sh
status: verified
verified: 2026-10-29 90da7be
---
# Session primer, anchor, and handoff

Each session starts with the working rules, the user's profile, this repo's entry, and the active task; every prompt re-anchors the goal; compaction leaves a resumable snapshot.

## Sub-features
- session.context.primer · SessionStart prints the flow-stack rules; suggests setup when no profile exists
- session.context.profile · injects Who/Rules/Taste/Toolchain and only the Repos entry whose path contains the cwd
- session.context.pointers · mentions .flow/map.md and the feature count when present
- session.context.router · a Toolchain `router:` line replaces the flow routing rule
- session.context.task · shows the active task goal and current slice
- session.context.anchor · UserPromptSubmit prints goal, first non-goal, current slice
- session.context.snapshot · PreCompact writes HANDOFF.auto.md; SessionStart on compact/resume re-injects the newer handoff
- session.context.toggle · `session-start`/`anchor` false silence them

## How to get to it
- Automatic: Claude Code runs these on session start, each prompt, and before compaction.

## Driving it
`.claude/skills/verify-flow-stack/scripts/session.context.sh` runs in a throwaway toy repo with a sandboxed FLOW_STACK_HOME, drives every entry point above, and prints one ✓/✗ per sub-feature.

## Proof
- output contains `## Active task: demo`, `Goal: …`, `[flow anchor · demo] goal: …`, `### Handoff (HANDOFF.auto.md)` on compact
- absence: no handoff on plain startup; no output when toggled off

## Gotchas
- Reads `$FLOW_STACK_HOME/profile.md` (default ~/.flow-stack); the driver points it at a sandbox.
