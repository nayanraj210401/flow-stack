---
id: setup.toolchain
title: Toolchain discovery for setup
owns: plugins/flow-stack/skills/setup/** .claude/skills/verify-flow-stack/scripts/setup.toolchain.sh
entries: cli detect.sh | cli inventory.sh [--fingerprint] | cli scan-repos.sh [dir] | cli usage.sh [days] | skill /flow-stack:setup
scenario: bash .claude/skills/verify-flow-stack/scripts/setup.toolchain.sh
status: verified
verified: 2026-10-26 b6cdf74
---
# Toolchain discovery for setup

Setup looks at what the user already has (tools, plugins, hooks, MCP servers, status line, repos, habits) so flow-stack adapts instead of clashing.

## Sub-features
- setup.toolchain.detect · one row per helper tool, MCP server, status line, and repo artifact
- setup.toolchain.inventory · JSON of plugins, hooks, MCP names, skills, CLAUDE.md imports; env and MCP values never printed
- setup.toolchain.fingerprint · changes when plugins, hooks, MCP, or status line change (drives the SessionStart re-adapt hint)
- setup.toolchain.scan · lists git repos with guessed test/run commands
- setup.toolchain.usage · counts skills, MCP servers, and subagents from recent transcripts

## How to get to it
- Skill: `/flow-stack:setup` runs these.
- CLI: `plugins/flow-stack/skills/setup/scripts/<script>.sh`

## Driving it
`.claude/skills/verify-flow-stack/scripts/setup.toolchain.sh` runs in a throwaway toy repo with a sandboxed FLOW_STACK_HOME, drives every entry point above, and prints one ✓/✗ per sub-feature.

## Proof
- inventory JSON has `status_line:"echo hi"`, `env_keys:["MY_TOKEN"]`, `mcp.user:["serena"]`
- absence: `s3cr3t-value` and `mcp-secret` never appear

## Gotchas
- Reads CLAUDE_CONFIG_DIR / FLOW_CLAUDE_JSON; the driver points both at fakes.
