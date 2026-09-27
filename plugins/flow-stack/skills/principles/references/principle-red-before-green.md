# Red before green

**Rule.** Every slice runs its check before building (red, failing for the reason the slice addresses), after building (green), and against reverted source (the probe must fail). The slice-done gate refuses completion without all three. It records `red: n/a <reason>` or `teeth: n/a <reason>` only when they truly can't apply.

**Why.** A check you never saw fail can't tell you anything. Green-first tests pass by accident: they assert the mock, test the wrong path, or already passed before the change.

**Bad.** Write the implementation, write a test, it passes. Ship. (The test would have passed with the old code too.)

**Good.** `evidence.sh S2:before "npm test -- limit"` → FAIL "expected 429, got 200". Build → PASS. `probe.sh S2` → TEETH. `task.sh slice S2 done` → accepted.

**Check yourself.** Does the red failure message name the missing behavior, not an import error or a typo?
