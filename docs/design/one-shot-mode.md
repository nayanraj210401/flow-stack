# One-shot mode

Status: design, decided 2026-11-14. Not built yet.

## Source data

A token-burn analysis of 2026-11-13 covered 247 Claude Code transcripts over 28 days ($606, 117 main
sessions). It lives outside this repo, in a local note. The findings this doc relies on:

| ID | Finding |
|---|---|
| F1 | 81% of cost is paid at ≥100k context; threads accumulate and are rarely reset |
| F2 | 45% of cost comes after the PR is created (review fix loops, PR polling) |
| F3 | review runs twice (local reviewer plus CI reviewer), and `ready.sh` is polled |
| F5 | the Stop hook's claims check forced about 245 extra turns (about 6% of cost) |
| F6 | in feature sessions the requirement arrived over 5–10 prompts, some after the PR existed |

Cost shares are relative units (cache read 0.1, cache write 2, output 5 per token). The suggested
savings below are judgment, not measured.

## The problem

The human's attention gets spent late and in small pieces (F6). Each late prompt wakes a thread that
already holds 150k+ tokens of context (F1).

The cause is structural:

- `rigor: lean` caps the intent interview at 2 questions (`skills/flow/SKILL.md`, rigor table), so the
  build starts on a partial spec.
- INTENT.md records *what passes* (goal, non-goals, sealed checks). Answered open questions are moved to
  DECISIONS.tsv, which a fresh build session doesn't read. So the build stops on choices it can't see
  and pulls the human back in.

## Is flow-stack spec-driven development?

Partly. It is driven by checks, not by a spec document.

| | Spec-driven (Spec Kit, Kiro) | flow-stack today |
|---|---|---|
| Source of truth | spec → plan → tasks; code derived from it | INTENT.md per task: goal, non-goals, sealed runnable checks, blind checks |
| Lifetime | the spec lives in the repo and evolves | INTENT is per task and untracked; the lasting spec is the feature map (`.flow/features/`) |
| Done means | matches the spec | checks pass, with evidence newer than the last edit |
| Design decisions | written in the plan | `## Approaches` in INTENT; the rest in DECISIONS.tsv or decided during the build |

One-shot closes the last row: the decisions move into INTENT, before the build.

## Design

One-shot means front-loading attention: spend it at grooming, then don't contact the human again until
the merge gate. It composes existing parts (`intent`, `seal`, `handoff`, `--auto`) and adds no new
playbook.

### 1. Groom: remove the lean cap for features

The `intent` skill already asks only what the code can't settle, offers a recommended answer with each
question, and batches independent questions. The only change: the feature playbook drops the lean
2-question cap. The interview runs until the decisions below are answered.

"quick" or "just do it" on a feature opts out of one-shot for that task and keeps the 2-question cap.

### 2. INTENT changes: answers stay in INTENT

No new sections, so the template doesn't grow:

| Need | Where it goes |
|---|---|
| Decisions the build would otherwise stop on | `## Open questions`. An answered question stays in place as `- Q1 · <question> → <answer>`; it is still logged to DECISIONS.tsv. The template comment "Remove when answered" changes to match. |
| Deferred scope | `## Non-goals`, as `- <item> → follow-up` |
| What "done" looks like | an acceptance check that replays a sample (CLI transcript, expected output), not a prose description |

Grooming covers every decision the build would otherwise stop on: the surface/UX, names, data shape,
files touched, and what to reuse.

Row grammar: an Open questions row is answered if and only if it contains ` → ` followed by non-empty
text. Any other non-blank row is unanswered.

### 3. Readiness: extend `seal.sh add`, no new command

`seal.sh add` already refuses while an edge-case row maps to neither a check nor a non-goal. In a
one-shot task it also refuses while INTENT has:

- any `(?)` marker;
- any unanswered Open questions row (by the grammar above).

Order stays as today: the human approves the intent, then seal runs. A refused seal sends the agent
back to grooming before the build can start. The script enforces this instead of prose
(principle-encode-in-structure).

### 4. Build in a fresh session, unattended until the PR

The groom session ends with a handoff, and the build runs from INTENT and SLICES alone. That keeps the
build under about 80k tokens of context (F1).

Plain `--auto` denies push and PR commands, so it can't reach a PR alone. `--auto ship` unlocks push,
PR and merge together, which is more than one-shot should get. One-shot needs a new level:

- `--auto pr`: allows a stamped push of the task branch and opening a draft PR. Merge stays denied and
  waits for the human at the merge gate.

Open choice: how the fresh session starts. A plugin can't open a session by itself. The candidates:

| Option | For | Against |
|---|---|---|
| `claude -p` launched from the handoff | fully unattended | headless, so no live view |
| A new thread in a host that runs parallel sessions (T3, herdr) | live view | one launcher per host |
| Print a resume command to paste | works everywhere, no new code | one human step |

Recommendation: print the command first, and add launchers per host later.

### 5. Scope freeze

A request made during the build goes to Non-goals as `→ follow-up`, or to an issue. The PR ships what
was groomed.

## How we know it worked

Re-run the token-burn analysis on feature sessions after the change:

- zero human prompts between build start and PR-create;
- build-session context stays under 80k at PR-create;
- intent-phase cost share may rise, and that is fine.

## Out of scope, and what to pair it with

One-shot targets the cost before the PR (about 28%). The cost after the PR (45%: two reviews, fix
loops, PR polling; F2, F3) is outside this design. The review part is #229 ("PR bottleneck: brakes
inside the PR"). PR polling has no issue yet. Two cheap wins worth pairing:

- End the build session at PR-create, and hand post-PR work to a small babysitter session. This is
  estimated at 25–35% of cost, and the fresh-session build already gets halfway there.
- Stop hook: don't block when the edits since the last PASS can't affect the check (F5, about 5%).

## Decided (human, 2026-11-14)

- Trigger: default for the feature playbook, even at `rigor: lean`. Bugs and contained edits stay
  quick, and "quick" on a feature opts out.
- Build: a fresh session that reads only INTENT and SLICES, runs unattended, and stops at an open
  draft PR.
- Scope added during the build goes to a follow-up or an issue. This PR ships what was groomed.
- Post-PR cost stays out of scope.
