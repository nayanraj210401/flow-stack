# Playbook: multi-session

Use when: the work will not fit one context window or one day.
Principles: spend-cheap-save-expensive, smallest-verifiable-unit.

1. Run the feature playbook, with these additions.
2. `slice` groups slices into **phases** of at most one session each (`## Phase 1` headings above slice blocks). Every phase ends in a green, committable state.
3. At every phase boundary, and whenever context passes the handoff threshold, run `handoff`. HANDOFF.md must let a fresh session start with no other reading than INTENT.md.
4. The next session starts with `/flow resume`.
5. Prefer committing at each phase boundary (with the human's permission, per their Rules) so progress survives outside `.flow/`.
6. `trace` at the end covers all sessions. The trail spans them because it lives in the task folder.
