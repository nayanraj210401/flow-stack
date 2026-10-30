---
id: multi.repo
title: Multi-repo tasks
owns: plugins/flow-stack/hooks/roots.sh plugins/flow-stack/skills/flow/scripts/task.sh .claude/skills/verify-flow-stack/scripts/multi.repo.sh
entries: cli task.sh new <slug> --workspace <name> | --repos a,b | profile # Workspaces, # Repos role: | hook edit-guard/guard across repos
scenario: bash .claude/skills/verify-flow-stack/scripts/multi.repo.sh
status: verified
verified: 2026-10-26 b6cdf74
---
# Multi-repo tasks

One flow task spans several repos from a profile workspace; the task folder lives in the primary repo and every guard holds in every repo.

## Sub-features
- multi.repo.home · the task lives in the workspace's primary repo; others get an ACTIVE pointer
- multi.repo.fence · a slice's repo: names where edits may land; edits elsewhere are denied, from any cwd
- multi.repo.seals · seals are repo-qualified (<repo>:<path>) and verified across repos
- multi.repo.evidence · evidence blocks record their repo
- multi.repo.close · close from any repo clears every pointer

## How to get to it
- task.sh new <slug> feature --workspace <name>

## Driving it
bash .claude/skills/verify-flow-stack/scripts/multi.repo.sh

## Proof
All ✓ and `== multi.repo · PASS`.

## Gotchas
Repo names are the profile's # Repos names, not folder names.
