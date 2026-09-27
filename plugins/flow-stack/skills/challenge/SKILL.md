---
name: challenge
description: "Break fixation: a blind advocate designs from the goal alone, then attacks our approach; the null option (delete, reuse, configure, skip) is always weighed. Use for \"is there a better way\", \"devil's advocate\", \"are we sure\", before committing to an approach."
---

# challenge: the first idea is rarely the best one

Agents anchor on the first workable approach and then spend every later step defending it. The fix is structural: get a second design from someone who never saw the first. Principles: `principle-design-it-twice`, `principle-subtract-before-add`.

## 1. State the problem without the solution

Write a problem brief of at most 12 lines: the goal, the constraints (from INTENT and repo taste), the non-goals, and what exists today (`file:line` pointers to the relevant code). **Do not mention the current approach, its names, or its files-to-be-created.** If you can't describe the problem without your solution, that is the first finding.

## 2. Blind design

Spawn the `advocate` agent (flow-stack:advocate) with the problem brief only, in `mode: design`. It returns its best approach, plus the null option, which it must always evaluate:
- **Delete**: can removing something solve it?
- **Reuse**: does the repo or a dependency already do this?
- **Configure**: is it a setting, flag, or data change?
- **Don't build**: does the goal hold without this?

Use a different model from yours when available (profile `budget.design_model`, or another panel model). A second opinion from the same model anchors less when it starts from zero, but diversity helps more.

## 3. Attack ours

Spawn the advocate again (or resume it) in `mode: attack`, now with our approach. It returns the three strongest reasons ours is wrong or worse, each with the evidence or the observation that would settle it.

## 4. Decide with a table, not a vibe

| | ours | advocate | null option |
|---|---|---|---|
| lines added / removed (estimate) | | | |
| new concepts (types, modules, deps) | | | |
| reader load (layers to trace) | | | |
| risk / reversibility | | | |
| settles which check in INTENT | | | |

Rules:
- The option with **fewer new concepts and fewer added lines wins ties**.
- If an attack names an observation that would settle it (a benchmark, a spike, reading one file), run it before deciding. That is cheaper than arguing.
- If the advocate's approach wins, switch now. Sunk cost is not a reason, and nothing is built yet.
- If they are close and the choice is a matter of taste or irreversible, it goes to the human as a GATE with the table.

Record the result in INTENT.md `## Approaches` (the chosen one, the rejected ones, why), and log it: `../flow/scripts/task.sh decide agent yes "approach: <chosen>" "<why it beat the others>" "challenge"`.

## When to run it

- **Always**, in flow's Approach step for features and refactors (skip for one-slice tasks; say you skipped).
- **At every slice boundary**, ask yourself in one line: *"If I were starting now, knowing what I know, would I pick this approach?"* A "no" triggers a full challenge.
- When a slice exceeds its diff budget by more than 50%.
- When the circuit breaker trips (after attack-the-premise).
- When the human asks "is there a better way?". Then show them the table, not a defense.

## Output to the human

At most 6 lines: the chosen approach, the runner-up and why it lost, the null option's verdict, and the lines-added estimate for the winner.
