---
description: make-gates finds this repo's irreversible actions and writes enforceable gate lines.
max_turns: 14
allowed_tools: [Read, Glob, Grep, Edit, Write, Skill]
append_system_prompt: "The user is away; write .flow/gates.md without waiting for approval, and list what you'd want them to confirm."
---

/flow-stack:make-gates protect this repo's dangerous operations.
