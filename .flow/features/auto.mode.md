---
id: auto.mode
title: Auto mode (--auto): the human is away
owns: plugins/flow-stack/hooks/anchor.sh plugins/flow-stack/hooks/lib.sh plugins/flow-stack/hooks/guard.sh .claude/skills/verify-flow-stack/scripts/auto.mode.sh
entries: prompt --auto / --no-auto anywhere | hook UserPromptSubmit | hook PreToolUse Bash|AskUserQuestion | file ~/.flow-stack/auto/<session_id>
scenario: bash .claude/skills/verify-flow-stack/scripts/auto.mode.sh
status: verified
verified: 2026-10-29 90da7be
---
# Auto mode (--auto): the human is away

Typing `--auto` anywhere in a prompt tells the session nobody will answer. The agent decides reversible gates itself and queues irreversible ones in GATES.md; the hooks make sure it can't block on a question or perform an outward-facing action.

## Sub-features
- auto.mode.toggle · `--auto` (followed by space, punctuation, or end) sets the session flag; `--no-auto` clears it; quoted or glued forms don't trigger
- auto.mode.anchor · while on, every prompt gets the `[flow auto]` instructions
- auto.mode.queue · every `ask` (repo gates, built-in escalations, seals) becomes a deny that says to queue in GATES.md
- auto.mode.noask · AskUserQuestion is denied
- auto.mode.outward · git push, gh pr create/merge/ready, gh release create, npm publish are queued even when nothing else gates them
- auto.mode.session · other sessions are unaffected

## How to get to it
- Put `--auto` in any prompt; `--no-auto` when back.

## Driving it
bash .claude/skills/verify-flow-stack/scripts/auto.mode.sh

## Proof
All ✓ and `== auto.mode · PASS`; decisions.tsv holds each hook verdict.

## Gotchas
- The flag is keyed by session_id; subagents share it. Stale flags older than 7 days are pruned on each toggle.
