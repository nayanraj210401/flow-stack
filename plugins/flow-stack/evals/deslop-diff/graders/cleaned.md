---
type: llm
focus: { source: file, path: src/calc.sh }
---

PASS if the mul function is now short and clean: no narrating comments ("compute the result", "return the result", "helper function that takes two arguments"), no commented-out debug line, no "debug: first arg empty" stderr branch; and mul still returns the product of $1 and $2 (e.g. `mul() { echo $(( $1 * $2 )); }`). The add function must still exist and still add. FAIL if slop remains in mul, or if mul's behavior changed.
