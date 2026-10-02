---
name: loop
description: "Inner loop for one slice: red → subtract scan → build → verify → probe → proof-gated done, with a circuit breaker. Use when flow executes a slice or for \"/loop S2\"."
---

# loop: build → verify → probe → diagnose → evidence

One slice at a time. Paths are relative to this skill's base directory. `T` below is `../flow/scripts/task.sh`.

## Start

1. `T slice <id> doing`. The fence hook now enforces the slice's `fence:` globs.
2. Read the slice's `check:` and `budget:`. If the check is empty, write it now, in the slice block, before any code (principle-intent-before-code). If it is a new test file, seal it: `../seal/scripts/seal.sh add <path>`.
3. Run the check once **before** building: `../verify/scripts/evidence.sh <id>:before` (it runs the slice's declared check). It should fail. If it already passes, the check does not test this slice. Fix the check, not the code.

## Cycle

**a0. Subtract scan** (principle-subtract-before-add), once per slice, before the first build: what inside the fence can be deleted? What already exists (`rg` for the verbs and nouns) that this slice could reuse? Could config or data do it? Write the answer in one line in DECISIONS.tsv.

**a. Build.** Make the smallest change that could make the check pass. Stay inside the fence. Delete before you add (principle-subtract-before-add). Follow the profile and repo Taste. When something falls outside the fence, the hook tells you how to widen it on purpose.

**b. Verify.** Run `../verify/scripts/evidence.sh <id>`, plus the repo's lint and typecheck from `.flow/config.json` `commands` when set. Use the repo verify driver (`.claude/skills/verify-*/`) for UI, API, or CLI behavior. A unit test alone doesn't prove a user-visible behavior.

**c. Pass?**
- **Yes:** run `../probe/scripts/probe.sh <id> "<check>"`. TEETH means record the slice done. TOOTHLESS means the check passes without your change, so it proves nothing. Strengthen the check, re-seal (the human approves), and go back to b.
- **No:** go to d.

**d. Diagnose.** Read the failure. Name the cause in one line before touching code. Fix the cause, not the symptom: no silencing try/catch, no special-casing the test's inputs, no loosening assertions (principle-fix-root-causes). Then go back to a.

## Circuit breaker

The PostToolUse hook counts failure signatures from `evidence.sh`. The third identical failure trips it. When it trips:
1. Write the assumption shared by every fix you tried (principle-attack-the-premise).
2. Design one observation that could prove that assumption false, and run it.
3. Run `challenge`: the advocate designs from the problem brief alone, so it can't inherit the assumption that failed.
4. Raise a GATE with what you learned and two options. Stop working on the slice until the human answers.

Heavy churn on one file (6 edits without a passing check) also trips a warning. Treat it as a prompt to diagnose.

## Finish the slice

- `scripts/diffstat.sh <fence globs>` gives added, removed, net, and new files. If it's net positive, say in one line what the added lines buy. A new file needs a reason it can't live beside its caller.
- `T slice <id> done`. This is **gated**: it checks red first, green after the last edit, probe TEETH, and the diff budget (`T proofs <id>` shows what's missing). Produce the missing proof; don't reach for `--force` unless a proof truly can't apply, and then give the reason.
- **Fixation check** (principle-design-it-twice): in one line, *"starting now, would I pick this approach again?"* If not, or if the slice ran more than 50% over budget, run `challenge` before the next slice.
- Record any shortcut with `debt`.
- One-line status to the human only if they asked for progress updates. Otherwise continue to the next slice silently.

## Never

- Claim a slice is done without a PASS and a TEETH entry in EVIDENCE.md.
- Edit a sealed check to make it pass.
- Read `blind/`.
