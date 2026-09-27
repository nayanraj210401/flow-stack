---
name: how
description: "Explain how code works with file:line citations: runtime flow, ownership, where a change belongs. Use for \"how does X work\", \"walk me through\", \"where should this live\"."
---

# how

Answer from the code, not from what the code probably does.

1. **Start from the map.** If `.flow/map.md` exists, read it first to find the entry points. If it doesn't and the question spans the repo, say so and offer `map`.
2. **Trace, don't skim.** Follow the actual path: the entry point → the calls → the data it touches → where it exits. Prefer symbol-level tools (serena `find_symbol` / `find_referencing_symbols`, or an LSP) over reading whole files. When a trace crosses more than about 5 files, send an Explore subagent with the exact question and keep only its cited answer (principle-spend-cheap-save-expensive).
3. **Answer shape** (per `brief`):
   - Line 1: the answer in one sentence.
   - Then the path as a numbered list, one `file:line` per step, at most 7 steps.
   - Then one line per surprise: implicit behavior, a global, a side effect.
   - For "where should this live": name the module, the reason (who owns that data or decision), and the nearest existing precedent at `file:line`.
4. Offer depth, don't dump it: "Want the error path too?"

For motivation ("why is it built like this"), hand off to `why`.
