---
type: llm
focus: { source: file, path: .flow/tasks/mul/EVIDENCE.md }
---

PASS if EVIDENCE.md contains a block headed with "S1 · PASS" (from evidence.sh) and a "probe:S1 · TEETH" block. A "before" FAIL block is fine and expected. FAIL if there is no PASS for S1 or no TEETH probe.
