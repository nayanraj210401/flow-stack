---
name: diagnose
description: "Root-cause a bug. Invoke for any bug report or production symptom with an unknown cause, even before code is available (\"users are getting logged out\", \"started since Tuesday\", \"intermittent\", \"why is this broken\"). Reproduce first, test hypotheses, fix the cause."
---

# diagnose

Principles: `principle-fix-root-causes`, `principle-attack-the-premise`.

## 1. Reproduce

Turn the report into a command that fails: a test, a curl, or a driver-skill script. Run it with `../verify/scripts/evidence.sh repro "<cmd>"`. If it doesn't reproduce, vary one thing at a time (data, env, order, timing), and note each attempt. After about 5 attempts with no reproduction, stop and raise a GATE: what you tried, and what information would help.

## 2. Hypothesize

List 2 or 3 candidate causes. For each one, name the single observation that would confirm or kill it (a log line, a debugger value, a bisect step, a minimal input). Rank them by cost to test × likelihood.

## 3. Observe

Run the cheapest decisive observation first. Tools, cheapest first: read the stack trace → add one targeted log → run a minimal input → `git bisect run <repro>` for regressions → a debugger. Record what you saw, not what you expected.

## 4. Ask why until you hit the defect

"The request 500s" → "the user is null" → "the session lookup misses" → "the cookie name changed in the auth upgrade". Fix at the last why. A null check at the first why is a silencing guard. Say so if you are tempted.

## 5. Record

`../flow/scripts/task.sh decide agent yes "root cause: <one line>" "<why chain>" "<evidence label>"`. The reproduction becomes the regression check; seal it. After the fix, `probe` must say TEETH.

## When stuck (or when the circuit breaker trips)

List the assumptions shared by everything you tried. Pick the one you are most sure of and test it anyway. That is usually the wrong one.
