# Playbook: optimize

Use when: making one measurable thing better (latency, memory, bundle size, cost, a flaky rate, an eval score) against a target, through repeated attempts.
Principles: evidence-over-claims, design-it-twice, subtract-before-add, build-the-lever.

The core discipline: **one change, one measurement, keep or revert.** Never stack untested changes. Never claim a win from reading code.

1. **Reproduce the complaint.** Run `how` on the hot path. Pick a workload that shows the problem. If nothing reproduces it, fix the reproduction first.
2. **Fix the metric and the stop rule.** Name one metric, the direction, a target, *and* a minimum number of attempts (e.g. "p95 −40% and ≥ 8 attempts"), so one lucky early win doesn't end the run. Use the human's numbers when given; otherwise agree them at a GATE.
3. **Build and prove the harness** (build-the-lever): one command that prints the metric as the median of N runs. Check that it separates the bad case from an easy case. If it can't tell them apart, fix the harness. Then freeze and seal it. Record the baseline and a green regression suite through `evidence.sh` (labels `baseline`, `gate`).
4. **Hypotheses from mechanism.** Each one names a specific cause ("the N+1 query at orders.ts:88 runs per line item"), not "try caching". Run `challenge` once on the hypothesis list; the advocate often finds the cheaper lever, like an index, deleting work, or a config flag.
5. **Loop.** For each hypothesis:
   - make the one change;
   - measure before and after with the frozen harness, and run the regression gate;
   - keep it only if the metric moves past noise and the gate stays green; otherwise **revert it fully**;
   - log a row in DECISIONS.tsv either way: hypothesis, change, before, after, delta, and kept or reverted.
   Independent hypotheses can go to `delegate` workers, one worktree each.
6. **Push past the first plateau.** After several reverts in a row, switch category, combine near-misses, or try something more radical. Prefer wins that delete code. A simplification that holds the number is kept even with no speedup.
7. **Stop** when the stop rule is met, or when the remaining ideas cost more than they would gain. Never relax the stop rule to meet it.
8. **Present**: baseline → final (percentage delta), attempts kept vs. reverted, one line per kept change with its delta, the next idea you'd try, and diffstat net lines.
