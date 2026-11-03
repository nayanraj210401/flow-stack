---
id: plugin.install
title: Install the plugin
owns: .claude-plugin/marketplace.json plugins/flow-stack/.claude-plugin/plugin.json plugins/flow-stack/hooks/hooks.json .claude/skills/verify-flow-stack/scripts/plugin.install.sh
entries: cli /plugin marketplace add ~/Project/flow-stack | cli /plugin install flow-stack@flow-stack | cli claude plugin validate
scenario: bash .claude/skills/verify-flow-stack/scripts/plugin.install.sh
status: verified
verified: 2026-10-29 90da7be
---
# Install the plugin

A user adds the repo as a marketplace, installs flow-stack, and gets its skills, agents, and hooks in every session.

## Sub-features
- plugin.install.manifests · plugin and marketplace manifests pass `claude plugin validate` and agree on the version
- plugin.install.hooks · every event in hooks.json points at an existing, executable script that parses
- plugin.install.skills · every skill and agent has name + description frontmatter; relative links inside skills resolve

## How to get to it
- CLI (in Claude Code): `/plugin marketplace add ~/Project/flow-stack`, then `/plugin install flow-stack@flow-stack`, then `/reload-plugins`
- CLI (shell): `claude plugin validate plugins/flow-stack` and `claude plugin validate .`

## Driving it
`.claude/skills/verify-flow-stack/scripts/plugin.install.sh` runs in a throwaway toy repo with a sandboxed FLOW_STACK_HOME, drives every entry point above, and prints one ✓/✗ per sub-feature.

## Proof
- `Validation passed` for both manifests; one ✓ per hook script and per wired event
- absence: zero broken relative links (`.flow/artifacts/plugin.install/broken-links.txt` not created)

## Gotchas
- Installing copies the plugin to `~/.claude/plugins/cache/`; the running session keeps the old copy until update + `/reload-plugins`. The driver always tests the working tree.
- Skips `claude plugin validate` when the `claude` CLI is not on PATH.
