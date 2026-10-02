---
name: verify
description: Prove behavior on the real artifact and record evidence (evidence.sh, the repo driver, blind checks). Use before claiming done, fixed, or works, and for /verify or "prove it".
---

# verify: evidence over claims

Principle: `principle-evidence-over-claims`. "It compiles", "the tests I wrote pass", and "it should work" are not evidence. Output from running the real thing is.

## Resolve the driver (slot)

0. A `verify-driver` line in the profile's `# Toolchain` (for example gstack `/qa` for UI): use that tool to drive the app, then record its result through `scripts/evidence.sh` so it counts as evidence.
1. A repo driver at `.claude/skills/verify-<repo>/` (made by `make-verifier`) or `.claude/skills/verify/` (for example from pstack's create-verification-skill): use it for any user-visible behavior. It knows how to launch the app and exercise features.
2. A user driver in `~/.claude/skills/`: use it when present.
3. Neither: fall back to the repo's test, lint, and typecheck commands (`.flow/config.json` → `commands`). For UI or API changes, say in one line that no driver exists and suggest `/flow-stack:make-verifier`.

## Record every check

```bash
scripts/evidence.sh C1                              # runs C1's command from INTENT.md
scripts/evidence.sh S2:before                        # runs S2's check: from SLICES.md
scripts/evidence.sh smoke "<command>" [artifacts…]   # any other label runs the command given
```

- A `C<n>`/`S<n>` label runs the declared command. Passing a different one is refused; change the declaration instead (sealed checks need the human). A check that can't fail (empty, `:`, `true`) is refused.
- The Stop hook accepts a success claim only when a tool result after your last code edit ends in `flow-evidence: PASS` (or a ready stamp), task or not.
- It appends a block to EVIDENCE.md, prints the tail of the output, and ends with a `flow-evidence:` line that the circuit breaker reads.
- Artifacts (screenshots, response dumps) go in `.flow/tasks/<slug>/artifacts/`. Pass their paths so the block links them.
- Never write an EVIDENCE block by hand.

For UI changes, an artifact (a screenshot, or a Playwright trace or log) is required. For API changes, capture the actual response. For CLI changes, capture the actual output.

## Impacted features (every change that touches behavior)

```bash
../feature-map/scripts/features.sh impact          # which features this change touches, plus unowned files
../feature-map/scripts/features.sh run --impacted  # run their scenarios through evidence.sh (labels feat:<id>)
```

A feature's scenario drives every entry point it lists, and a PASS marks the feature verified at this commit. Acceptance checks prove the new behavior; impacted scenarios prove nothing else broke. Report both. If a changed file is `unowned`, say so. It means the map has a gap, and the fix is to add it to a feature's `owns:`. If the map doesn't exist, say so in one line and suggest `/flow-stack:feature-map`.

## Blind checks (Prove phase)

```bash
scripts/blind-run.sh
```

This installs the held-out checks temporarily, runs them, removes them, and reports only the verdict and failing test names. When it fails, the name tells you which behavior broke. Fix the behavior. Do not go looking for the check. Tell the human a blind check failed; it is a sign the visible checks were too narrow.

## Seals

Before presenting, run `../seal/scripts/seal.sh verify`. A changed seal that the human did not approve is a stop-everything finding. Report it.

## Reporting

Cite evidence by timestamp and label: `✓ C1 passes (EVIDENCE 10:42 · C1)`. Anything you did not run is `~ assumed`. See `claims`.
