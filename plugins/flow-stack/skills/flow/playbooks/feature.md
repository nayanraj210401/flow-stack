# Playbook: feature

Use when: new behavior, a contract change, or work touching several files.
Principles: intent-before-code, design-it-twice, subtract-before-add, red-before-green, smallest-verifiable-unit, evidence-over-claims, checks-need-teeth.

1. **Understand.** If `.flow/map.md` is missing or older than 30 days of commits, run `map`. Run `how` on the area you will touch, and `why` when the current design looks deliberate. Use a subagent when this means reading more than about 5 files. Keep only its conclusions.
2. **Intent.** Run `intent`. It produces INTENT.md with visible checks and spawns the `checker` agent for blind checks. Seal the visible checks with `seal`.
   **GATE:** the human approves the Goal, the Non-goals, and the checks in one message.
3. **Approach.** Run `challenge`. The advocate designs from the goal alone, then attacks ours, and the null option (delete, reuse, configure, don't build) is always weighed. Record the result in INTENT.md `## Approaches`. The winner has the fewest new concepts and the least added code that meets the checks (principle-design-it-twice, principle-redesign-not-bolt-on, principle-model-the-domain). A GATE is needed only if the options are close and the choice is taste or irreversible.
4. **Slice.** Run `slice`. Each slice gets a check, a fence, and a diff budget. The first slice is the thinnest end-to-end path (tracer bullet).
5. **Execute.** For each slice in order, run `loop`. When slices are independent and the profile allows more than one agent, `delegate` instead. It caps parallel workers at `attention.max_parallel_agents`.
6. **Prove.**
   - Run every acceptance check once more on the final tree through `evidence.sh`.
   - Run `../verify/scripts/blind-run.sh`.
   - Run `../seal/scripts/seal.sh verify`.
   - Run `review` (fresh-context reviewer).
   - Run `deslop` on the diff and `unslop` on any prose you wrote (commit message, PR body, docs).
   - Record shortcuts with `debt`.
   A blind failure goes back to step 5 for the slice it names, and the human is told it happened.
7. **Present.** Run `../review/scripts/ready.sh` until it stamps HEAD (review, deslop, tour, and the live checks); only then open the PR as ready for review. One message: `tour` (a risk-ranked diff: what to read, what is safe to skip) plus `claims` (each statement tagged). If `dojo` is on, one explain-back question.
   **GATE:** the human approves the merge or push. Never push without it.
8. **Close.** Run `trace` (TRACE.md with estimate vs. actual), then `reflect`. Taste, lesson, and calibration diffs need the human's approval. Then run `scripts/task.sh close`.
