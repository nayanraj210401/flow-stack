---
id: claims.stop
title: Claims check and notifications
owns: plugins/flow-stack/hooks/stop.sh plugins/flow-stack/hooks/notify.sh .claude/skills/verify-flow-stack/scripts/claims.stop.sh
entries: hook Stop | hook Notification | cli notify.sh "<msg>" | profile notify: notify_on:
scenario: bash .claude/skills/verify-flow-stack/scripts/claims.stop.sh
status: verified
verified: 2026-10-29 2d69405
---
# Claims check and notifications

If the agent's final message claims success without passing evidence since its last edit, it is sent back once. The human is notified when the agent needs them.

## Sub-features
- claims.stop.block · "done/fixed/works/tests pass" with no PASS newer than the last Edit blocks once
- claims.stop.pass · `~ assumed`, a fresh PASS, stop_hook_active, no claim, or `claims: false` let it stop
- claims.stop.notify · profile `notify: ntfy:<topic>` posts the message; `osascript` shows a macOS notification; `off` sends nothing

## How to get to it
- Automatic on Stop and Notification.
- CLI: `plugins/flow-stack/hooks/notify.sh "message"`

## Driving it
`.claude/skills/verify-flow-stack/scripts/claims.stop.sh` runs in a throwaway toy repo with a sandboxed FLOW_STACK_HOME, drives every entry point above, and prints one ✓/✗ per sub-feature.

## Proof
- `decision: block` with "flow claims check"; the ntfy capture server receives `/flowtest Claude needs your permission`
- absence: nothing received with `notify: off`

## Gotchas
- The claim regex is broad: "here is how it works" counts as a claim (sent back once, then allowed).
- osascript is not asserted (no way to observe it); ntfy is driven against a local server via NTFY_SERVER.
