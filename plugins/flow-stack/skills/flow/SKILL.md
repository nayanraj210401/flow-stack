---
name: flow
description: "flow-stack's operating mode and orchestrator. Invoke BEFORE planning or writing code for a new feature, multi-file change, design choice, refactor, optimization, or unknown bug; also for \"how would you approach\", \"plan this\", \"/flow resume\", and long or unattended runs (\"going to bed\", \"run until done\"). Routes to a playbook and runs intent → approach → slices → prove with human gates."
---

# flow

The operating mode for work that matters. It decides **which skill runs when**, **how much ceremony a task gets**, **when the human is asked**, and **how subagents are used**. Playbooks in `playbooks/` do the step-by-step work. File formats live in [references/conventions.md](references/conventions.md); read it once per session before writing task files. Paths below are relative to this skill's base directory.

Three currencies: tokens (cheap, capped), dollars (moderate), the human's attention (the most expensive). Spend cheap to save expensive.

## 1. Non-negotiables: situation → skill

| When | Do |
|---|---|
| Any code change | Name the data shape first (principle-model-the-domain). Run the subtract scan before adding (principle-subtract-before-add). |
| Change touches existing behavior | `../feature-map/scripts/features.sh impact` → the features it touches. Their scenarios are part of "done". |
| Code you haven't read | `how`. For a history question, or "is this odd on purpose?", use `why` before changing it. |
| Acceptance criteria come from a ticket | `intent` §1a: one evidence-only fact-check by the advocate. Confirmed discrepancies go to the intent gate; nothing else is argued. |
| Choosing an approach | `challenge` (the advocate designs blind, and the null option is weighed). No approach is locked in without it, except when rigor is `lean` or the task is one slice. |
| A check passes | `probe`. TOOTHLESS means strengthen the check. |
| Marking a slice done | `task.sh slice <id> done`, the proof gate. Never edit SLICES.md for it. |
| Saying done, fixed, or works | `verify`, then `claims`. `✓` only with evidence newer than the last edit. |
| Two failed fixes on the same thing | principle-attack-the-premise, then `challenge`. The circuit hook forces this at 3. |
| About to ask the human | `gate`. If running something could answer it, run it instead. Batch what's left into one message. |
| Irreversible or outward-facing action | Always a GATE: push, merge, deploy, publish, delete data, send messages, spend money, `.flow/gates.md` entries. |
| A diff is ready | `deslop` (code), `unslop` (prose), then `review`, and `tour` for the human. Then `../review/scripts/ready.sh`: a non-draft PR is refused until it stamps HEAD (unless `review_gate: yolo`). |
| Taking a shortcut | `debt`. |
| Context past the handoff threshold | `handoff` at the next slice boundary. |
| A reply longer than 5 lines | `brief`. Detail goes to a file. |
| The same correction twice | `reflect` at close, and prefer a lint, test, or hook (principle-encode-in-structure). |
| No verify driver or feature map, and the change is user-visible | Say so in one line and suggest `/flow-stack:make-verifier` or `/flow-stack:feature-map`. Don't improvise a driver. |

**No is an acceptable answer.** When the human proposes an approach, give your real judgment. If a simpler path or the null option wins, show the `challenge` table. Agreeing is not the default.

## 2. Classify and route (10 seconds, in your head)

| Request | Route | Ceremony |
|---|---|---|
| Question about code, history, or behavior | `playbooks/investigate.md` | none: a cited brief answer |
| One contained edit with an obvious check | edit → `verify` (its impacted feature scenarios included) | none |
| "Not sure what to build" / taste unknown | `playbooks/spike.md` | throwaway branch |
| Bug with unknown cause | `playbooks/bug.md` | task folder |
| New behavior, multi-file, contract change | `playbooks/feature.md` | task folder |
| Rename, migration, sweep | `playbooks/refactor.md` | task folder |
| Make a metric better | `playbooks/optimize.md` | task folder |
| Spans days or sessions | `playbooks/multi-session.md` | task folder + handoffs |
| Spans several repos (a ticket touching a profile workspace) | the matching playbook, opened with `task.sh new <slug> <playbook> --workspace <name>` | task folder in the primary repo; one slice per repo change; one PR per repo |
| No playbook fits: ambitious, mixed kinds, or reviewed after stepping away | `playbooks/compose.md` | task folder, rigor +1 |
| Source is a ticket someone else wrote | the matching playbook; `intent` fact-checks the ticket (§1a) | as that playbook |
| Matches `.flow/playbooks/*.md` | that repo playbook | as it says |

**Resolve before routing.**
1. **Toolchain.** The profile's `# Toolchain` (injected at start) may map a capability to the user's own tool. That provider replaces the matching flow-stack skill (see Delegation in conventions.md). If `router` names another tool and the human invoked flow anyway, run flow for this task.
2. **Repo slots.** A repo playbook beats a built-in one when its "Use when" line matches. Check for the verify driver (`.claude/skills/verify-*/` or `verify/`), the run driver, and the feature map (`.flow/features/`).

Say the route in one line: `flow: feature · task rate-limit · rigor standard · features: auth.login, billing.invoice`.

## 3. Rigor: scale the ceremony

The profile's `rigor:` sets the default. The human overrides per task: "quick" means lean; "go strict" means strict.

| Step | lean | standard | strict |
|---|---|---|---|
| intent interview | ≤ 2 questions | as needed | as needed |
| blind checks (checker agent) | skip | when a contract changes | always |
| challenge (advocate agent) | on request, or when the circuit trips | multi-slice features and refactors | every task-folder task |
| review (reviewer agent) | diff > 300 lines | one reviewer | one per area, in parallel |
| impacted feature scenarios | touched features | touched features | every feature |
| evidence, seal, probe, slice gate | on (bash, 0 tokens) | on | on |
| trace / reflect | on request | at close | at close |

## 4. Open the task and run the playbook

```bash
scripts/task.sh new <kebab-slug> <playbook> --goal "<outcome, user's view>" --check "<command that proves it>"
scripts/task.sh estimate <usd> <ctx_pct> <human_min>
```

The goal and C1 are written at birth; `intent` refines them. `evidence.sh C1` runs exactly that command, and the Stop hook accepts a success claim only after a passing check. Copy the playbook's steps into the todo list verbatim. A step you skip stays there as `skip: <reason>`.

Base the forecast on the change size and the profile's `# Calibration`. If the human-minutes estimate is more than a third of `attention.review_minutes_per_day`, say so and offer to cut scope. Then read the playbook and follow it. Every playbook is built from these phases:

| Phase | Skill | Output |
|---|---|---|
| Understand | `map`, then `how` / `why`; `features.sh impact` on the area | cited notes; the feature IDs in play |
| Intent | `intent` | INTENT.md, with checks bound to feature and sub-feature IDs; sealed with `seal` |
| Approach | `challenge` | INTENT.md `## Approaches` |
| Slice | `slice` | SLICES.md; fences seeded from the features' `owns:` |
| Execute | `loop` per slice, or `delegate` | EVIDENCE.md |
| Prove | `verify` (the checks + impacted feature scenarios + blind checks), `review`, `deslop`, `unslop`, `debt` | verdicts; feature files marked verified |
| Present | `tour` (grouped by feature), `claims`, `dojo` if on | one short message |
| Close | `trace`, `reflect`, `feature-map` update if a feature was added or changed | TRACE.md, profile diffs, feature files |

**Gates.** There are three fixed points: intent, merge/push, and profile diffs. Beyond those, only what `gate` says. Everything else proceeds and is logged: `scripts/task.sh decide agent yes "<decision>" "<why>" "<evidence>"`.

**Principles.** Read `../principles/references/principle-<name>.md` the first time a principle shapes a decision. Name it in the reply when it changed what you did.

## 5. Autonomy

| Mode | Trigger | Behavior |
|---|---|---|
| **Interactive** (default) | — | Proceed on reversible work. Stop at gates. |
| **Autonomous** | `--auto` anywhere in a prompt (`--no-auto` ends it), "going to bed", "run until done", "don't stop", `/loop` | Never block on a question. Intent and seal approval are yours to give; log them with `who=agent`. With `--auto` the hooks enforce it for the session: every ask is denied with "queue it", and so are AskUserQuestion, push, and PR commands. Put open gates in `.flow/tasks/<slug>/GATES.md` (question, options, recommendation), pick the recommended reversible option, log it with `who=agent`, and keep going on anything the gate doesn't block. **Irreversible actions still never happen.** They wait in GATES.md. At the end, notify, then `trace` plus a HANDOFF that lists the GATES.md items first. |
| **Quick** | "quick", "just do it" | rigor `lean` for this task. The hooks stay on. |

## 6. Subagents

Spawn one when it saves the human's attention or the main context: bulk reading (> ~5 files), independent slices, reviews, the advocate, blind checks.
- **Pick the agent.** Use `advocate`, `checker`, `reviewer`, or `worker` for their named jobs, and `flow-agent` for any other delegate. It loads flow itself, so the rules follow it.
- **Brief with pointers**: the task folder path, `file:line` references, and the exact question or scope. Don't paste context. Say what to return and in what shape.
- **Choose the model per role** from the profile's `budget:` and pass it as the Agent call's `model`: `design_model` for reviewer, advocate, and a contested design; `build_model` for workers, checker, and flow-agent; `subagent_model` for exploration. The agents pin no model, so without one the subagent inherits the session's model (or your router picks).
- **Isolate writers.** Every file-writing delegate gets its own worktree. Never run the suite in a worktree a delegate still holds.
- **Run independent agents in the background**, and do unblocked work meanwhile.
- **You own the result.** Review the diff yourself and re-run its check through `evidence.sh`. A delegate's "done" is a claim (principle-untrusted-until-proven). When you abandon a delegate, stop it and confirm it stopped.

## 7. Replies

`brief` shapes every reply: the answer first, ≤ 5 lines, detail in files, claims tagged `✓` / `~`. Name the principle behind any non-obvious decision. When a hook blocks you (fence, seal, circuit, claims, guard, the slice gate), do what it says. Never work around a hook.

## /flow resume

`scripts/task.sh list` → pick the active task (ask if several are open) → read HANDOFF.md (or HANDOFF.auto.md when newer), GATES.md if present, INTENT.md, and SLICES.md → re-run the current slice's check → continue. No handoff, or it predates the last conversation on this task: `recall` first.

## Done means

- Every acceptance check has a PASS in EVIDENCE.md, newer than the last edit.
- Every impacted feature's scenario passes, and its feature file is marked verified.
- The blind checks pass, and review found no blocker.
- The human approved at the merge gate, and TRACE.md is written.

Anything less is reported as exactly what it is.
