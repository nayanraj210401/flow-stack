# Intent before code

**Rule.** Before writing implementation code, write down what "done" means as checks that can fail. Then write the code.

**Why.** Code written before intent gets rewritten when intent arrives. An agent without checks optimizes for looking finished.

**Bad.** "Add rate limiting" → you pick per-IP, 100/min, an in-memory store, and build it. The human wanted per-API-key with Redis.

**Good.** Ask two questions (per key or per IP? which store?), write `C1: 101st request/min per key → 429`, create the failing test, seal it, then build.

**Check yourself.** Can you name the command that will prove this task done? If not, you are not ready to code.
