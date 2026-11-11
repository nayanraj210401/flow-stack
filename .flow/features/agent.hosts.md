---
id: agent.hosts
title: Agent hosts (herdr, Orca, cmux): phase in the sidebar, host-owned pings, workers as panes
owns: plugins/flow-stack/skills/delegate/scripts/dispatch.sh plugins/flow-stack/hooks/host.sh .claude/skills/verify-flow-stack/scripts/agent.hosts.sh
entries: hook UserPromptSubmit|PostToolUse|SessionEnd host.sh (host push) | hook Notification notify.sh | cli inventory.sh (.hosts) | cli delegate/scripts/dispatch.sh start|wait|cleanup|gc | /flow-stack:setup adapt
scenario: bash .claude/skills/verify-flow-stack/scripts/agent.hosts.sh
status: verified
verified: 2026-10-27 b6cdf74
---
# Agent hosts

herdr, Orca and cmux run Claude Code in panes. Inside one, the session that owns a task reports it, slice and open gates to the host, flow's desktop ping steps aside for the host's, setup detects the host and offers what connects it, and delegate can run each worker as a visible herdr pane.

## Sub-features
- agent.hosts.detect · flow_host (hooks/lib.sh): herdr, orca, cmux, conductor or none from env, trusted only while the host's socket or CLI answers
- agent.hosts.push · host.sh: herdr pane tokens flow_task/flow_slice/flow_gates, Orca worktree comment (+ unread on a new gate), cmux set-status; once per change; task owner only; background, ~1s cap
- agent.hosts.clear · no active task, SessionEnd, SessionStart:clear clear the label once and remove hosts/<sid>
- agent.hosts.notify · notify.sh skips osascript inside a host; ntfy and notify_on: all unchanged; hooks.host: false restores it
- agent.hosts.setup · inventory.sh .hosts (herdr version, Claude integration, sidebar rows, herdr-projects; orca; cmux); fingerprint moves only with a host; adapt.md and tools.md offers
- agent.hosts.dispatch · dispatch.sh (delegate: herdr-panes): worktree + claude pane + worker brief, lanes/<lane>/HOST record, flow-thread marker (push waits like --auto), cleanup of clean recorded lanes only

## How to get to it
Run Claude inside herdr (`herdr`), Orca or cmux with flow-stack 1.0.0+. Add `$flow_task $flow_slice $flow_gates` to herdr's `[ui.sidebar.agents].rows`, or let `/flow-stack:setup adapt` offer it. Visible workers: `- delegate: herdr-panes` in the profile's `# Toolchain`.

## Driving it
The scenario stubs herdr, orca, cmux, osascript and curl on PATH (each logs its argv) with real unix sockets, in a toy repo. Sections: `push herdr orca cmux notify setup dispatch`.

## Proof
Scenario for every sub-feature. Live: C5 in a real herdr pane (human-judged). Orca is stub-tested only.

## Gotchas
- Pushes run in the background; the scenario waits up to 3s for them.
- Orca and cmux have no expiry for status text.
- `.claude/` is gitignored: workers copy the verify scenarios into their worktree before running them.
