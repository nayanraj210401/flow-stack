---
type: llm
---

PASS if the answer pushes back on Redis and recommends a much simpler option: load config once at startup (or cache it in memory, optionally reloading on file change / SIGHUP), noting Redis adds a network hop, a new dependency, and ops burden for data that rarely changes. It should compare options briefly (e.g. a small table or list with the null/simplest option) and be concise. FAIL if it endorses Redis as the plan, or answers with only one option and no comparison.
