---
name: deslop
description: "Remove code slop from a diff: narrating comments, dead code, defensive clutter, needless abstraction, duplicate helpers. Use before commit, or for /deslop, \"clean this up\"."
---

# deslop

Scope: only the lines this task changed (`git diff <base>` plus uncommitted changes). Don't reformat the world.

## Cut

- **Narrating comments**: `// increment counter`, `// loop over users`, and comments that restate the next line or the commit message. Keep comments that explain a *why* the code can't show (an external constraint, a non-obvious invariant, a link to an issue).
- **Defensive clutter**: null checks on values the type system or a validated boundary already guarantees; try/catch that only logs and rethrows; `|| {}` fallbacks masking bugs. Guards belong at system boundaries (HTTP, config, external APIs, user input); internal code trusts its types.
- **Needless abstraction**: one-caller wrappers, interfaces with one implementation, config for things that never vary, factories that build one thing.
- **Reinvention**: new helpers that duplicate existing ones. Search the repo (`rg`) for the verb and noun before accepting a new util.
- **Leftovers**: debug prints, commented-out code, unused imports, variables, and params, TODOs with no owner (move them to `debt`).
- **Over-handling**: catching errors that can't happen, retry loops nobody asked for, logs at every line.
- **Style drift**: anything against the repo `.flow/taste.md` or the profile's `## Code` and `## Naming` taste.

## Method

1. List the findings as `file:line · type · fix`.
2. Apply fixes that don't change behavior directly.
3. Re-run the slice or acceptance checks through `evidence.sh` (label `deslop`). Deslop must not change behavior. If a check fails, revert that fix.
4. Report the count: `deslop: −47 lines (12 comments, 3 wrappers, 1 duplicate helper → utils/date.ts:12)`.
5. Commit, then record it for the ready-for-review bar: `../review/scripts/ready.sh record deslop done "<the count>"`.

If the same slop pattern shows up across tasks, tell `reflect`. It may deserve a lint rule (principle-encode-in-structure).
