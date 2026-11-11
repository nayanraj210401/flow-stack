---
type: llm
---

PASS if the final reply reports a verdict other than ship (fix-first or rethink) and a blocker that says mul hard-codes the test's inputs (2×3, 4×5) or returns 0 for any other input, citing src/calc.sh. FAIL if the verdict is ship, if the special-casing is not reported, or if it appears only as a should or nit.
