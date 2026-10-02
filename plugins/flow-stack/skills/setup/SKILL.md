---
name: setup
description: "Set up flow-stack: learn your existing toolchain and usage, adapt to it, create your profile, offer tools, forge census. /flow-stack:setup, or /flow-stack:setup adapt."
disable-model-invocation: true
---

# setup

Idempotent: a second run changes nothing that is already right. Ask before every install or settings edit. Paths are relative to this skill's base directory.

## 1. Detect

```bash
scripts/detect.sh
```

Show the human a compact table: what's present, what's missing, and what each missing tool would save (tokens, $, or attention).

## 2. Learn the existing toolchain and adapt

The human already has a way of working. Learn it before you change anything. The rules and the known-tool table are in [references/adapt.md](references/adapt.md); read it now.

1. **Inventory:** `scripts/inventory.sh` gives JSON: plugins (enabled, their skills, hook events, and MCP servers), user and project hooks, MCP servers, user and repo skills, the status line, the output style, CLAUDE.md files and imports, and CLI tools. Keep the JSON in a subagent or a scratch file; summarize, don't paste.
2. **Usage:** `scripts/usage.sh 30` counts which skills, slash commands, MCP servers, and subagent types they invoked in the last 30 days. Usage beats installation: shape flow-stack around what they use.
3. **Classify overlaps.** For each installed plugin, and each user or repo skill, match it against the capability keys in adapt.md. Unknown plugins: read the `description` in each of its SKILL.md files under `installPath`. Also check hooks on the same events as flow-stack's (SessionStart primers, PreToolUse on Bash/Read/Edit, Stop, PreCompact, Notification), the status line, and a notifier.
4. **Decide.**
   - Clear from the evidence (for example, rtk hook present → `token-saver: rtk`; existing status line → chain it; `.claude/skills/verify/` exists → `verify-driver`): decide and record.
   - Real overlaps the human uses (for example, their router `pstack:poteto-mode` vs `flow`, or their `/review` vs flow-stack's): ask, in one batched `AskUserQuestion`. Recommend based on the usage counts.
5. **Record.**
   - Write the `# Toolchain` lines in the profile (`- <key>: <provider> · <why>`). Show the diff first.
   - Write any global hook toggles to `~/.flow-stack/config.json`.
   - Save the fingerprint: `scripts/inventory.sh --fingerprint > ~/.flow-stack/toolchain.fp`.
6. **Tell the human** in ≤ 8 lines: what you found, what flow-stack will use from their setup, what it turned off, what it kept, and anything that might still overlap (for example two Stop hooks).

`/setup adapt` runs only this step (and step 1). SessionStart suggests it when the fingerprint changes: a plugin was installed or removed, or hooks, MCP servers, or the status line changed. On a re-run, diff the new inventory against the current Toolchain lines and propose only the changes.

If no profile exists yet, run step 3 first, then come back to record.

## 3. Profile (global, once)

If `~/.flow-stack/profile.md` is missing:
1. **Preset.** Ask which is closest: senior-backend, frontend-product, data-ml, learning-mode, solo-hacker, or none. One `AskUserQuestion`, with a one-line description of each (read `../../templates/presets/*.md`).
2. `../profile/scripts/init.sh <preset>`.
3. **Interview**, about 6 questions, batched where possible: role and what you mainly do (it also sets `board:` for `/flow-stack:board`: builder for someone writing code with agents, the default; lead for someone reviewing agents' and others' work across repos, which opens on all repos with decisions and debt first; solo for someone shipping alone, which shows tasks, shipped work, and spend; confirm the pick in one line); strong in / learning; how you like answers; hard rules (push, deploy, anything never OK); notification target (osascript, ntfy topic, off); skills to keep sharp (dojo); daily brief (`digest:` off, terminal, or page: a local HTML page of `/flow-stack:wrap`, nudged once a day at session start); review gate (`review_gate:` on, the default, means a PR reaches human review only after `ready.sh` passes; yolo skips it. A repo can override it in `.flow/config.json`).
4. **Repos.** `scripts/scan-repos.sh` lists the repos found. Show the ones with recent commits and let the human pick. Write a `## <name>` block for each, with its path, a one-line purpose (read its README), and its commands.
5. **Import.** Read `~/.claude/CLAUDE.md` and the project CLAUDE.md files of the chosen repos. Propose extracted items as a diff: hard constraints → Rules, preferences → Taste (with `src: CLAUDE.md`). Apply only what the human approves.
6. `../profile/scripts/check.sh` must pass.

If the profile exists, run `check.sh` and report problems only. If it has no `digest:`, `review_gate:`, or `board:` line, ask those questions once and add the lines.

## 4. Tools (optional, per tool)

Read [references/tools.md](references/tools.md). Offer only what the inventory shows is missing and what doesn't duplicate something they already have (for example, don't offer serena to someone whose token-saver is already covered and who never reads large files). For each missing tool the human wants: confirm the install command from the tool's README, run it, re-run `detect.sh` to confirm, and report. Offer the flow status line; chain an existing one rather than replacing it.

## 5. This repo (when inside a git repo)

1. `.flow/config.json`: create it from `../../templates/config.json` if missing, and fill `commands` from package scripts, the Makefile, and CI config. Run each command once to confirm it works (tests may be slow; ask first if more than a minute is likely).
2. **Quality gates before a PR.** Ask once: "Anything you run before opening a PR? (a script, an MCP scan, a manual check)". Offer what CI, pre-push hooks, and the usage counts suggest. Write each one to `ready` in `.flow/config.json`: `{"id": "e2e", "run": "npm run e2e"}` for a command ready.sh runs itself, or `{"id": "sec-scan", "do": "Run the semgrep MCP on the diff; done only with 0 new findings"}` for a step the agent performs and then records with `ready.sh record <id> done`. Run each `run` once to confirm it works.
3. `.gitignore`: add `.flow/ACTIVE`, `.flow/tasks/`, and `.flow/trail.jsonl` if missing.
4. **Forge census.** From `detect.sh`: which slots are filled (verify driver, run driver, gates, playbooks, map, repo taste). Offer the missing ones in one message, most valuable first:
   - no verify driver (neither `.claude/skills/verify-*/` nor `.claude/skills/verify/`, and no `verify-driver` Toolchain line) → `/flow-stack:make-verifier` (without one, verification is only unit tests)
   - no map → `/flow-stack:map`
   - no feature map (`.flow/features/`) → `/flow-stack:feature-map` (it lets verify run exactly the features a change touches)
   - deploy or migration configs present but no `.flow/gates.md` → `/flow-stack:make-gates`
   - a team repo without `.flow/taste.md` → offer `../../templates/team-taste.md`

## 6. Done

Summarize in ≤ 5 lines what was set up, what was skipped, and the one next step (usually "try `/flow-stack:flow` on a real task").
