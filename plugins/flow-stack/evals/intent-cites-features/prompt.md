---
description: With a feature map present, intent binds acceptance checks to feature and sub-feature IDs.
max_turns: 14
allowed_tools: [Read, Glob, Grep, Edit, Write, Skill]
append_system_prompt: "The user is away. Where the intent skill would ask a question, choose the recommended answer and record it under Open questions as 'assumed: …'. Skip blind checks and say so. Do not spawn subagents."
---

Use flow-stack's intent skill for the active task `validate`: "add() should reject non-integer arguments: print an error to stderr and exit 2". Write INTENT.md; don't implement.
