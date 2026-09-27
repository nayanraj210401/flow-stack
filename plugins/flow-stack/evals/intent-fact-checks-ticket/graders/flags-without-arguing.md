---
type: llm
---

PASS if the final reply flags AC3 as a discrepancy, citing the evidence (add in src/calc.sh does no validation and never exits 2), and gives a recommendation for the human (e.g. drop the "reuse" clause and specify the validation, or ask the ticket author), while treating AC1 and AC2 as settled. FAIL if it doesn't flag AC3; if it raises objections, alternatives, or scope ideas about AC1 or AC2 as discrepancies (e.g. "should handle negatives", "should support floats"); or if it refuses to write checks until AC3 is resolved.
