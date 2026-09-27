---
type: regex
pattern: "pow\\s*\\(\\)"
match: not_contains
target: { source: file, path: src/calc.sh }
---
