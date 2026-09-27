---
name: flow
description: "Orchestrator for non-trivial work. Invoke BEFORE planning or writing code for a new feature, multi-file change, design choice, or unknown bug; also for \"how would you approach\", \"plan this\", /flow, \"/flow resume\". Picks a playbook and runs intent → approach → slices → prove with human gates."
---

# flow: the outer loop

You spend three currencies: tokens (cheap, capped), dollars (moderate), and the human's attention (the most expensive). Spend cheap to save expensive. Every step below either protects the human's attention or turns tokens into evidence.

Paths in this skill are relative to this skill's base directory. Formats for every file live in [references/conventions.md](references/conventions.md). Read it once per session before writing task files.

## 0. Classify (always, in your head, 10 seconds)

| Request | Route | Ceremony |
|---|---|---|
| Question about code, history, or behavior | `playbooks/investigate.md` | none: cited brief answer |
| One contained edit with an obvious check | edit, then run the check through `verify` | none |
| "Not sure what to build" / taste or design unknown | `playbooks/spike.md` | throwaway branch |
| Bug with unknown cause | `playbooks/bug.md` | task folder |
| New behavior, multi-file, contract change | `playbooks/feature.md` | task folder |
| Rename, migration, sweep | `playbooks/refactor.md` | task folder |
| Make a metric better (latency, size, cost, flake rate) | `playbooks/optimize.md` | task folder |
| Spans days or several sessions | `playbooks/multi-session.md` | task folder + handoffs |
| Matches a repo playbook in `.flow/playbooks/` | that playbook | as it says |

**Resolve before routing.** Read the profile's `# Toolchain` (injected at session start). A listed provider replaces the matching flow-stack skill at every step below (see Delegation in [references/conventions.md](references/conventions.md)). If `router` names another tool and the human invoked flow anyway, run flow for this task. Check `.flow/playbooks/*.md` next: a repo playbook beats a built-in one when its "Use when" line matches. Check for a repo driver (`.claude/skills/verify-*/`) and a repo runner (`.claude/skills/run-*/`). When a slot the playbook needs is empty, say so in one line and suggest the forge skill (`make-verifier`, `make-runner`) instead of improvising.

Say the route in one line: `flow: feature playbook · task rate-limit · verify driver: verify-api`.

## Rigor: scale the ceremony to the task

Ceremony costs tokens and dollars; skip what the task can't use. The profile's `rigor:` sets the default (`standard`), and the human can override per task ("quick", "go strict").

| Step | lean | standard | strict |
|---|---|---|---|
| intent interview | ≤ 2 questions | as needed | as needed |
| blind checks (checker agent) | skip | features that change a contract | always |
| challenge (advocate agent) | only if the human asks or the circuit trips | multi-slice features and refactors | every task-folder task |
| review (reviewer agent) | diff > 300 lines | always, one reviewer | per area, in parallel |
| probe, seal, evidence, slice gate | on (bash only, no model tokens) | on | on |
| trace / reflect | on request | at close | at close |

The deterministic parts (evidence, seals, probe, trail, proofs, diffstat, auto-handoff) run as shell scripts and cost no model tokens, so no rigor level turns them off. Agents run on Sonnet by default. Pass the Agent tool a `model` from the profile's `budget:` when a step needs more (for example, `design_model` for a contested challenge).

## 1. Open the task (task-folder playbooks only)

```bash
scripts/task.sh new <kebab-slug> <playbook>
```

Then **forecast**. Give a rough estimate of dollars, the context percentage you expect to peak at, and the human's minutes (gates plus review). Base it on the size of the change and on the profile's `# Calibration` table when it has rows. Save it with `scripts/task.sh estimate <usd> <ctx_pct> <human_min>`. If the human-minutes estimate is more than a third of the profile's `attention.review_minutes_per_day`, say so and offer to cut scope.

## 2. Run the playbook

Read the chosen playbook file and follow it step by step. Every playbook uses these building blocks:

| Phase | Skill | Output |
|---|---|---|
| Understand | `how`, `why` (with `map` first if `.flow/map.md` is missing or stale) | cited notes, kept in your context or a subagent's |
| Intent | `intent` | INTENT.md; checks sealed with `seal` |
| Approach | `challenge` (advocate designs blind, then attacks; null option weighed) | INTENT.md `## Approaches` |
| Slice | `slice` | SLICES.md |
| Execute | `loop` per slice, or `delegate` for independent slices | EVIDENCE.md entries |
| Prove | `verify` (blind checks), `review`, `deslop`, `unslop`, `debt` | verdicts |
| Present | `tour`, `claims`, `dojo` if on | one short message |
| Close | `trace`, `reflect` | TRACE.md, proposed profile diffs |

**Gates.** The human is asked at three fixed points: intent approval, merge/push, and profile diffs. They are also asked whenever `gate` classifies a decision as irreversible or a matter of taste. Everything else proceeds and is logged with `scripts/task.sh decide agent yes "<decision>" "<why>" "<evidence>"`. Batch questions. Never ask what running something could answer.

**Principles in play.** Read a principle (`../principles/references/principle-<name>.md`) the first time it shapes a decision, and name it in your reply when it changed what you did: `principle-intent-before-code`, `principle-design-it-twice`, `principle-subtract-before-add`, `principle-red-before-green`, `principle-evidence-over-claims`, `principle-checks-need-teeth`, `principle-smallest-verifiable-unit`, `principle-spend-cheap-save-expensive`, `principle-human-owns-irreversible`. Shaping code: `principle-model-the-domain`, `principle-redesign-not-bolt-on`, `principle-minimize-reader-load`.

**No is an acceptable answer.** When the human proposes an approach, give your real judgment. If a simpler path or the null option is better, say so with the table from `challenge`. Agreeing is not the default.

## 3. Throughout

- **Context budget.** When context passes the profile's `budget.handoff_at_context_pct`, run `handoff` at the next slice boundary. Route bulk reading to subagents. `budget` has the rules.
- **Drift.** The anchor hook re-injects the goal every prompt. If the work no longer serves the goal, stop and raise a gate.
- **Replies.** Follow `brief`: answer first, at most 5 lines, detail in files.
- **Hooks you will meet.** `fence` (edit outside the slice), `seal` (edit to a sealed check), `circuit` (the same failure 3 times), `claims` (a success claim without evidence), and `guard` (destructive commands, missing packages). Each tells you what to do. Do it; never work around a hook.

## /flow resume

Run `scripts/task.sh list`, pick the active task (or ask when several are open), read its `HANDOFF.md` (or `HANDOFF.auto.md` when newer), INTENT.md, and SLICES.md, then continue the slice marked `doing`.

## Done means

Every acceptance check has a PASS entry in EVIDENCE.md. The blind checks pass. Review found no blocking issue. The human approved at the merge gate. TRACE.md is written. Anything less is reported as exactly what it is.
