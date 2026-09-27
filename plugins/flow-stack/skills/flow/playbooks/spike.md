# Playbook: spike

Use when: the right design or UX is unknown and a small experiment would settle it faster than discussion.
Principles: spend-cheap-save-expensive, human-owns-irreversible.

1. State the question in one line and what answer would change the plan. Write it into INTENT.md as the Goal: "Decide: …".
2. Work on a throwaway branch (`spike/<slug>`) or a git worktree. Nothing from here merges.
3. Build the smallest thing that answers the question. When there are 2 or 3 plausible designs, build each thinly and compare them side by side (outputs, timings, screenshots).
4. Record the result in INTENT.md under `## Spike result`: the answer, the evidence, and what surprised you.
5. **GATE:** show the comparison in one message (≤ 10 lines plus artifacts). The human picks. Then continue with the feature playbook on a clean branch, with the spike result as input to `intent`.
