---
type: llm
focus: { source: file, path: .flow/tasks/pow/INTENT.md }
---

PASS if this INTENT.md has: a one-sentence Goal about raising a number to a power; at least one Non-goal (e.g. no floats, no negative exponents, no other operations); and at least two acceptance checks, each either a runnable command (e.g. `bash tests/test_pow.sh`) or explicitly marked human-judged, covering at least one edge case (exponent 0, exponent 1, or negative/zero base). FAIL if the checks are vague prose like "pow works correctly" with no command, or if Goal/Non-goals are missing.
