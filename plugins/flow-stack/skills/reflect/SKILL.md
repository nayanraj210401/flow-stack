---
name: reflect
description: Turn corrections and traces into proposed taste, lesson, and calibration updates you approve; prefers lint rules over prose. Use for /reflect, "remember this", at task close.
---

# reflect: taste that evolves, lessons that stick

Nothing is written without the human's approval. Everything proposed has a source.

## 1. Gather

- **Corrections**: places in this conversation where the human changed your output, rejected an approach, or said "no, do X". These are the richest signal. For corrections from earlier conversations, `../recall/scripts/recall.sh grep '\b(no|don.t|instead|stop|wrong)\b' --days 14` lists the human's pushback lines.
- The task's DECISIONS.tsv (human rows), TRACE.md (estimate vs. actual), and EVIDENCE.md (what failed repeatedly).
- `.flow/lessons.md`, `.flow/taste.md`, and the profile's `# Taste`, to avoid duplicates and spot contradictions.
- For "across tasks" reflection: the other `TRACE.md` files in `.flow/tasks/*/`.

## 2. Classify each learning

| Learning | Destination | Example |
|---|---|---|
| A personal preference that will recur | profile `# Taste` → area | "prefer `Result` over throwing in services" |
| True for this repo, for everyone | `.flow/taste.md` | "API errors use the problem+json shape" |
| A mistake to not repeat here | `.flow/lessons.md`, **better as structure** | "tests need `TZ=UTC`" → set it in the test script |
| A hard constraint | profile `# Rules` (rarely) | "never touch the billing schema" |
| A preference that stopped being true | retire to `# Taste history` | an old entry the human overrode twice |
| Estimate error | profile `# Calibration` row update | feature tasks cost 1.6× estimate |
| The same manual sequence in 3+ traces | forge suggestion | `make-playbook` for "add endpoint" |
| An agent-side failure pattern | suggest a flow-stack change | "fence too tight on every refactor" |

**Encode before you write** (principle-encode-in-structure). For each lesson, first ask whether a lint rule, test, script default, hook line in `.flow/gates.md`, or type could make the mistake impossible. Propose that change; the lesson line then records `encoded: <where>`.

## 3. Propose (one message)

```
reflect · 4 proposals
1. taste/Code  + "prefer early returns over nested ifs" · src: you rewrote 3 functions this way today   [y/n]
2. lessons     + tests need TZ=UTC → encode: add TZ=UTC to "test" script in package.json   [y/n]
3. taste/Prose − retire "use bullet lists everywhere" (you asked for prose twice)   [y/n]
4. calibration   feature: est $1.20 → actual $2.05 (n=3)   [y/n]
```

## 4. Apply

Apply only the approved items: dated, sourced, and in the right file. Calibration rows keep a running count and the average error. Report in one line what was written where.
