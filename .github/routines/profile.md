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
factory_ready: enforce            # warn | enforce: --auto ship in a repo that isn't factory-ready runs as plain --auto
auto_merge: low-risk              # labelled | low-risk: auto-merge also merges unlabelled risk:low size:S self-heal PRs
---

# Who
<!-- Read by: brief, teach, intent. Sets how deep explanations go.
     SessionStart injects the filled lines of this section. -->
- Role: unattended maintainer of flow-stack, a Claude Code plugin; a solo human reviews each PR once a day
- Strong in: bash, jq, git, Claude Code hooks, skills and plugin layout
- How I like answers: terse; PR bodies lead with the outcome and the evidence, then the diff's risk

# Repos
<!-- Read by: SessionStart (only the entry whose path contains the cwd), wrap, setup.
     setup pre-fills from a repo scan; delete what you don't work on. -->
## flow-stack
- path: /home/runner/work/flow-stack/flow-stack
- what: Claude Code plugin: two-loop skill stack (intent → slices → prove) with bash + jq hooks
- test: for t in $(git ls-files 'plugins/**/*.test.sh' | grep -v /herdr/); do bash "$t"; done
- notes: claude plugin eval is the paid model eval; routines don't run it
- notes: skills and templates are prompts other agents follow, so Markdown here is code: review it like code
- notes: before changing behavior, `feature-map/scripts/features.sh impact`; prove with `features.sh run --impacted`

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
- No new runtime dependency: nothing beyond bash, jq, git, perl and the POSIX userland; an optional tool degrades gracefully when missing.
- Never widen what a guard, fence, seal, gate, or the review bar lets through on your own: past a proven false positive (its payload becomes a test), widening is a human decision, made in a PR a human merges.
- Never bump the version in plugin.json or marketplace.json; releases are the human's.

# Taste
<!-- Your preferences; the rubric for deslop, unslop, review, and brief.
     One entry per line:  - YYYY-MM-DD · <preference> · src: <where it came from>
     reflect proposes additions and retirements; you approve each one. -->
## Code
- 2026-10-28 · smallest diff that works; delete before adding · src: preset solo-hacker
- 2026-10-28 · no abstraction until the third copy · src: preset solo-hacker
- 2026-11-04 · reuse an existing script, hook helper (hooks/lib.sh) or skill before adding one; `rg` the verbs first · src: owner's profile
- 2026-11-04 · bash: quote every expansion, jq for JSON in new code, runs on both macOS and Linux userlands · src: repo convention
- 2026-11-04 · a hook fails safe: a parse error or missing tool never blocks the user's session silently, it says why · src: repo convention
- 2026-11-04 · a fix lands at the root cause, not a special case for the one payload that broke · src: principles fix-root-causes

## Prose
- 2026-10-28 · replies in 3 lines or fewer unless asked · src: preset solo-hacker
- 2026-11-04 · skill and doc prose: imperative, one idea per sentence, no filler or hedging; cut a sentence that restates another · src: principles reader-first
- 2026-11-04 · a skill change keeps its SKILL.md description routing-accurate: what it does and when to use it · src: repo convention
- 2026-11-04 · commit titles: conventional-commit style, lowercase, no trailing period; PR titles follow the running routine's shape rule · src: git log, self-heal.md

## UI

## Naming
- 2026-11-04 · name a script for its verb on the feature (`features.sh run`, `ready.sh record`); reuse the terms the README defines (slice, seal, gate, stamp) · src: repo convention

## Testing
- 2026-10-28 · one end-to-end check per feature beats many unit tests · src: preset solo-hacker
- 2026-11-04 · every behavior change comes with a `*.test.sh` next to the script or hook, seen failing before the fix · src: principles red-before-green
- 2026-11-04 · a hook test drives the hook with the real payload's shape and the fields the hook reads, through verify-flow-stack's lib.sh helpers · src: verify-flow-stack
- 2026-11-04 · a stop.sh false-positive fix adds its payload as a case in verify-flow-stack's claims.stop.sh · src: owner's lessons, 2026-10-08

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
