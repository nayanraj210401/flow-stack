---
profile_version: 1
preset: none                      # the preset this profile started from
attention:
  review_minutes_per_day: 90      # delegate and tour respect this
  max_parallel_agents: 2          # delegate never runs more workers than this
budget:
  subagent_model: haiku           # exploration, bulk reads, summaries
  build_model: sonnet             # implementation workers
  design_model: opus              # intent, architecture, review
  handoff_at_context_pct: 60
notify: osascript                 # osascript | ntfy:<topic> | off
notify_on: blocked                # blocked | all
dojo: off                         # off | light (explain-back) | on (TODO(you))
rigor: standard                   # lean | standard | strict: how much ceremony flow spends per task
---

# Who
<!-- Read by: brief, teach, intent. Sets how deep explanations go.
     SessionStart injects the filled lines of this section. -->
- Role:
- Strong in:
- Learning:
- How I like answers:

# Repos
<!-- Read by: SessionStart (only the entry whose path contains the cwd), wrap, setup.
     setup pre-fills from a repo scan; delete what you don't work on. -->
## example-repo
- path: ~/Project/example-repo
- what: one line on what it does
- test: npm test   run: npm run dev   lint: npm run lint
- notes: gotchas, owners, deploy target

# Rules
<!-- Hard constraints. Always injected. Keep ≤ 20 lines.
     A rule is never OK to break. A preference belongs in Taste. -->
- Never push, merge, deploy, or publish without asking.

# Taste
<!-- Your preferences; the rubric for deslop, unslop, review, and brief.
     One entry per line:  - YYYY-MM-DD · <preference> · src: <where it came from>
     reflect proposes additions and retirements; you approve each one. -->
## Code

## Prose

## UI

## Naming

## Testing

# Toolchain
<!-- How flow-stack fits your existing setup. Written by setup (adaptation step); edit freely.
     One line per capability:  - <key>: <provider> · <why>
     Keys: router, intent, how, why, teach, verify-driver, review, tdd, diagnose, unslop, deslop,
           handoff, decision-log, delegate, compaction, token-saver, browser, statusline, notify, note.
     SessionStart injects these lines; a flow-stack skill whose key is listed hands off to the provider.
     Guarantees stay with flow-stack either way: seals, blind checks, evidence, claims, trail, gates. -->

# Keep-sharp
<!-- Skills you want to stay good at. With dojo on, the agent leaves these parts to you. -->

# Calibration
<!-- Written by reflect from TRACE estimate-vs-actual rows. Don't hand-edit. -->
| task type | tasks | avg $ err | avg ctx err | avg minutes err |
|---|---|---|---|---|

# Taste history
<!-- Retired taste entries:  - retired YYYY-MM-DD · <entry> · why -->
