---
id: feature.map
title: Feature map
owns: plugins/flow-stack/skills/feature-map/** .claude/skills/verify-flow-stack/scripts/feature.map.sh
entries: cli features.sh list|impact|run|mark|stale|coverage|check|subs|index|new | skill /flow-stack:feature-map
scenario: bash .claude/skills/verify-flow-stack/scripts/feature.map.sh
status: verified
verified: 2026-10-26 b6cdf74
---
# Feature map

The repo keeps one file per user-facing feature; a diff maps to the features it touches, and each feature's scenario proves it.

## Sub-features
- feature.map.check · lints ids, fields, sections, globs, and template placeholders
- feature.map.impact · maps changed/untracked files to features and lists unowned ones
- feature.map.run · runs scenarios through evidence.sh; PASS → verified + stamp, FAIL → broken, none → says so
- feature.map.stale · features whose owned code changed since the stamp; --write marks them
- feature.map.coverage · unowned code, missing scenarios, dead globs
- feature.map.index · regenerates README.md; new scaffolds from the template

## How to get to it
- CLI: `plugins/flow-stack/skills/feature-map/scripts/features.sh <cmd>`
- Skill: `/flow-stack:feature-map`; flow, verify, tend call it

## Driving it
`.claude/skills/verify-flow-stack/scripts/feature.map.sh` runs in a throwaway toy repo with a sandboxed FLOW_STACK_HOME, drives every entry point above, and prints one ✓/✗ per sub-feature.

## Proof
- `feature map ok (2 features)`, `calc.add\tsrc/calc.sh`, `feat:calc.add · PASS` with `status: verified`
- absence: export.csv not in impact when only calc changed

## Gotchas
None known.
