---
id: flow.pane
title: /flow-pane (slices, gates with buttons, leads)
owns: plugins/flow-stack/skills/flow/scripts/status.sh plugins/flow-stack/skills/flow/scripts/task.sh plugins/flow-stack/hooks/register.tsx .claude/skills/verify-flow-stack/scripts/flow.pane.sh
entries: cmd /flow-pane | ui Pane flow-pane Approve/Reject | cli task.sh gate <n> approve|reject | cli status.sh --full
scenario: bash .claude/skills/verify-flow-stack/scripts/flow.pane.sh
status: verified
verified: 2026-10-27 b6cdf74
---
# /flow-pane

## Sub-features
- flow.pane.data · status.sh --full: slices with status and last verdict, open gates (decided ones hidden), leads; control characters stripped
- flow.pane.gate · task.sh gate <n> approve|reject: decided line under the gate, DECISIONS.tsv row; refuses decided, missing, or other verdicts
- flow.pane.ui · /flow-pane opens the pane; Approve/Reject runs task.sh gate and tells Claude (plugin test)

## How to get to it
Install 0.9.0+ (or `claude --plugin-dir plugins/flow-stack`), open a flow task, type `/flow-pane`.

## Driving it
- data and decisions: the scenario above (toy repo; status.sh --full, approve and reject).
- pane and buttons: `claude plugin test plugins/flow-stack` (engine test kit).

## Proof
Scenario + `claude plugin test plugins/flow-stack`.

## Gotchas
- status.sh adds `--full` only while the pane is open; the band polls the short form.
- The guard denies any Bash command whose text names the decision subcommand, so decide from the pane or the scenario, never an ad-hoc shell line.
- The pane draws only in terminal + Desktop; `-p` and VS Code chat draw nothing.
