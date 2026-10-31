---
id: board.publish
title: Publish the flow-stack board
owns: plugins/flow-stack/skills/board/** .claude/skills/verify-flow-stack/scripts/board.publish.sh
entries: skill /flow-stack:board | cli skills/board/scripts/collect.sh | cli skills/board/scripts/render.sh | cli skills/board/scripts/attention.sh | hook Notification → hooks/notify.sh (waits.jsonl)
scenario: bash .claude/skills/verify-flow-stack/scripts/board.publish.sh
status: verified
verified: 2026-10-29 90da7be
---
# Publish the flow-stack board

The user runs /flow-stack:board and gets one private artifact link with real data across their repos, refreshed in place on every run.

## Sub-features
- board.publish.collect · collect.sh emits tasks (slices, gates, active), features, agent-only decisions, debt with triggers, shipped commits; --no-cost/--no-prs honored
- board.publish.render · render.sh fills the template; data can't close the script tag; non-board JSON is refused
- board.publish.quality · collect.sh scores each repo 0–100 on eight dimensions (null when no data); the template draws a Quality panel and an All-repos column
- board.publish.prefs · the profile's # Board section (theme, tab, hide, order, wide, accent, jq views) lands in board.json.prefs, identical from any lead; bad lines become warnings; views can't read env
- board.publish.sessions · each task lists its Claude sessions (distinct trail.jsonl sids) with title, calls, minutes of you
- board.publish.attention · attention.sh turns transcripts + waits.jsonl into prompt/answer/question/permission events (5 min cap); collect.sh adds per-day minutes, blocked, switches, peak, and today's 🔴/🟡 warnings; the Your attention tile and Needs you show them; --no-attention skips it
- board.publish.artifact · the skill publishes to the saved URL (model-only; not driven)

## How to get to it
- /flow-stack:board

## Driving it
bash .claude/skills/verify-flow-stack/scripts/board.publish.sh

## Proof
17 ✓ lines; board.json in the artifacts folder.

## Gotchas
Not driven: the Artifact publish itself (needs the model's Artifact tool), gh PRs, and ccusage cost.
