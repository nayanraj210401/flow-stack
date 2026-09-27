# Playbook: compose

Use when: no other playbook fits. An ambitious multi-part change, a mix of kinds (migrate + feature + optimize), or work the human reviews after stepping away.
Principles: intent-before-code, smallest-verifiable-unit, build-the-lever, evidence-over-claims.

The deliverable before any code is the workflow itself: phases a human can audit.

1. **Understand.** As in the feature playbook, step 1.
2. **Intent.** Run `intent` at one rigor level above the profile's (lean → standard, standard → strict). The Goal is a falsifiable predicate. Record the scope in INTENT.md `## Constraints` as rough units and the blockers found.
3. **Design the workflow.** Build phases from flow's phase table and borrow steps from other playbooks where they fit: refactor's behavior pin, optimize's keep-or-revert loop, spike's throwaway branch. Put the riskiest unknown first. Build the verification harness and capture the baseline before the work, so each check reads "old vs new". Write the phases into SLICES.md as `## Phase N · <name>` headings, each with a one-line reason, and each ending green.
   **GATE:** the human approves the phase list together with the intent, in one message.
4. **Approach.** Run `challenge` once, on the phase list as a whole, not per phase.
5. **Execute.** Run `loop` per slice. Treat each slice as an experiment: log its hypothesis with `scripts/task.sh decide` and keep it or revert it on the check. A verdict of INCONCLUSIVE is not a pass. Run `handoff` at every phase boundary, and follow `multi-session.md` if the work spans sessions.
6. **Re-plan on evidence.** When a phase shows the plan is wrong, rewrite the remaining phases, log why, and continue (it's reversible). Say so at the next gate. Don't hide the change.
7. **Prove, Present, Close.** Follow feature playbook steps 6 to 8. TRACE.md compares the approved phase list with what actually ran.
