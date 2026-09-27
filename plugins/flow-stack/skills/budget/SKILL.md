---
name: budget
description: Context and cost discipline (subagents, cheap models, symbol reads, handoff threshold); /budget reports spend. Use for "context is full", "this is expensive", /budget.
---

# budget: three currencies

Principle: `principle-spend-cheap-save-expensive`. Tokens are cheap but capped per session. Dollars are moderate. Human attention is the most expensive.

## Rules of thumb

1. **Main context is for decisions, not payloads.** Reading more than about 5 files, grepping widely, or reading long logs goes to a subagent with a precise question, and only its conclusion comes back.
2. **Cheapest capable model per step** (from the profile's `budget:`): `subagent_model` for exploration, search, and summaries; `build_model` for implementation workers; `design_model` for intent, architecture, review, and diagnosis once the circuit breaker has tripped.
3. **Symbols over files.** Use serena or LSP `find_symbol` / `get_symbols_overview` instead of reading a 2,000-line file for one function. Use `Read` with `offset`/`limit` when you know the range.
4. **Map once.** Read `.flow/map.md` rather than re-exploring (see `map`).
5. **Compress tool output.** rtk shrinks CLI output when installed. Pipe long commands through `tail -n 40` or `grep`. Never cat a lockfile or a minified bundle.
6. **Don't re-read** files you just edited, or output you already have.
7. **Loops cost the most.** Three failed attempts at the same thing cost more than stopping to think; the circuit breaker enforces this.

## Handoff threshold

When the status line or `/context` shows usage past the profile's `budget.handoff_at_context_pct` (default 60%), finish the current slice, then run `handoff`. Past 80%, handoff immediately. A compaction mid-slice loses reasoning that files don't hold.

## /budget

1. `scripts/cost.sh` for today (or `scripts/cost.sh session`). It needs ccusage, which setup offers.
2. Context: tell the human to run `/context`, or read the flow status line (`scripts/statusline.sh`; setup installs it).
3. For the active task, compare against ESTIMATE and report in 3 lines: spent vs. estimate, the biggest cost driver (from the trail: tool counts, large reads), and one concrete saving for the rest of the task.
