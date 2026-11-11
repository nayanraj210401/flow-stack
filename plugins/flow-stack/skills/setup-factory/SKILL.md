---
name: setup-factory
description: "Set up a software factory on any host (this laptop, a server or VPS, GitHub Actions, cloud sessions): explain it, read the repo's and machine's state, interview on hosts, jobs, risk and autonomy, tune the profile, run the fixes, and end in a draft PR (repo changes) or local changes only (machine setup). /flow-stack:setup-factory."
disable-model-invocation: true
---

# setup-factory: from a repo to a factory

Idempotent: a second run on a ready setup shows the state, says nothing is missing, and stops. Every fix is an existing skill or script; this skill picks and orders them. Paths are relative to this skill's base directory.

## 0. Say what the factory is (once, ≤ 8 lines, before any question)

- **The factory is flow run without you at the keyboard.** Work is found, specified, built, proven and reviewed; the output is a draft PR that passed flow's ready gate.
- **You sit at three points:** the spec, the code (every PR), the product (what you merge or release). Bot work on an issue starts only after a human label (`heal-ok`).
- **Risk decides what it builds alone:** issues are scored `risk:low|med|high`; `high` gets a spec and `needs-human`, never code.
- **It runs where you put it:** this laptop, an always-on server or VPS, GitHub Actions (routines in the repo, for everyone on it), Claude Code cloud sessions.
- **It needs a repo that can prove its own changes:** a committed verify driver and feature map with a scenario. A runner sees only the clone.
- **Safety:** drafts by default, hooks hold every run, `FLOW_FACTORY=off` pauses every routine.

The full stage map is [../flow/references/factory.md](../flow/references/factory.md); link it, don't recite it.

## 1. Read the state

```bash
bash ../setup/scripts/detect.sh | sed -n '/^FACTORY /,$p'   # loop stages + factory-ready, from HEAD
bash scripts/state.sh                                       # host, profile, shift, repo, GitHub side
```

Show both as one table: fact, status, what serves it or the fix. `unknown` means gh couldn't see it (offline, no auth, not an admin): say so, don't guess. The state shapes the interview: `host` is the default answer to question 1; no github.com remote drops Actions and cloud; `stock-yml warn` means `mention` needs the stock `claude.yml`'s comment triggers removed; `kill off` means routines are paused on purpose, so ask before suggesting a resume.

## 2. Interview

Recommended option first and marked; skip what the state already answers. Under `--auto` nobody answers: take every recommended option, log it with `task.sh decide agent`, and queue the rest in GATES.md.

**Round 1** (one AskUserQuestion, 4 questions):
1. **Where should it run?** (multiSelect) this laptop · a server or VPS (always on) · GitHub Actions · cloud sessions. Preselect `host`; recommend Actions when there's a GitHub remote.
2. **What should it do?** (multiSelect) review every PR [recommended] · build issues you label (`self-heal`) · answer `@claude` on GitHub (`mention`) · find bugs nightly (`self-create`) · sort new issues (`triage`, + `ideate`) · prepare your own queue overnight (the shift; laptop or server).
3. **Up to what risk may it build without you?** low and med [recommended: the default] · low only · nothing, specs only. `risk:high` is never built, whatever the answer. Where it lands: on Actions, risk labels exist only with `triage`. Without it self-heal builds any `heal-ok` issue, so any ceiling adds `triage` to the picks, and "low only" also tailors self-heal's `risk:low` or `risk:med` line. On the shift, `start.build_up_to` is `med` or `low` (an unlabelled issue counts as `med`). "Specs only" drops `self-heal` and the shift's `start` job.
4. **How far alone?** draft PRs only [recommended] · also auto-merge PRs a maintainer labelled (the `ship` stage: it merges code) · on a laptop or server, `--auto ship` may push and open PRs after the ready stamp.

**Round 2** (only the questions that apply, ≤ 3):
- **Risky paths here?** (multiSelect) propose them from the scan: hooks, CI scripts, migrations, deploy configs, `.flow/gates.md` entries, auth and billing code. They go in `.github/routines/safety-paths.txt`: auto-merge never merges them and triage scores them `risk:high`. Only with Actions.
- **Whose repo?** just me · a team or org. Team means: the repo's own label names (`labels.tsv`), never create labels unasked, `api-key` auth when a routine serves other people's repos, and offer `../../templates/team-taste.md`.
- **Where should it reach you?** a server, VPS or cloud host can't use `osascript`: `ntfy:<topic>` [recommended] · off.

Then state the plan in one message: each answer → the rows it turns `ok`, what stays `missing` on purpose, and which output it ends in (step 8). Proceed; the gates come later.

## 3. Tune the profile

Compare the profile (`state.sh`'s `profile` row, `~/.flow-stack/profile.md`) with the answers and propose one diff. Profile edits are a gate: show it, apply on yes. No profile: `/flow-stack:setup` first.

| When | Change |
|---|---|
| any unattended host | `factory_ready: enforce`, so `--auto ship` in a repo that isn't factory-ready drops to plain `--auto` |
| `review_gate: yolo` | `on`: the factory's PRs are trusted only through the ready stamp, and shift releases refuse `yolo` |
| server, VPS or cloud and `notify: osascript` | `notify: ntfy:<topic>` from round 2, `notify_on: blocked` |
| self-heal or the shift picked | check `attention.review_minutes_per_day`: every unattended PR spends it; size per-run caps to it |
| the shift picked | a `shift:` block (make-routines' "The shift" has the shape): `repos:` only repos whose code the user trusts, `start.build_up_to` from question 3 |
| this repo has no `# Repos` entry | add one (path, what, test, run), the way setup fills it |

For Actions, the run's profile is a different file, `.github/routines/profile.md`, which make-routines writes from a preset. It is committed, so strip anything personal.

## 4. Verify first (nothing unattended is allowed without it)

The `verify` row gates `self-heal`, `auto-merge`, `--auto ship` and the shift's `respond`/`start`, so fix it before anything else whenever the plan touches this repo. Before the first commit, `git switch -c flow-factory` from the default branch: every commit this run makes goes there (step 8).

| `verify` says | Do |
|---|---|
| missing a committed verify driver, and `.claude/skills/verify-*/` or `verify/` exists on disk | check `git check-ignore -v` on it; if ignored, un-ignore that path, then commit it |
| missing a committed verify driver, none on disk | `/flow-stack:make-verifier` |
| missing a committed feature map, and `.flow/features/` exists on disk | the same: un-ignore `.flow/features/` (keep `.flow/tasks/`, `.flow/ACTIVE`, `.flow/trail.jsonl` ignored) and commit it |
| missing a committed feature map, none on disk | `/flow-stack:feature-map` |
| missing a committed feature map, but `.flow/features/` is committed | no feature has a `scenario:`: `/flow-stack:feature-map` to add one |

Then run the scenarios once (`../feature-map/scripts/features.sh run --all` on a new map, `--impacted` otherwise). A factory that can't pass its own scenarios on HEAD stamps nothing. `tests none` in the state: offer to fill `.flow/config.json` `commands` the way setup's "This repo" step does.

## 5. Build each host that was picked

**GitHub Actions.** Run `/flow-stack:make-routines` with the picks from question 2 (`self-heal` only once `verify` is ok), the risky paths, and the team answers. It asks schedules, caps, auth and label names, writes `.github/routines/` and the workflows, and runs `routines.sh check`. Don't repeat its questions. Skip its "Ask before the workflows leave the machine" step: its files join `flow-factory` in step 8. With a risk ceiling, `triage` is in the picks (question 3). For "low only", tailor the `risk:low` or `risk:med` line in `.github/routines/self-heal.md`, then `routines.sh render`. Auto-merge has no template: follow factory.md's `ship` fix.

**This laptop.** The profile from step 3, then the shift if picked: `make-routines add shift --local` writes a launchd plist and prints its install command, which the user runs. `--auto ship` needs nothing installed: `/flow-stack:flow --auto ship <task>`.

**A server or VPS.** The same as the laptop, but run this skill on the server itself (over ssh), since it reads and writes that machine's profile. Check, and hand over what's missing: `claude` installed and logged in, flow-stack installed (`claude plugin marketplace add https://github.com/nayanraj210401/flow-stack.git`, then `claude plugin install flow-stack@flow-stack`), `gh auth login` with a token scoped to the repos it works on, and git able to push. On Linux, `make-routines add shift --local` writes a crontab line (tagged `# flow-stack-shift`) instead of launchd; the user installs it. A long `--auto` run belongs in tmux, so it survives the ssh session. Not supported: the server as a self-hosted Actions runner (the workflows use `ubuntu-latest`, and `--gha` refuses anything but a GitHub-hosted runner).

**Cloud sessions.** Hand over the README's "Cloud sessions" steps (Trusted network, the two-line setup script, a committed feature map). The known limit: no GitHub GraphQL there, so a cloud session builds and stamps a branch, and a routine or a laptop opens the PR (#194).

## 6. The human steps (gates: list them, don't run them)

From the state's `missing` and `unknown` rows, for the hosts picked:
- **Actions:** make-routines' "Human steps": the secret (`claude setup-token`, `gh secret set CLAUDE_CODE_OAUTH_TOKEN`), the Claude GitHub App (`/install-github-app`), branch protection on the default branch, the first `heal-ok` label, one manual run.
- **The shift (laptop or server):** a fine-grained token at `$FLOW_STACK_HOME/shift/token` for `shift.repos` (Pull requests read and write, Contents read, Issues read); `state.sh` shows `shift missing` until it exists. Then the scheduler install command make-routines printed.
- **Always, with routines:** the kill switch. `gh variable set FLOW_FACTORY --body off` pauses every routine, `gh variable delete FLOW_FACTORY` resumes.

## 7. Prove it

Re-run step 1. Done means the `factory` row is `ok` (when the repo was in the plan) and every row the user picked is `ok`. The stage rows read HEAD, so with "leave uncommitted" (or `--auto`) they stay `missing`: that is the expected end, not a reason to loop; say which rows flip once the files are committed. For the shift, `shift.sh run --dry-run` plans a run without staging anything on GitHub.

## 8. The output: a draft PR, local changes, or both

| What changed | Output |
|---|---|
| only this machine (profile, shift, scheduler entry, installs) | **local changes, no PR.** List each file changed and each command left for the user |
| repo files (driver, feature map, `.gitignore`, `.github/routines/`, `.github/workflows/flow-*.yml`, `safety-paths.txt`) | **one draft PR** from `flow-factory`, never the default branch, never mixed into another change |
| both | both: the local list, then the PR |

For repo changes, ask once (a gate): **draft PR** [recommended]: commit, `git push -u origin flow-factory`, `gh pr create --draft --title "ci: make this repo factory-ready"`, with a body listing the routines (triggers, caps, risk ceiling) and step 6 as a checklist · **branch only**: commit, no push · **leave uncommitted**. Under `--auto`, queue it in GATES.md and leave the files uncommitted.

Reply in ≤ 5 lines: what changed and where (the PR link, or the local files), what stays `missing` on purpose, the open human steps, and the one next step: merge the PR, then `gh workflow run flow-<name>.yml` and read its summary for `## Profile` and `[flow auto`; or, machine-only, `shift.sh run --dry-run` or a first `/flow-stack:flow --auto` task.
