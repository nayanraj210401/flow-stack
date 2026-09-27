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

## TOOTHLESS: what to do

The check doesn't observe the behavior you changed. Common causes:
- It asserts on a mock you also changed.
- It only checks that there is no crash.
- It tests a path the change does not reach.

Strengthen it to observe the real behavior, have the human approve the check change (it is sealed), re-seal, and probe again.

## Limits

Probe needs a git repo and uncommitted changes. After committing, probe against the parent by checking out `HEAD~1 -- <source files>` in a worktree. Say so if you did.
