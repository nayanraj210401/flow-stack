---
name: make-routines
description: "Forge scheduled GitHub Actions routines that run flow-stack headless: self-create (file reproducible bugs), self-heal (fix issues as proven draft PRs), or your own. /flow-stack:make-routines."
disable-model-invocation: true
---

# make-routines: maintenance that runs while you sleep

Claude Code cloud routines don't load plugins, so flow-stack's hooks never run there. A GitHub Actions job with `anthropics/claude-code-action` installs the plugin, so the guard, the fences, and the ready gate hold even with nobody watching.

## Ask once (batched, defaults in brackets)

- Which routines: `self-create`, `self-heal`, or a custom name [both templates].
- Schedule and caps: the cron line, issues or PRs per run [3], and timeout. Size the PR cap to the profile's `review_minutes_per_day`.
- Auth: `oauth` (a subscription token from `claude setup-token`) or `api-key` [oauth]. A routine that serves other people's repos needs `api-key`.

## Write

```bash
S=<this skill's dir>/scripts/routines.sh
$S add self-create && $S add self-heal     # --preset <p> picks the CI profile's preset [solo-hacker]
```

| File | Committed | What it is |
|---|---|---|
| `.github/routines/<name>.md` | yes | the source of truth: frontmatter `cron`, `timeout`, `labels`, `auth`, and the prompt body |
| `.github/routines/profile.md` | yes | the profile runs use (`FLOW_STACK_HOME`), notifications off. Strip anything personal before committing |
| `.github/workflows/flow-<name>.yml` | yes | rendered from the routine. Edit the routine, then `$S render` |

Tailor each prompt body to the repo: its verify driver, its test command, what "not worth fixing" means here. Keep the template's rules: a bug needs a repro that ran, at most N per run, drafts only, never the default branch.

Every run starts as `/flow-stack:flow --auto ship`. The guard then lets it push only its own branch and open a PR only after `review/scripts/ready.sh` stamps HEAD. Everything else irreversible is queued in GATES.md.

## Human steps (these are gates, so hand them over, don't run them)

1. The secret: `claude setup-token`, then `gh secret set CLAUDE_CODE_OAUTH_TOKEN` (or `ANTHROPIC_API_KEY`).
2. The Claude GitHub App on the repo (`/install-github-app`). PRs opened with the default `GITHUB_TOKEN` don't trigger CI, so self-heal's drafts would arrive with no checks.
3. Commit, push, and start one run by hand: `gh workflow run flow-<name>.yml`. Read its log for `## Profile` (the profile loaded) and `[flow auto ship]` (auto mode is on) before trusting the schedule.

## Self-test

`$S check`: every workflow matches a fresh render of its routine and the profile exists.

Measure it after two weeks: the share of `self-heal` PRs merged, and of `self-create` issues not closed as invalid. Below half, tighten the prompt before adding routines.
