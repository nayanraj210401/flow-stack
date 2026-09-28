---
name: tour
description: "Risk-ranked diff tour for the reviewer: what to read, skim, or skip, with net lines. Use for /tour, \"what should I review\", before a merge gate."
---

# tour: spend review minutes where the risk is

A 600-line diff usually has about 40 lines that need a human. Find them.

## Rank every hunk

| Tier | What | Human action |
|---|---|---|
| **1 · read** | new logic, changed contracts (signatures, API shapes, schemas), security or auth, concurrency, money, data deletion, anything irreversible | read line by line |
| **2 · skim** | new tests, error handling, config, non-trivial renames | check intent matches |
| **3 · skip** | mechanical: formatting, import moves, codemod output, generated files, lockfiles | skip; reason given |

Use `../loop/scripts/diffstat.sh` and the hunks. When net lines are positive, add one line on what the added code buys (from INTENT `## Approaches`). For each tier-3 claim, say *why* it is safe ("codemod output; script at .flow/tasks/x/rename.ts; all 212 call sites compile"). "Safe to skip" is itself a claim and needs evidence.

**Group by feature** when `.flow/features/` exists: `../feature-map/scripts/features.sh impact` maps each file to its feature. The human reviews "auth.login: 3 hunks, lockout logic" rather than a file list.

## Output

```
tour · <n> files · +<a>/-<r> (net <±n>, <k> new files) · est. <m> min review
READ (≈<m> min)
  1. src/auth/limit.ts:40-72 · token bucket refill: concurrency across requests · C1, C3 cover it
  2. …
SKIM
  - tests/…: new checks for C1–C4
SKIP (with reason)
  - 38 files · import path rename (codemod, compiles, suite green)
not verified: <anything no check covers>
```

Order READ items by risk. Estimate review minutes honestly and compare them to the profile's attention budget. If the READ tier alone needs more than 20 minutes, offer to split the change.

The tour goes in the PR body. Once it describes the current HEAD, record it for the ready-for-review bar: `../review/scripts/ready.sh record tour done`.
