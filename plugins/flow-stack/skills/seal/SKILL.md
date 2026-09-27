---
name: seal
description: Lock acceptance checks so they cannot be weakened to get a pass; edits then need the human. Use after checks are approved, or for /seal.
---

# seal: the goalposts don't move

Agents under pressure to pass make checks easier: they loosen an assertion, special-case an input, or skip a test. Sealing makes that impossible to do silently.

```bash
scripts/seal.sh add <path>…    # after the human approves the checks
scripts/seal.sh verify         # before presenting; non-zero exit = tampering
scripts/seal.sh list
```

## What happens after sealing

- An Edit or Write to a sealed file prompts the human (edit-guard hook).
- A shell command that writes to a sealed file prompts the human (guard hook).
- Editing `SEALS` or `INTENT.md` prompts the human.
- `seal.sh reseal` and `seal.sh rm` prompt the human.

## When a sealed check really is wrong

It happens: the check itself has a bug, or the requirement changed. Then:
1. Say so in one GATE message: what is wrong with the check, the proposed change, and why the code shouldn't change instead.
2. After approval, edit it (the hook asks and the human confirms), run `seal.sh reseal`, and log it: `../flow/scripts/task.sh decide human no "check C2 changed" "<why>"`.
