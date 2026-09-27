---
name: debt
description: Ledger of shortcuts taken, each with a cost and a repay trigger. Use when taking a shortcut, or for /debt, "what did we cut".
---

# debt: make shortcuts visible

Shortcuts are fine. Hidden shortcuts are how prototypes collapse weeks later.

## Record (at the moment you take the shortcut)

Append to `.flow/debt.md` (create it from the plugin template if it is missing):
```
- [ ] D<n> · <date> · <shortcut> · where: <file:line> · cost if ignored: <concrete> · repay when: <trigger> · task: <slug>
```
Triggers are events, not dates: "before a second tenant", "when traffic > 100 rps", "before public launch", "next time this file changes".

Examples of debt: an unhandled edge case, a mocked external service, a hard-coded config value, a skipped test, a compatibility shim, "works for the happy path only", a TODO left in code.

## Report

`/debt` lists the open items, grouped by trigger, and flags those whose trigger has likely fired (e.g. a file listed in `where:` changed recently: `git log --since`). In flow's Present phase, list only this task's new entries, one line each.

## Repay

When one is repaid, tick it, append ` · repaid <date> in <commit/task>`, and keep the line. The history of what was cut and fixed is the point.
