---
description: probe detects a check that passes without the change it claims to test.
max_turns: 10
allowed_tools: [Read, Glob, Grep, Bash, Skill]
---

I added sub() and tests/test_sub.sh. Use flow-stack's probe to tell me whether that test actually tests my change. Don't fix anything.
