---
name: make-playbook
description: "Forge a repo playbook (.flow/playbooks/) from past traces and git history for a workflow this repo repeats. /flow-stack:make-playbook."
disable-model-invocation: true
---

# make-playbook: capture how this repo does things

## 1. Find examples (at least 2, ideally 3+)

- Past traces: `.flow/tasks/*/TRACE.md` and `trail.jsonl` for tasks of this kind.
- git: `git log --diff-filter=A --name-only -- <typical path>` to find commits that added similar things. Read 2 or 3 of their diffs in full.
- PRs: `gh pr list --search "<keyword>" --state merged`.

## 2. Extract the invariant steps

Which files always change together (route + handler + schema + test + docs)? What order? Which commands run (codegen, migration create)? What did reviewers repeatedly flag? Those become checks.

## 3. Write `.flow/playbooks/<kebab-name>.md`

```
# Playbook: <name>
Use when: <one line: flow's classifier matches on this>
generated-by: flow-stack:make-playbook · generated-at: <date> · source-commit: <sha>
Examples: <commit/PR refs>
Principles: <which apply>

1. <step> · files: <globs> · check: <command>
2. …
Gates: <which steps need the human>
Fence template: <globs to use for slices>
Checks every instance needs: <list, e.g. "OpenAPI spec validates", "migration is reversible">
## Self-test
<command that validates a dry run of the playbook, e.g. codegen + typecheck on a scratch instance>
```

## 4. Validate

Walk a real or scratch instance through the playbook (on a throwaway branch) and fix the steps that don't hold. Show the human the playbook (≤ 30 lines) for approval before committing.
