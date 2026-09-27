---
type: llm
focus: { source: file, path: .flow/tasks/mul/HANDOFF.md }
---

PASS if this handoff lets a fresh session start cold: it states the goal (add mul), says S1's check currently FAILS, identifies the concrete next action (mul in src/calc.sh uses + instead of *, so fix it to multiply), and cites a pointer to src/calc.sh. It should be short (under ~40 lines) and must not claim S1 is done. FAIL if the next action is vague (e.g. "continue working on S1") or the handoff claims the check passes.
