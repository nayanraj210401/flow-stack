---
type: regex
pattern: "feat:export\\.csv"
match: not_contains
target: { source: file, path: .flow/tasks/tweak/EVIDENCE.md }
---
