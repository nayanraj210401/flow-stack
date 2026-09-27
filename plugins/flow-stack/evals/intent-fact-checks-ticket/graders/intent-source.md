---
type: llm
focus: { source: file, path: .flow/tasks/mul/INTENT.md }
---

PASS if this INTENT.md records the ticket's three criteria (AC1, AC2, AC3) in a Source section or equivalent, maps AC1 and AC2 to runnable acceptance checks, and marks AC3 as an open discrepancy: `add` in src/calc.sh has no input validation and no exit code 2, so "reuse add's existing validation" rests on a false premise. A check for AC3 is fine only if it is visibly pending (marked `(?)`, "pending", or "awaiting gate"). FAIL if AC3 is treated as settled (its check unmarked, or the Goal states AC3's behavior as decided), if AC1 or AC2 are missing or marked as discrepancies, or if the ticket's criteria are not recorded at all.
