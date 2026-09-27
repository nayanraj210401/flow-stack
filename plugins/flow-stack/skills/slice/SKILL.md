---
name: slice
description: Split an approved INTENT into small slices, each with a check, a file fence, and a line budget. Use for /slice, "break this down", "plan the steps".
---

# slice: small units that prove themselves

Principle: `principle-smallest-verifiable-unit`.

## Rules for a good slice

1. **It ends green.** After the slice, the repo builds, and its check passes.
2. **It has one check.** It reuses an acceptance check or is a narrower one. `check:` is a single command.
3. **Its fence is tight.** Start from the touched features' `owns:` (see `features.sh impact`), then narrow it. `fence:` lists repo-relative globs of the files it may touch. It is a scope promise, enforced by the fence hook.
4. **Its budget is honest.** `budget:` is the maximum number of changed lines. Default 150; above 300 means split it.
5. **The first slice is a tracer bullet**: the thinnest end-to-end path through every layer (route → logic → storage → response), even if it is ugly. Later slices thicken it.
6. **Order by risk.** Unknowns go early. Mechanical work goes late.
7. **Independent slices are marked** with `parallel: yes`, so `delegate` can fan them out.
8. **Subtraction slices first.** If the challenge or the subtract scan found dead code, a wrapper, or a legacy path to remove, make it its own first slice (`S0 · delete …`). Its budget counts removals, and it must keep every check green.
9. **Red and teeth.** Every slice owes a red run and a probe unless it says why not (`red: n/a …`, `teeth: n/a …`). Refactor slices usually have `red: n/a behavior-preserving` because their pin must stay green.

## Output

Write SLICES.md (format in `../flow/references/conventions.md`). Show the human a numbered list, one line per slice: `S1 · tracer: POST /login → 429 at limit · check: rate-limit.spec · ~80 lines`. No gate is needed unless the slicing reveals a scope question. In that case, raise that question alone.

## Checks per slice

When a slice needs a narrower check than an acceptance check, write that check file first and seal it along with the others.
