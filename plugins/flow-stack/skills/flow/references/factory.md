# The factory

The factory is flow run as one loop, without a human at the keyboard: work is found, specified, built, proven, reviewed, and shipped, and the human sits at three points (spec, code, product). Read this when running with `--auto`, `--auto ship`, or `--gha`, or inside a routine.

`../../setup/scripts/detect.sh` prints one `FACTORY` row per stage for the current repo: `ok` with what serves it, `missing` with the skill that fixes it, or `planned` with its issue.

## The loop

Stages marked **planned** don't exist yet; don't act as if they do.

| Stage | Served today by | Planned | Human touchpoint |
|---|---|---|---|
| Monitor | `self-create` routine (finds bugs by running code); CI on main; the shift for a person (`make-routines add shift --local`): review requests, feedback on your PRs, assigned issues, prepared overnight on your machine and released by you | prod signals | none |
| Triage | `triage` routine: type, readiness, size and risk labels at intake (a safety path is risk:high, never built); `ideate` routine: at most one evidence-cited `proposal` a week | | **one human label before bot work is built**: `heal-ok` (or, with triage, an approved `triage:ready`); a `proposal` needs `accept` |
| Spec | `intent` (goal, non-goals, runnable checks, blind checks, an edge-case matrix) + `seal`, which enforces the matrix | | **review the spec**: the intent gate in a session; under `--auto` the agent approves it. A risk:high issue gets a draft INTENT and `needs-human`, never code |
| Implement | `self-heal` routine; `mention` routine (`@claude` runs through flow with the plugin, draft PRs only); `flow --auto` in any session; `task.sh route` picks the repo for a request with none named | cloud sessions (#194); shipping linked PR sets across repos (#190) | none |
| Verify | the repo's committed verify driver + impacted feature scenarios (`features.sh run --impacted`) + `probe` | | none |
| Review | `ready.sh` stamp (review, deslop, tour, live checks), carried to self-heal PRs as a `flow/ready` check run; `review` routine; rework loop capped at 3 rounds; a non-ship review verdict on a self-heal PR's head starts a round, then `needs-human` | | **review the code**: every PR except opt-in low-risk self-heal ones (routines open drafts; `auto-merge` takes maintainer-labelled PRs, and opt-in low-risk self-heal PRs). |
| Ship | `auto-merge` routine (maintainer-labelled PRs, or opt-in low-risk self-heal PRs; security review either way); `--auto ship` / `--gha` unlock a stamped push, PR, merge; `board`'s Factory panel and `board/scripts/factory.sh apply` keep a GitHub Project in step with issue and PR state (profile `factory:` `project: <owner>/<n>`) | | **review the product**: what you merge or release |

## Factory-ready

A repo is factory-ready when it has a **committed** verify driver (`.claude/skills/verify-*/`, `.claude/skills/verify/` or a top-level `verify/`) and a **committed** feature map with at least one scenario. Committed, because runners and cloud sessions see only the clone. Existence isn't enough: the impacted scenarios must also pass on HEAD, which `ready.sh` already runs.

`hooks/lib.sh` `factory_ready` checks it, and `detect.sh` reports the same result (rows `verify` and `factory`). `--auto ship` and `--gha` warn in a repo that isn't factory-ready, or run as plain `--auto` (no push, no PR) with the profile's `factory_ready: enforce`, and `make-routines` refuses `self-heal` and `auto-merge` there. Pair mode is unaffected.

## Fixes

`/flow-stack:setup-factory` runs these in order (verify first) and stops at `factory ok`.

| Row missing | Run |
|---|---|
| monitor, review | `/flow-stack:make-routines` (`self-create`, `review`) |
| implement | `/flow-stack:make-routines`: `mention` works in any repo; `self-heal` is refused until the repo is factory-ready |
| verify: `a committed verify driver` / `a committed feature map` | if the driver or map already exists on disk, commit it (a gitignored one is invisible to routines); otherwise run the named skill |
| ship | `auto-merge` has no `make-routines` template; check that `detect.sh` shows `factory ok` first (`render` doesn't check; only `add` does), copy flow-stack's `.github/routines/auto-merge.md` into your repo's `.github/routines/` with `safety-paths.txt` (without the list on the default branch, auto-merge blocks every PR), make sure `.github/routines/profile.md` exists (any `make-routines add` writes it), run `make-routines/scripts/routines.sh render`, and commit the routine, the profile and `.github/workflows/flow-auto-merge.yml` together |
