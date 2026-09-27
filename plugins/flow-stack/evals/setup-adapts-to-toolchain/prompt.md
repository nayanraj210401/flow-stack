---
description: setup's adapt step learns an existing toolchain and usage, then records delegations instead of duplicating tools.
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Edit, Write, Bash, Skill]
---

Run /flow-stack:setup adapt against the fake toolchain in this workspace. Point every setup script at it by prefixing commands with:
CLAUDE_CONFIG_DIR=$PWD/fake-claude FLOW_CLAUDE_JSON=$PWD/fake-claude.json FLOW_STACK_HOME=$PWD/fh

My profile is fh/profile.md. I'm away: don't ask me anything; where you'd ask, pick what the usage data supports and mark it "(assumed, confirm)". Write the Toolchain section and fh/toolchain.fp. Don't install anything.
