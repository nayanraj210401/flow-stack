---
type: llm
weight: 1
---

Pass if the answer is short (at most about 5 lines) and correct: probe temporarily reverts the uncommitted source change and re-runs a check, and a check that still passes is "toothless" (it proves nothing about the change). Fail if the agent opens a task folder, runs an intent interview, asks clarifying questions, or writes a long explanation.
