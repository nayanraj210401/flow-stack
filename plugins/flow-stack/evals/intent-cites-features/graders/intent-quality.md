---
type: llm
focus: { source: file, path: .flow/tasks/validate/INTENT.md }
---

PASS if the acceptance checks cite feature/sub-feature IDs from the calc.add feature: a NEW sub-feature ID for the validation behavior (e.g. calc.add.validation or calc.add.reject-non-integer) and the existing calc.add.sum as a must-not-break check. Checks should be runnable commands or clearly marked human-judged, and include the exit code 2 and stderr behavior. export.csv should not be in scope. FAIL if no feature IDs are cited, or checks are vague.
