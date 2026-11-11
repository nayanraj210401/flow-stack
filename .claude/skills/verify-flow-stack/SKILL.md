---
name: verify-flow-stack
description: "Prove flow-stack works the way a user meets it: drive every hook with Claude Code's real JSON payloads and every script in a throwaway toy repo, one scenario per feature in .flow/features/. Use for \"verify\", \"prove it works\", \"check the hooks\", \"does the guard still block X\", \"run the plugin\", or before claiming a change to hooks/, skills/*/scripts/, or templates/ is done."
---

# verify-flow-stack

generated-by: flow-stack:make-verifier
generated-at: 2026-10-27
source-commit: d7b1913

Currency saved: attention: user-level proof instead of "tests pass".

flow-stack has no server and no UI. A user meets it in three ways, and the driver uses all three:
1. **Hooks.** Claude Code pipes JSON into `plugins/flow-stack/hooks/*.sh` and reads the decision from stdout. The scenarios pipe the same JSON (`lib.sh`: `pre`, `bashcmd`, `edit`) and assert on `permissionDecision` or `decision`.
2. **Scripts.** Skills run `task.sh`, `seal.sh`, `evidence.sh`, `probe.sh`, `features.sh`, and others. The scenarios call them in a toy git repo.
3. **Skills (prose).** Only a model can follow a skill, so the paid evals prove this part (`skills.behavior`, no scenario).

Every scenario tests the **working tree** (`plugins/flow-stack/`), not the installed copy in `~/.claude/plugins/cache/`.

## Launch

```bash
bash .claude/skills/verify-flow-stack/scripts/up.sh     # checks bash git jq perl shasum python3 curl; parses every script; prints the plugin root
```
There is nothing to start. `up.sh` is idempotent and exits non-zero if a tool is missing or a script fails to parse.

## Reset

Each scenario builds its own sandbox, so no reset step is needed:
- a `mktemp -d` toy repo from `plugins/flow-stack/evals/_lib/toy.sh` (`toy_repo`, `toy_task`, `toy_slice`, `toy_mul_check`, `toy_features`),
- `FLOW_STACK_HOME`, `CLAUDE_CONFIG_DIR`, and `FLOW_CLAUDE_JSON` pointed into the sandbox, so your real `~/.flow-stack` and `~/.claude` are never read or written.

The sandbox is deleted on exit. `scripts/down.sh` removes sandboxes that a killed run left behind.

## Scenarios

Source of truth: [.flow/features/README.md](../../../.flow/features/README.md). Each feature file lists its entry points and sub-features, and its `scenario:` line points here.

```bash
S=plugins/flow-stack/skills/feature-map/scripts/features.sh
$S run --impacted          # after a change: only the features the diff touches
$S run --all               # everything (~20 s); skills.behavior reports NO SCENARIO by design
bash .claude/skills/verify-flow-stack/scripts/<feature-id>.sh   # one feature, verbose ✓/✗ lines
```

| Script | What the user sees it do |
|---|---|
| `guard.shell.sh` | deny/ask on destructive Bash, `.flow/gates.md`, .env reads, toggle, fail-open |
| `seal.sh` · `slice.fence.sh` · `slice.gate.sh` | sealed checks need the human; edits stay in the fence; `done` needs proofs |
| `task.lifecycle.sh` · `evidence.record.sh` · `probe.teeth.sh` · `blind.checks.sh` | task folders, evidence rows and sigs, TEETH/TOOTHLESS, held-out checks |
| `session.context.sh` · `trail.circuit.sh` · `claims.stop.sh` | primer, anchor, handoff; redacted trail and circuit breaker; claims check and ntfy |
| `feature.map.sh` · `profile.sh` · `setup.toolchain.sh` · `budget.statusline.sh` · `plugin.install.sh` | the remaining CLIs and the install surface |

To add a scenario: copy the closest script, `. lib.sh; sandbox <id>`, then assert with `expect <hook> <json> <allow|deny|ask|block> <label>`, `check`, `fails`, `sees`, or `ok`/`bad`. End with `finish`. Set `scenario:` in the feature file.

## Evidence

Each scenario prints one `✓`/`✗` line per assertion, then `== <id> · PASS|FAIL`, and exits non-zero on any ✗. Artifacts go to `${FLOW_ARTIFACTS:-.flow/artifacts}/<id>/`:
- `decisions.tsv`: every hook case, with its label, the decision it got, and the raw stdout. This is the proof for all hook features.
- `stderr.log`: hook stderr. A hook that fails open leaves its trace here.
- Per feature: `EVIDENCE.md` (evidence, probe, slice), `trail.jsonl` + `trace-stats.txt`, `session-start.*.txt` + `HANDOFF.auto.md`, `inventory.json`, `ntfy.txt`, `features/`, `profile.md`, `broken-links.txt` (only when links break).

When a task is active, run the scenarios through `features.sh run` or `verify/scripts/evidence.sh "feat:<id>" "<cmd>"` so the result lands in EVIDENCE.md.

## Gotchas

- **Tests the working tree only.** A passing run says nothing about the installed copy. Reinstall and run `/reload-plugins` before you trust a live session.
- **Hook stdout is the contract.** `hook()` captures stdout only. Stderr goes to `stderr.log`, because Claude Code ignores it for decisions.
- **No output means allow.** An empty stdout counts as `allow`. A hook that crashes and fails open also looks like `allow`, so the deny/ask cases catch that and the allow cases can't.
- **Not driven:** `guard.shell.pkgcheck` (needs npm/PyPI), `budget.statusline.cost` (needs ccusage), osascript notifications (can't be observed; ntfy is driven through a local capture server instead), and `skills.behavior` (paid model evals; the command is in its feature file).
- **The claims regex is broad.** "here is how it works" counts as a success claim. `claims.stop.sh` avoids that phrase on purpose.
- **macOS first.** The plugin targets bash 3.2 and BSD tools. The driver uses `perl -pi`, not `sed -i`, so it also runs on GNU.
- `claims.stop.sh` needs a free localhost port (random 20000–39999) for the ntfy capture server.

## Self-test

```bash
bash .claude/skills/verify-flow-stack/scripts/up.sh && bash .claude/skills/verify-flow-stack/scripts/guard.shell.sh && bash .claude/skills/verify-flow-stack/scripts/down.sh
```
