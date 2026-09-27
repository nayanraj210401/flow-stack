---
name: make-runner
description: "Forge .claude/skills/run-<repo>/ with verified install, start, seed, reset, and stop commands. /flow-stack:make-runner."
disable-model-invocation: true
---

# make-runner

## Discover (with file:line evidence)

Package scripts, the Makefile, docker-compose, Procfile, CI workflows (the most honest source: CI must actually run it), the README's setup section, `.env.example`, `.tool-versions`, `.nvmrc`, and `rust-toolchain`.

## Write `.claude/skills/run-<repo>/SKILL.md` (≤ 100 lines)

- frontmatter `name: run-<repo>`, with description triggers ("run", "start the app", "set up dev env", "reset db").
- metadata: `generated-by: flow-stack:make-runner`, `generated-at`, `source-commit`.
- sections: **Prereqs** (versions) · **Install** · **Env** (variables from `.env.example`, which are required, and safe local defaults; never real secrets) · **Start** (the command, port, and ready signal) · **Seed / reset** · **Stop** · **Common failures** (the error → the fix, found while verifying) · `## Self-test` (install → start → ready check → stop).
- `Currency saved: tokens + minutes: no rediscovery each session.`

## Verify

Run every command from a clean state, in order. Fix the skill until the self-test passes. Record each failure you hit and its fix under Common failures; that section is the valuable part.

Also fill `.flow/config.json` `commands.run` and `commands.test` if they're empty.
