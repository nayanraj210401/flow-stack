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

`add` refuses while a row in INTENT.md's `## Edge cases` maps to no check listed under `## Acceptance checks` and no `non-goal: <why>`, and it names the rows. A row is one line: `- <case> → C1, C2` or `- <case> → non-goal: <why>` (`→`, not `->`; no wrapped mappings). The gate is on when INTENT has a `## Edge cases` heading outside fences and comments (a trailing `:` or `##` is fine). That section may hold only rows, blank lines and comments that open at column 0; a fence or comment marker elsewhere in it, or an unclosed fence or comment anywhere, is refused. Lookalike headings (`## Edge cases (v2)`, `### Edge cases`) are not the matrix, and an INTENT without the heading seals as before: renaming or deleting the section shows in the diff.

## What happens after sealing

- An Edit or Write to a sealed file prompts the human (edit-guard hook).
- A shell command that writes to a sealed file prompts the human (guard hook).
- Editing `SEALS` or `INTENT.md` prompts the human.
- `seal.sh reseal` and `seal.sh rm` prompt the human.

## When a sealed check really is wrong

It happens: the check itself has a bug, or the requirement changed. Then:
1. Say so in one GATE message: what is wrong with the check, the proposed change, and why the code shouldn't change instead.
2. After approval, edit it (the hook asks and the human confirms), run `seal.sh reseal`, and log it: `../flow/scripts/task.sh decide human no "check C2 changed" "<why>"`.
3. If the check came from a ticket criterion, update that line in INTENT.md `## Source` (`resolved: amended`) so the ticket's author can be told.
