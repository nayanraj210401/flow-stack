---
name: make-skill
description: "Forge any repo-specific or personal skill with a self-test and staleness metadata. /flow-stack:make-skill."
disable-model-invocation: true
---

# make-skill

## Decide scope and home

- **Repo, shared with the team**: `<repo>/.claude/skills/<name>/`.
- **Personal, all repos**: `~/.claude/skills/<user>-<name>/`.
- **Not a skill**: a one-off belongs in a note. A rule belongs in the profile. A fixed script belongs in the repo.

## Gather

The procedure's real source: the human's explanation, a runbook doc, past traces, shell history they share, or the CI config. Run each step once to confirm it works as written.

## Write (the skill contract, see `../flow/references/conventions.md`)

- A frontmatter `description` with what it does and when to use it, with concrete trigger phrases.
- Metadata lines: `generated-by: flow-stack:make-skill`, `generated-at`, `source-commit` (repo skills).
- `Currency saved:` tokens, $, or attention, and how.
- Steps as imperative commands. Scripts in `scripts/` for anything deterministic (principle-build-the-lever).
- Gates: which steps are irreversible and need the human.
- `## Self-test`: one command that proves the skill still works (a dry run, `--help`, or a read-only check).
- ≤ 150 lines; detail in `references/`.
- Prose passes `unslop`.

## Verify

Run the self-test. Then have a fresh subagent follow the skill cold on a harmless instance, and fix wherever it stumbled. Show the human the skill for approval.
