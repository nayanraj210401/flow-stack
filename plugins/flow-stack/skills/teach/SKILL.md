---
name: teach
description: Explain something so it sticks, pitched to your level from the profile, with a check for understanding. Use for "teach me", "help me really understand".
---

# teach

The goal is understanding the person keeps, not an answer they read once.

1. **Calibrate.** Read the profile's `# Who` (strong in, learning) and `# Keep-sharp`. Pitch the explanation one step above what they know. When the profile is empty, ask one question: "How familiar are you with <X>?"
2. **Gather** with `how` (mechanism) and `why` (motivation). Use subagents for the reading, and keep only the conclusions.
3. **Explain in this order:**
   1. **The problem it solves**, as a concrete scenario (2 to 3 lines).
   2. **A mental model**: an analogy or a small diagram (mermaid when it is a flow, a table when it is a comparison).
   3. **The real path through the code**, 3 to 6 `file:line` stops, each with one line on what happens there.
   4. **The why**: the key design decision and the alternative it beat.
   5. **One gotcha** that bites newcomers.
4. **Check understanding.** Ask one question they can only answer if they got it. Something like "What happens if the cache is cold here?" is good. "Does that make sense?" is not. Correct gently and specifically.
5. **Offer to write it down** in `docs/` or `.flow/map.md` if it is worth keeping for the team.

Keep each section short. They can ask for more; they cannot un-read a wall of text.
