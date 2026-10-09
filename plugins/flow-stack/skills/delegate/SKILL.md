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

For each slice, spawn the `worker` agent (flow-stack:worker, which runs in its own worktree) with: the task slug, the slice id, and "follow flow-stack:loop for this slice only". Use the profile's `budget.build_model`. When you lead from a worktree, your workers join your task, not the main checkout's, and you accept them from your worktree. Run the workers in the background, and do other unblocked work while they run.

Read the profile Toolchain `- delegate:` line through `scripts/dispatch.sh start <slug> <slice>`. It prints "use the Agent tool" for `agent` (or no line): spawn as above. For `herdr-panes` it starts the worker as a herdr pane (worktree, claude, the same brief), prints the lane, and the worker joins the task as that lane. Then `dispatch.sh wait <lane>` and read `lanes/<lane>/EVIDENCE.md` instead of a return value. The pane's prompts arrive as user input, so its irreversible gates stay queued.

## Accept or reject each result

A worker's report is a claim. Before merging its branch:
1. Its EVIDENCE shows PASS and TEETH for its slice. Re-run its check yourself on the worker branch through `evidence.sh` (label `accept:<id>`).
2. `seal.sh verify` passes on its branch.
3. Its diff stays inside its fence and budget.
4. `review` on its diff returns no blockers.

Merge into the task branch only when all four hold. Then import the worker's evidence and mark the slice from the main checkout: `../flow/scripts/task.sh accept <lane>`, then `task.sh slice <id> done`. `accept` first checks that the lane's branch is merged into HEAD (a real merge, not `--squash`), then re-runs the features that lane changed (its recorded fork point to its branch) on the merged tree. If one fails, the lanes drifted apart: it refuses the evidence and marks the feature broken. Feature runs inside a lane go to `.flow/features/lanes/<lane>.tsv`; only the main checkout moves the shared status. Workers never mark slices themselves; one writer keeps SLICES.md and EVIDENCE.md race-free. Otherwise send the failure back to a fresh worker, once. A second failure becomes a gate.

After `accept` succeeds on a pane lane, run `dispatch.sh cleanup <lane>`: it removes only a worktree recorded in `lanes/<lane>/HOST`, and only when it has no uncommitted changes. Keep it if accept failed. `dispatch.sh gc` sweeps every clean recorded lane: ask the human before running it.

## After all slices

Run the full Prove phase on the merged result, including the blind checks. Integration bugs live between slices.

## The human sees

One consolidated `tour` and `claims`, never N separate reports.
