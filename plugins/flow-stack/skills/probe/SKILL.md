---
name: probe
description: "Test the test: revert the change and re-run the check; if it still passes, the check proves nothing. Use after a check passes, or for \"does this test actually test anything\"."
---

# probe: does the check have teeth?

Principle: `principle-checks-need-teeth`. A check that passes with and without your change is decoration.

```bash
scripts/probe.sh <label> "<check command>" [--keep <path> …]
```

- It reverts uncommitted source changes relative to HEAD. It keeps sealed files, `.flow/`, test-looking paths, and any `--keep` paths.
- It runs the check, restores everything (even on Ctrl-C), and records `probe:<label> · TEETH|TOOTHLESS` in EVIDENCE.md.
- Exit code 0 means TEETH; 1 means TOOTHLESS.

Use `--keep` for fixtures or helpers the check needs that don't look like tests.

## Reverting new code proves little: hollow it too

When every reverted file is new, the check fails on the missing import whatever its assertions say, and probe says so. A test that loops over the output, or checks the items are unique, also passes when the output is empty. So after a revert probe, empty the code under test:

```bash
scripts/probe.sh <label> "<check>" --hollow <file> "<old text>" "<new text>"
# e.g. --hollow src/guide.ts "return keys;" "return [];"
```

`<old text>` must occur exactly once in `<file>`. Swap the return value for an empty one of the same type (`[]`, `''`, `{}`, or an object whose arrays are empty). Probe runs the check on the rest of your change, restores the file, and records `probe:<label>:hollow · TEETH|TOOTHLESS`. TOOTHLESS here means: assert the exact length or the exact value before looping.

## TOOTHLESS: what to do

The check doesn't observe the behavior you changed. Common causes:
- It asserts on a mock you also changed.
- It only checks that there is no crash.
- It tests a path the change does not reach.
- It loops over the output, or checks uniqueness, with no length check first (`--hollow` catches this).
- It matches part of a string (`include`) where the whole text should be compared.

Strengthen it to observe the real behavior, have the human approve the check change (it is sealed), re-seal, and probe again.

## Limits

Probe needs a git repo and uncommitted changes. After committing, probe against the parent by checking out `HEAD~1 -- <source files>` in a worktree. Say so if you did.
