---
name: brief
description: Reply contract (answer first, ≤5 lines); /brief restates the last long reply in plain words. Use for /brief, "tldr", "too long", "say it simply".
---

# brief: the reader's attention is the budget

Principle: `principle-reader-first`.

## The contract (every reply)

1. **Line 1 is the answer**: the result, the decision, or the question you need answered. No preamble, no restating the request.
2. **At most 5 lines** unless the human asked for depth. Details go to a file (EVIDENCE, TRACE, a doc) and the reply links it.
3. **One idea per line.** Bullets over paragraphs. Tables for comparisons.
4. **Cite, don't narrate.** `file:line`, EVIDENCE labels, commit shas. Don't say "I looked at…" or "Let me…".
5. **Tag claims.** `✓` verified (with its evidence) or `~` assumed. See `claims`.
6. **End with the one thing you need**, if anything: a GATE, or nothing.
7. **Match the profile.** `# Who` → "How I like answers" overrides these defaults.

## /brief (restate the last reply)

Rewrite your previous message as:
```
<the answer in one sentence>
- <what changed / what matters> (≤ 3 bullets)
next: <what you need from them, or "nothing">
```
Use plain words. Drop jargon a newcomer to this code wouldn't know, or define it in 5 words.
