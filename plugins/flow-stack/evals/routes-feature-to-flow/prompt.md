---
max_turns: 6
allowed_tools: [Read, Glob, Grep, Skill]
---

Context: we have a Node/Express API (about 40 routes, API keys checked in `src/middleware/auth.ts`, plan tier stored on the key record in Postgres, 3 instances behind a load balancer, Redis already available). There's no code for you to read here; work from this description.

I want to add per-API-key rate limiting to all routes, with limits configurable per plan tier. Before anything gets built, tell me how you're going to approach it.
