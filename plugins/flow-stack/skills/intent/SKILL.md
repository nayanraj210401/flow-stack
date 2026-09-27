---
name: intent
description: "Turn a fuzzy request into INTENT.md: goal, non-goals, runnable acceptance checks, blind checks. Use for /intent, \"define the problem\", \"what exactly are we building\", \"grill me\"."
---

# intent: decide what "done" means before any code

The most expensive bug is building the wrong thing. This skill spends a few minutes of the human's attention up front so none is wasted later. Principle: `principle-intent-before-code`.

## 1. Draft first, ask second

Read the request, the profile's Who section, and the code you learned in Understand. Draft INTENT.md in `.flow/tasks/<slug>/` from the template, filling every section you can. Mark each guess `(?)`.

## 2. Grill, one question at a time

Only ask about what the code, docs, or a quick experiment cannot answer. Before each question, check: *could I find this out by reading or running something?* If yes, do that instead.

Good questions attack:
- **The premise:** "Is rate limiting the fix, or is the real problem one abusive client?"
- **The boundary:** "Per user or per API key? What happens at the 101st request?"
- **The non-goals:** "Is the admin API in scope?"
- **What would surprise them:** "Existing clients retry on 429 with no backoff. Is that acceptable?"

Offer your recommended answer with each question so the human can reply "yes". Stop when the goal, non-goals, and checks are unambiguous. That is usually 2 to 5 questions. Use `AskUserQuestion` when available; batch independent questions into one call.

## 3. Acceptance checks

Each check proves one observable behavior:
- `C1 · 101st request in 60s returns 429 · \`npm test -- rate-limit.spec\``: runnable, preferred.
- `C3 · error message reads well · human-judged: read the 429 body`: only when no command can decide it.

**Bind checks to features.** When `.flow/features/` exists, run `../feature-map/scripts/features.sh impact <paths the change will touch>` and cite sub-feature IDs in the checks (`C1 · auth.login.lockout · 6th failure returns 423 · \`…\``). New behavior gets a new sub-feature ID. A new user-facing capability gets a new feature (`features.sh new`), and that file is written after the intent gate.

Write the check files now, before any code (test files, curl scripts, driver-skill scenarios), so they exist and fail. Then seal them: `../seal/scripts/seal.sh add <paths>`.

## 4. Blind checks

Spawn the `checker` agent (flow-stack:checker) with INTENT.md's Goal, Non-goals, and checks, plus the repo's test conventions. It writes 1 to 3 held-out checks into `.flow/tasks/<slug>/blind/` with a `MANIFEST`, and returns only the count and the behavior area. **Do not read what it wrote**; the read-guard hook denies it anyway. Record the count and area in INTENT.md.

Skip blind checks for tiny tasks and for the bug playbook unless a contract changes. Say that you skipped them.

## 5. Gate

Present in at most 8 lines: Goal, Non-goals, checks (one line each), blind count, open risks. The human approves or edits. Log the approval: `../flow/scripts/task.sh decide human no "intent approved" "<any edits>"`.
