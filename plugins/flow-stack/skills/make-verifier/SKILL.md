---
name: make-verifier
description: "Forge .claude/skills/verify-<repo>/, a driver that runs this app like a user (CLI, HTTP, browser) and proves itself; if one exists, check it for drift and refresh only what's stale. /flow-stack:make-verifier."
disable-model-invocation: true
---

# make-verifier: teach the agent to use this app like a user

Generic skills can't know how to prove *this* app works. This skill writes the driver that can. The output is read cold, mid-task, by an agent that has never seen the app. Write for that reader.

## 0. Driver already there? Refresh, don't regenerate

If `.claude/skills/verify-<repo>/SKILL.md` exists with `generated-by: flow-stack:make-verifier`, measure drift instead of starting over:
1. **Self-test**: run its `## Self-test` command.
2. **Code drift**: `../feature-map/scripts/features.sh stale` (owned code changed since each feature was verified) and `git diff --stat <source-commit>..HEAD` on the launch files §1 found (build and start commands, env example, ports).
3. **Coverage**: `features.sh coverage`. Features without a scenario (except ones the driver's Gotchas lists as not driven, with a reason), and code no feature owns.
4. **Driver drift**: every script path, command, and flag the driver's SKILL.md names still exists.

All clean → reply `verify-<repo> up to date · source-commit <sha>` and stop. Otherwise, fix only what drifted: add scenarios for the new features, repair the broken ones, and re-run §1 only for launch changes. Keep hand edits. Where one conflicts with the code, ask the human. Then run §4 on the scenarios you changed, bump `generated-at` and `source-commit`, and hand over the list of what changed.

## 1. Interview the repo, not the human

Find out, with evidence (file:line):
- **App type(s)**: CLI, HTTP service, web UI, mobile, library, worker/queue, data pipeline. Monorepos can have several; make one driver per deployable, or one driver with sections.
- **Launch**: the exact commands to install, build, and start; required env (`.env.example`, never `.env`); ports; seed data; how to know it's ready (a health URL, a log line).
- **Reset**: how to return to a clean state (db reset, fixture reload, temp dirs).
- **Auth**: how a test user logs in locally (seed user, dev token, auth bypass flag).
- **Features**: read the feature map (`.flow/features/`). If it's missing, build it first with the `feature-map` skill. Every feature file lists its entry points, sub-features, and proof. The driver must cover them all.

Ask the human only for what the repo cannot tell you (usually credentials for a local test user). Batch the questions.

## 2. Pick the driver pattern

See [references/patterns.md](references/patterns.md) for CLI, HTTP, browser (Playwright MCP or script), mobile, library, and pipeline recipes. Prefer scripts the agent runs through `evidence.sh` over prose instructions.

## 3. Write the skill

```
.claude/skills/verify-<repo>/
  SKILL.md          # ≤ 150 lines, the skill contract (below)
  scripts/up.sh     # start + wait-until-ready, idempotent; prints the base URL/port
  scripts/down.sh   # stop + clean
  scripts/<feature-id>.sh … # one scenario per feature in .flow/features/; drives EVERY entry
                            # point the feature lists; exits non-zero on failure
```

SKILL.md must have:
- frontmatter: `name: verify-<repo>`, and a description with triggers ("verify", "prove it works", "check the UI/API", "run the app").
- body metadata lines: `generated-by: flow-stack:make-verifier`, `generated-at: <date>`, `source-commit: <sha>`.
- after writing each scenario, set `scenario: bash .claude/skills/verify-<repo>/scripts/<feature-id>.sh` in that feature's file.
- sections: Launch · Reset · Scenarios (a pointer to `.flow/features/README.md`; the feature files are the source of truth) · Evidence (what artifact each produces: screenshot, response JSON, stdout) · Gotchas · `## Self-test` (one command: `scripts/up.sh && scripts/<core-feature>.sh && scripts/down.sh`).
- `Currency saved: attention: user-level proof instead of "tests pass".`

## 4. Prove it before accepting it

1. Run the self-test, then `../feature-map/scripts/features.sh run --all`. Every feature should pass and be marked verified. Features that can't be driven yet stay `unverified`, with the reason in their Gotchas.
2. **Teeth**: break the core feature on purpose (a one-line change in a temp git stash), run its scenario, and confirm it fails. Then restore. A driver that can't detect a broken feature is worthless.
3. Record both runs through `../verify/scripts/evidence.sh` when a task is active; otherwise show the output.

## 5. Hand over

Tell the human in ≤ 4 lines: which features it covers, what it can't cover yet (`features.sh list` → unverified), and that it's committed-ready at `.claude/skills/verify-<repo>/`. Re-running `/flow-stack:make-verifier` later refreshes it (§0); `tend` does the same across every generated skill.
