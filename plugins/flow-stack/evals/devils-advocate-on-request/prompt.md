---
description: 'Asking "is there a better way?" triggers challenge. Alternatives and the null option come back as a comparison, not a defense.'
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill, Agent]
---

Our Node service reads `config.json` from disk on every request (about 300 req/s), and profiling shows that read is 8% of CPU. My plan is to add a Redis cache in front of the config reads. Is there a better way? There's no code here; answer from the description.
