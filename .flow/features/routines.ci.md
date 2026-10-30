---
id: routines.ci
title: Routines on GitHub Actions
owns: plugins/flow-stack/skills/make-routines/** .claude/skills/verify-flow-stack/scripts/routines.ci.sh
entries: skill /flow-stack:make-routines | cli skills/make-routines/scripts/routines.sh list|add|schedule|render|check | file .github/routines/<name>.md | file .github/workflows/flow-<name>.yml
scenario: bash .claude/skills/verify-flow-stack/scripts/routines.ci.sh
status: verified
verified: 2026-10-29 90da7be
---
# Scheduled routines on GitHub Actions

Cloud routines can't load plugins, so flow-stack's hooks don't run there. make-routines writes a routine (prompt + schedule) and renders a GitHub Actions workflow that installs the plugin through claude-code-action and runs `/flow-stack:flow --auto ship` on it.

## Sub-features
- routines.ci.add · `add <name>` writes `.github/routines/<name>.md` from the self-create / self-heal template or a stub, refuses to clobber without --force, rejects bad names
- routines.ci.profile · a CI profile from a preset with notify off, loaded via FLOW_STACK_HOME under $RUNNER_TEMP, not the checkout
- routines.ci.render · the workflow takes cron, timeout, labels, auth (oauth | api-key) from the routine's frontmatter; installs the flow-stack marketplace and plugin
- routines.ci.check · `check` fails when a workflow differs from a fresh render (stale or hand-edited)
- routines.ci.trigger · `trigger: pull_request` runs on non-draft, same-repo PRs, one run per PR; `schedule` takes a cron
- routines.ci.grants · `grants` picks the write scopes; contents implies `--auto ship`, anything else runs `--auto`
- routines.ci.review · the review template spawns flow-stack:reviewer and posts one comment, never approves or pushes
- routines.ci.pin · `flow_ref` pins the marketplace to a tag or branch; unset installs the default branch fresh each run
- routines.ci.list · `list` prints the template catalog with trigger and when to use it
- routines.ci.schedule · each scheduled routine has its own cron: `add --cron` sets it, `schedule <name> <cron>` changes it and re-renders; refuses pull_request routines and malformed crons without writing

## How to get to it
- /flow-stack:make-routines → routines.sh add

## Driving it
bash .claude/skills/verify-flow-stack/scripts/routines.ci.sh

## Proof
All ✓ and `== routines.ci · PASS`; the rendered .github/ lands in artifacts.

## Gotchas
The scenario proves the rendered files, not a live Actions run: the first real run needs the secret and the Claude GitHub App (see the skill's Human steps). Ruby's YAML reads the key `on` as true.
