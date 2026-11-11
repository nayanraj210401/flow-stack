---
id: recall
title: Recall past conversations
owns: plugins/flow-stack/skills/recall/** .claude/skills/verify-flow-stack/scripts/recall.sh
entries: skill /flow-stack:recall | cli skills/recall/scripts/recall.sh sessions|grep|show | toolchain recall:
scenario: bash .claude/skills/verify-flow-stack/scripts/recall.sh
status: verified
verified: 2026-10-26 b6cdf74
---
# Recall past conversations

A new session can find what was said and decided in earlier conversations in this repo, without tool noise or secrets.

## Sub-features
- recall.sessions · lists conversations in the window: date, id, title, human prompt count, PRs
- recall.grep · matching lines, human prompts and Claude replies only (tool calls and output, skill text, thinking, agent hand-backs, notifications, sidechains dropped)
- recall.show · one conversation in order
- recall.scope · this repo and --days only; --repo and --skip widen or narrow it
- recall.redact · secrets are redacted

## How to get to it
- /flow-stack:recall, /flow resume, reflect

## Driving it
bash .claude/skills/verify-flow-stack/scripts/recall.sh

## Proof
All ✓ and `== recall · PASS`.

## Gotchas
- Older transcripts have no `origin`; a user line without one counts as human unless it's a tool result, meta, or a known harness wrapper.
