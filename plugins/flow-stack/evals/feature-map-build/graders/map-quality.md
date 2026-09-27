---
type: llm
focus: { source: file, path: .flow/features/README.md }
---

PASS if the index lists user-facing features of the calc CLI grouped by what the user does (e.g. adding, multiplying, viewing history; not one feature per file), each with entry points naming the CLI commands (calc add / calc mul / calc history) and owns globs pointing at src/cli.sh and/or src/calc.sh. FAIL if features are organized by file/module instead of user action, or entry points are template placeholders.
