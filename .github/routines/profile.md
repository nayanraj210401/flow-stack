---
profile_version: 1
preset: solo-hacker                      # the preset this profile started from
attention:
  review_minutes_per_day: 45      # delegate and tour respect this
  max_parallel_agents: 3          # delegate never runs more workers than this
budget:
  subagent_model: haiku           # exploration, bulk reads, summaries
  build_model: sonnet             # implementation workers
  design_model: opus              # intent, architecture, review
  handoff_at_context_pct: 60
notify: off                 # osascript | ntfy:<topic> | off
notify_on: blocked                # blocked | all
dojo: off                         # off | light (explain-back) | on (TODO(you))
digest: off                       # off | terminal | page: how /flow-stack:wrap delivers the daily brief
review_gate: on                   # on | yolo: on = a PR needs ready.sh (review, deslop, tour, checks) before human review
rigor: lean                   # lean | standard | strict: how much ceremony flow spends per task
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
## flow-stack
- path: /home/runner/work/flow-stack/flow-stack
- what: Claude Code plugin: two-loop skill stack (intent → slices → prove) with bash + jq hooks
- test: for t in $(git ls-files 'plugins/**/*.test.sh' | grep -v /herdr/); do bash "$t"; done
- notes: claude plugin eval is the paid model eval; routines don't run it

# Workspaces
<!-- Repos a single task may span. task.sh new <slug> <playbook> --workspace <name> puts the task in the
     role: primary repo and guards every listed repo.
## example
- repos: example-repo, example-dep
- search: ~/Project          (where to look for repos not listed) -->
# Board
<!-- Read by: board/collect.sh on every /flow-stack:board run, from any session. Bad lines show as warnings
     on the board. Panels: needs spend attention tasks features quality decisions debt shipped estimate repos.
- theme: auto                 # auto | light | dark
- tab: current                # current | all | <repo name>
- hide: spend
- order: tasks, quality
- wide: debt
- accent: #2F55D4
- view: Paused tasks · [.repos[].tasks[] | select(.active | not) | {slug, goal}] · table -->

# Rules
<!-- Hard constraints. Always injected. Keep ≤ 20 lines.
     A rule is never OK to break. A preference belongs in Taste. -->
- Never push to the default branch.
- Push, PR, and merge only as the running routine's file allows; never deploy or publish.

# Taste
<!-- Your preferences; the rubric for deslop, unslop, review, and brief.
     One entry per line:  - YYYY-MM-DD · <preference> · src: <where it came from>
     reflect proposes additions and retirements; you approve each one. -->
## Code
- 2026-10-28 · smallest diff that works; delete before adding · src: preset solo-hacker
- 2026-10-28 · no abstraction until the third copy · src: preset solo-hacker

## Prose
- 2026-10-28 · replies in 3 lines or fewer unless asked · src: preset solo-hacker

## UI

## Naming

## Testing
- 2026-10-28 · one end-to-end check per feature beats many unit tests · src: preset solo-hacker

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
