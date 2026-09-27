---
type: regex
pattern: "mul\\s*\\(\\)"
match: not_contains
target: { source: file, path: src/calc.sh }
---
