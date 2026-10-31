---
id: flow.band
title: Flow band and model per role (the mod)
owns: plugins/flow-stack/hooks/register.tsx plugins/flow-stack/hooks/register.test.ts plugins/flow-stack/skills/flow/scripts/status.sh .claude/skills/verify-flow-stack/scripts/flow.band.sh
entries: ui AbovePrompt band + Spinner suffix (terminal, Desktop) | mod agent.spawn for flow-stack agents | cli skills/flow/scripts/status.sh [dir]
scenario: bash .claude/skills/verify-flow-stack/scripts/flow.band.sh
status: verified
verified: 2026-10-26 b6cdf74
---
# Flow band and model per role

flow-stack's mod (hooks/register.tsx) draws the active task above the prompt and puts flow-stack's agents on the profile's budget model for their role. status.sh is the band's data.

## Sub-features
- flow.band.status · status.sh: {} without a task; task, doing slice (or the TDD slice), n/m slices, TDD phase, last evidence header, stale after an edit; a lane reads its own state
- flow.band.render · AbovePrompt shows `flow · task · slice · n/m slices · tdd · evidence`; nothing without a task; Spinner suffix gets the slice id
- flow.band.models · advocate/reviewer → design_model, worker/checker/flow-agent → build_model when the Agent call names no model; Explore and other built-ins untouched; a budget value that isn't a model name is ignored with a toast

## How to get to it
Install 0.9.0+ (or `claude --plugin-dir plugins/flow-stack`), open a flow task. `/plugin` shows `1 mod active · flow-stack`.

## Driving it
- status.sh: the scenario above (toy repo, evidence.sh, post-tool trail, task.sh tdd, a worktree lane).
- render and models: `claude plugin test plugins/flow-stack` (engine test kit; process.run, fs.read, env mocked).

## Proof
Scenario + plugin tests. Live terminal rendering is not driven by either.

## Gotchas
- Evidence output can contain `### ` lines; only the conventions.md header shape counts.
- A mod draws nothing in VS Code chat or `claude -p`; agent.spawn routing still runs there.
