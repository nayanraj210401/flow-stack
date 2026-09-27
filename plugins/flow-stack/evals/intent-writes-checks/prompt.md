---
description: intent turns a vague request into INTENT.md with runnable acceptance checks and non-goals.
max_turns: 14
allowed_tools: [Read, Glob, Grep, Edit, Write, Skill]
append_system_prompt: "The user is away. Where the intent skill would ask the user a question, pick the recommended answer yourself and record it under Open questions as 'assumed: …'. Do not spawn subagents. Skip blind checks and say so."
---

Use the flow-stack intent skill for the active task `pow` (the folder already exists at .flow/tasks/pow/). The request: "the calculator should be able to do powers". Write INTENT.md and any check files; don't implement pow itself.
