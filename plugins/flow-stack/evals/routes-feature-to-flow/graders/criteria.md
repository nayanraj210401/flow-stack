---
type: llm
weight: 1
---

Pass if the response follows an intent-first, verifiable approach:
- It defines, or commits to defining, concrete acceptance checks before implementation (e.g. "the 101st request in the window for a key returns 429", "different tiers get different limits", "separate keys don't share a limit").
- It proposes working in small verifiable steps (e.g. a thin end-to-end slice first).
- It raises only the few decisions that genuinely need the human (e.g. fail-open vs fail-closed, whether the quota is per key or per account), ideally with a recommended answer, rather than a long questionnaire or asking about facts already given in the prompt.
- It is concise: the approach comes first, and it doesn't read like a multi-page design doc (roughly under 40 lines).
Fail if it writes implementation code, has no notion of checks or acceptance criteria, or is a long essay.
