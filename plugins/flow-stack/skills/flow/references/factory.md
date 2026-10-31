# The factory

The factory is flow run as one loop, without a human at the keyboard: work is found, specified, built, proven, reviewed, and shipped, and the human sits at three points (spec, code, product). Read this when running with `--auto`, `--auto ship`, or `--gha`, or inside a routine.

`../setup/scripts/detect.sh` prints one `FACTORY` row per stage for the current repo: `ok` with what serves it, `missing` with the skill that fixes it, or `planned` with its issue.

## The loop

Stages marked **planned** don't exist yet; don't act as if they do.

| Stage | Served today by | Planned | Human touchpoint |
|---|---|---|---|
| Monitor | `self-create` routine (finds bugs by running code); CI on main | prod signals; the shift's watchers for a person: assigned work, feedback on my PRs, review requests (#188, #189) | none |
| Triage | nothing: a human files or picks the issue | `triage` routine: type, readiness, size, risk at intake (#185); `ideate` routine: evidence-cited proposals (#186) | planned (#184, #185): bot-originated work needs one human label before it is built. Today `self-heal` takes `heal-ok` and `self-create` issues |
| Spec | `intent` (goal, non-goals, runnable checks, blind checks) + `seal` | edge-case matrix that seal enforces (#187) | **review the spec**: the intent gate in a session; under `--auto` the agent approves it. Planned: high-risk issues (#185) and `proposal` → `accept` (#186) |
| Implement | `self-heal` routine; `flow --auto` in any session; `@claude` via `claude.yml` | `@claude` runs through flow with the plugin installed (#183); cloud sessions (#194); multi-repo routing (#190) | none |
| Verify | the repo's verify driver + impacted feature scenarios (`features.sh run --impacted`) + `probe` | driver and feature map committed so routines see them (#182) | none |
| Review | `ready.sh` stamp (review, deslop, tour, live checks); `review` routine | stamp carried as a `flow/ready` check run, rework loop capped at 2 rounds (#184) | **review the code**: every PR today (routines open drafts; `auto-merge` takes only maintainer-labelled PRs). Planned: med/high risk (#185), rework past 2 rounds (#184) |
| Ship | `auto-merge` routine (maintainer-labelled PRs, security review); `--auto ship` / `--gha` unlock a stamped push, PR, merge | human-approved auto-merge of factory PRs, draft → ready (#184); GitHub Project board (#191) | **review the product**: what you merge or release |

## Factory-ready

A repo is factory-ready when it has a **committed** verify driver (`.claude/skills/verify-*/` or `verify/`) and a **committed** feature map with at least one scenario. Committed, because runners and cloud sessions see only the clone. Existence isn't enough: the impacted scenarios must also pass on HEAD, which `ready.sh` already runs.

Today `detect.sh` reports it (row `factory`). **Planned (#181, draft PR #196):** `hooks/lib.sh` `factory_ready` checks the same rule at HEAD; `--auto ship` and `--gha` warn in a repo that isn't factory-ready, or run as plain `--auto` (no push, no PR) with the profile's `factory_ready: enforce`, and `make-routines` refuses `self-heal` and `auto-merge` there. Pair mode is unaffected.

## Fixes

| Row missing | Run |
|---|---|
| monitor, implement, review | `/flow-stack:make-routines` (`self-create`, `self-heal`, `review`) |
| verify: no driver | `/flow-stack:make-verifier` |
| verify: no feature with a scenario | `/flow-stack:feature-map` |
| verify: `commit …` | commit that path; a gitignored driver or map is invisible to routines |
| ship | `auto-merge` has no `make-routines` template yet (#184); copy this repo's `.github/routines/auto-merge.md` |
