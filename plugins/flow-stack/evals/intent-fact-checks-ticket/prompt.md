---
description: intent fact-checks a ticket. The one criterion with a false premise is flagged with evidence; the valid ones are built into checks, not argued with.
max_turns: 18
allowed_tools: [Read, Glob, Grep, Edit, Write, Skill, Agent]
append_system_prompt: "The user is away. Where the intent skill would stop at a gate, present what you would show at the gate as your final reply and stop there. Skip blind checks and say so."
---

Use the flow-stack intent skill for the active task `mul` (the folder already exists at .flow/tasks/mul/). The ticket, as written by our PM:

> CALC-12 · Add multiplication
> AC1: `mul 2 3` prints 6.
> AC2: `mul 0 5` prints 0.
> AC3: Like `add`, `mul` rejects non-numeric input with exit code 2 (reuse add's existing validation).

Write INTENT.md and the check files; don't implement mul itself.
