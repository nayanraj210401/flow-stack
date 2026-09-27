---
name: claims
description: Tag each statement ✓ verified (with evidence) or ~ assumed. Use when reporting results, or for "what did you actually verify".
---

# claims: what do you actually know?

Principle: `principle-evidence-over-claims`.

## Format

```
✓ 101st request returns 429 (EVIDENCE 10:42 · C1)
✓ blind checks pass (EVIDENCE 10:51 · blind)
~ assumed: Redis failover keeps counters (no check; needs staging)
~ assumed: the mobile client handles 429 (not in this repo)
```

- `✓` requires an EVIDENCE entry that covers the current code, meaning it ran after the last edit to the files involved.
- Everything else is `~ assumed`, with what would verify it.
- Put assumed items last. Never bury them.

## The Stop hook

If your final message says done, fixed, works, passes, or ready, and there is no PASS evidence after the last code edit, the hook sends you back once. Either run the check, or rewrite the claim as `~ assumed: …`. Don't game it by avoiding the words; the human reads the same report.

## Self-audit before presenting

For each claim, ask: *if the human re-ran this now, would it hold?* If you are not sure, it is `~`.
