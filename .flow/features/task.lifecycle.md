---
id: task.lifecycle
title: Manage flow tasks
owns: plugins/flow-stack/skills/flow/scripts/task.sh plugins/flow-stack/templates/DECISIONS.tsv plugins/flow-stack/templates/config.json .claude/skills/verify-flow-stack/scripts/task.lifecycle.sh
entries: cli task.sh new|active|dir|switch|close|list|decide|estimate | skill /flow-stack:flow
scenario: bash .claude/skills/verify-flow-stack/scripts/task.lifecycle.sh
status: verified
verified: 2026-10-26 b6cdf74
---
# Manage flow tasks

Each piece of work gets a task folder under .flow/tasks/ with its intent, slices, evidence, and decisions; one task is active at a time.

## Sub-features
- task.lifecycle.new · creates INTENT/SLICES/DECISIONS/EVIDENCE/PLAYBOOK from templates, makes it active, adds .gitignore lines and .flow/config.json
- task.lifecycle.guard · refuses an existing slug and non-kebab-case slugs
- task.lifecycle.switch · `switch`/`list`/`active` move and show the active task (`*` in list)
- task.lifecycle.log · `decide` appends a DECISIONS.tsv row; `estimate` writes ESTIMATE
- task.lifecycle.close · clears ACTIVE, keeps the folder

## How to get to it
- CLI: `plugins/flow-stack/skills/flow/scripts/task.sh new <slug> [playbook]`
- Skill: `/flow-stack:flow` calls it when a task starts

## Driving it
`.claude/skills/verify-flow-stack/scripts/task.lifecycle.sh` runs in a throwaway toy repo with a sandboxed FLOW_STACK_HOME, drives every entry point above, and prints one ✓/✗ per sub-feature.

## Proof
- the five files exist and INTENT.md has no `{{slug}}`; `task.sh active` prints the slug
- absence: after `close`, `task.sh active` is empty and `task.sh dir` fails

## Gotchas
- Runs in whatever git repo the cwd is in; the driver uses a throwaway toy repo.
