---
name: make-verifier
description: "Forge .claude/skills/verify-<repo>/, a driver that runs this app like a user (CLI, HTTP, browser) and proves itself. /flow-stack:make-verifier."
disable-model-invocation: true
---

# make-verifier: teach the agent to use this app like a user

Generic skills can't know how to prove *this* app works. This skill writes the driver that can. The output is read cold, mid-task, by an agent that has never seen the app. Write for that reader.

## 1. Interview the repo, not the human

Find out, with evidence (file:line):
- **App type(s)**: CLI, HTTP service, web UI, mobile, library, worker/queue, data pipeline. Monorepos can have several; make one driver per deployable, or one driver with sections.
- **Launch**: the exact commands to install, build, and start; required env (`.env.example`, never `.env`); ports; seed data; how to know it's ready (a health URL, a log line).
- **Reset**: how to return to a clean state (db reset, fixture reload, temp dirs).
- **Auth**: how a test user logs in locally (seed user, dev token, auth bypass flag).
- **Features**: the 5 to 15 user-facing capabilities, from routes, commands, and UI pages.

Ask the human only for what the repo cannot tell you (usually credentials for a local test user). Batch the questions.

## 2. Pick the driver pattern

See [references/patterns.md](references/patterns.md) for CLI, HTTP, browser (Playwright MCP or script), mobile, library, and pipeline recipes. Prefer scripts the agent runs through `evidence.sh` over prose instructions.

## 3. Write the skill

```
.claude/skills/verify-<repo>/
  SKILL.md          # ≤ 150 lines, the skill contract (below)
  scripts/up.sh     # start + wait-until-ready, idempotent; prints the base URL/port
  scripts/down.sh   # stop + clean
  scripts/<feature>.sh …   # one scenario per core feature; exits non-zero on failure
  features.md       # feature → scenario script → what it proves → known gaps
```

SKILL.md must have:
- frontmatter: `name: verify-<repo>`, and a description with triggers ("verify", "prove it works", "check the UI/API", "run the app").
- body metadata lines: `generated-by: flow-stack:make-verifier`, `generated-at: <date>`, `source-commit: <sha>`.
- sections: Launch · Reset · Scenarios (table from features.md) · Evidence (what artifact each produces: screenshot, response JSON, stdout) · Gotchas · `## Self-test` (one command: `scripts/up.sh && scripts/<core-feature>.sh && scripts/down.sh`).
- `Currency saved: attention: user-level proof instead of "tests pass".`

## 4. Prove it before accepting it

1. Run the self-test. It must pass on the current code.
2. **Teeth**: break the core feature on purpose (a one-line change in a temp git stash), run its scenario, and confirm it fails. Then restore. A driver that can't detect a broken feature is worthless.
3. Record both runs through `../verify/scripts/evidence.sh` when a task is active; otherwise show the output.

## 5. Hand over

Tell the human in ≤ 4 lines: what the driver covers, what it can't cover yet (the gaps from features.md), and that it's committed-ready at `.claude/skills/verify-<repo>/`. `tend` keeps it honest as the code changes.
