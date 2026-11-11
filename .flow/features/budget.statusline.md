---
id: budget.statusline
title: Status line and cost
owns: plugins/flow-stack/skills/budget/** .claude/skills/verify-flow-stack/scripts/budget.statusline.sh
entries: cli statusline.sh (Claude Code statusLine) | cli cost.sh | skill /flow-stack:budget
scenario: bash .claude/skills/verify-flow-stack/scripts/budget.statusline.sh
status: verified
verified: 2026-10-26 b6cdf74
---
# Status line and cost

The status line shows model, context %, session cost, and the active task, after the user's own status line.

## Sub-features
- budget.statusline.line · `<model> · ctx N% · $X.XX · flow:<task>`
- budget.statusline.chain · FLOW_STATUSLINE_CHAIN output comes first, joined by `│`
- budget.statusline.cost · cost.sh reports usage via ccusage

## How to get to it
- settings.json `statusLine.command` → statusline.sh (setup installs it)
- CLI: `plugins/flow-stack/skills/budget/scripts/cost.sh`

## Driving it
`.claude/skills/verify-flow-stack/scripts/budget.statusline.sh` runs in a throwaway toy repo with a sandboxed FLOW_STACK_HOME, drives every entry point above, and prints one ✓/✗ per sub-feature.

## Proof
- exact string `previous-line │ Opus · ctx 42% · $1.23 · flow:demo`
- absence: no `flow:` segment without an active task

## Gotchas
- `budget.statusline.cost` is not driven: it needs ccusage or network npx.
