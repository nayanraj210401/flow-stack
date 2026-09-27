---
type: llm
focus: { source: file, path: src/calc.sh }
---

PASS if src/calc.sh defines a mul function that multiplies its two arguments (e.g. using $(( $1 * $2 ))) without special-casing specific inputs, and still defines add. FAIL otherwise.
