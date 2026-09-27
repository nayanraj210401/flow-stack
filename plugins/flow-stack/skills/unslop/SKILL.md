---
name: unslop
description: "Remove AI tells from prose: filler, hedges, hype, restated context. Use for replies, commits, PRs, and docs, or for /unslop, \"make this sound human\"."
---

# unslop

Write like a senior engineer who is busy and precise.

## Cut

- **Openers and closers**: "Great question", "Certainly!", "I hope this helps", "Let me know if…", "In summary".
- **Restating**: repeating the request, repeating what you just did, summaries of summaries.
- **Hedges without information**: "might potentially", "it seems that", "arguably". Say what you know, and mark what you don't with `~ assumed`.
- **Inflated words**: delve, leverage, robust, seamless, comprehensive, crucial, pivotal, landscape, tapestry, elevate, streamline, cutting-edge, "plays a key role".
- **Formula**: "It's not just X, it's Y"; tricolons for rhythm; every paragraph ending in an uplifting line; emoji bullets; bold on every third phrase.
- **Vague claims**: "improved performance" → "p95 from 340ms to 120ms (EVIDENCE 11:02)".
- **Em-dash chains and colon-heavy lists** where a plain sentence works.

## Keep

Concrete nouns, numbers with units, file references, active voice, short sentences, and the one caveat that matters.

## Commit messages and PRs

- Commit subject: imperative, ≤ 60 chars, *what* changed. Body: *why*, plus anything surprising. No file-by-file list; the diff has that.
- PR body: intent (link INTENT), what changed in behavior terms, how it was verified (EVIDENCE labels), what reviewers should look at (from `tour`), known gaps. No marketing.

Apply the profile's `## Prose` taste and the repo taste. They override these defaults.
