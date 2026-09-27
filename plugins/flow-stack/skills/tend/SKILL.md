---
name: tend
description: "Re-run self-tests of generated skills and flag drift against the code; one batched fix. /flow-stack:tend."
disable-model-invocation: true
---

# tend: a stale skill is worse than none

A skill that confidently describes a script that no longer exists sends the agent down the wrong path.

## Inventory

- `.claude/skills/*/SKILL.md` containing `generated-by: flow-stack:`.
- `.flow/playbooks/*.md`, `.flow/gates.md`, `.flow/map.md`, `.flow/taste.md`.
- The personal skills listed in the profile, if the human asks.

## Check each one (run these in parallel, one subagent per skill for big repos)

1. **Self-test**: run the `## Self-test` command. Record pass or fail with output.
2. **Drift**: `git diff --stat <source-commit>..HEAD -- <paths the skill references>`. Referenced files that moved or vanished, renamed scripts, changed routes and selectors.
3. **Feature map**: `../feature-map/scripts/features.sh check`, then `stale --write`, then `run` on the stale ones. `coverage` shows code that no feature owns. Report it; assigning it is the human's call.
4. **Map freshness**: commits since map's `source-commit` that touched modules listed in it.
5. **Gates**: every `deny:`/`ask:` regex compiles (`grep -E`), and still matches something real in the repo's scripts or docs.
6. **Taste**: entries contradicted by recent code, where the repo consistently does the opposite. These are candidates for the human.

## Report and fix

```
tend · 6 skills · 4 ok · 2 need work
✗ verify-api: self-test fails: scripts/up.sh uses port 3000, app now on 8080 (src/server.ts:12)
✗ playbook add-endpoint: step 3 references src/routes/index.ts (moved to src/http/routes.ts in a1b2c3)
~ map.md: 61 commits since source-commit; 2 modules changed
```

Propose all fixes as one batch. After approval, apply them, re-run the self-tests, and bump `generated-at` and `source-commit`. Anything that can't be fixed confidently becomes a question to the human, not a guess.
