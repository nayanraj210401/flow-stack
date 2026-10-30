---
id: profile
title: Personal profile
owns: plugins/flow-stack/skills/profile/** plugins/flow-stack/templates/profile.md plugins/flow-stack/templates/presets/** .claude/skills/verify-flow-stack/scripts/profile.sh
entries: cli init.sh <preset> [--force] | cli check.sh | skill /flow-stack:profile | skill /flow-stack:setup
scenario: bash .claude/skills/verify-flow-stack/scripts/profile.sh
status: verified
verified: 2026-10-29 2d69405
---
# Personal profile

The user keeps one profile (rules, taste, repos, toolchain) that every session and skill reads; presets give a starting point.

## Sub-features
- profile.init · each preset (senior-backend, frontend-product, data-ml, learning-mode, solo-hacker, none) yields a profile check.sh accepts
- profile.noclobber · refuses to overwrite; --force keeps a timestamped backup
- profile.check · flags empty/oversized Rules, undated taste, missing repo paths, stale taste

## How to get to it
- CLI: `plugins/flow-stack/skills/profile/scripts/init.sh solo-hacker`, `check.sh`
- Skills: `/flow-stack:setup`, `/flow-stack:profile`

## Driving it
`.claude/skills/verify-flow-stack/scripts/profile.sh` runs in a throwaway toy repo with a sandboxed FLOW_STACK_HOME, drives every entry point above, and prints one ✓/✗ per sub-feature.

## Proof
- every preset → `0 structural problem(s)`
- absence: an existing profile is not overwritten without --force

## Gotchas
- Writes `$FLOW_STACK_HOME/profile.md` (default ~/.flow-stack). Never run init against your real home to test it.
