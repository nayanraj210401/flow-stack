---
name: delegate
description: Run independent slices in parallel worktree workers, capped by your review budget; accept only with evidence and review. Use for /delegate, "parallelize this".
---

# delegate: trust, verified

Principle: `principle-untrusted-until-proven`. Compute scales freely. Review capacity doesn't. The real limit on parallel agents is how much the human can review.

## Preconditions

- An approved, sealed INTENT and a SLICES.md with independent slices (`parallel: yes`, non-overlapping fences).
- Git repo, clean enough to branch from.

## Cap

`max = profile attention.max_parallel_agents` (default 2). Never exceed it. If more slices are ready, queue them and start the next as one finishes. Tell the human the cap and the queue in one line.

## Fan out

For each slice, spawn the `worker` agent (flow-stack:worker, which runs in its own worktree) with: the task slug, the slice id, and "follow flow-stack:loop for this slice only". Use the profile's `budget.build_model`. Run the workers in the background, and do other unblocked work while they run.

## Accept or reject each result

A worker's report is a claim. Before merging its branch:
1. Its EVIDENCE shows PASS and TEETH for its slice. Re-run its check yourself on the worker branch through `evidence.sh` (label `accept:<id>`).
2. `seal.sh verify` passes on its branch.
3. Its diff stays inside its fence and budget.
4. `review` on its diff returns no blockers.

Merge into the task branch only when all four hold. Then import the worker's evidence and mark the slice from the main checkout: `../flow/scripts/task.sh accept <lane>`, then `task.sh slice <id> done`. Workers never mark slices themselves; one writer keeps SLICES.md and EVIDENCE.md race-free. Otherwise send the failure back to a fresh worker, once. A second failure becomes a gate.

## After all slices

Run the full Prove phase on the merged result, including the blind checks. Integration bugs live between slices.

## The human sees

One consolidated `tour` and `claims`, never N separate reports.
