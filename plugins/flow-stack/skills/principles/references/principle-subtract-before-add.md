# Subtract before you add (delete > add)

**Rule.** Before building, run the subtract scan:
1. **Delete**: what dead code, redundant validators, stale flags, or one-caller wrappers sit in the area? Remove them first, in their own step.
2. **Reuse**: `rg` for the verbs and nouns. Does a helper, dependency, or pattern already do this?
3. **Configure**: is this a setting or data change?
Only then add, and add the least code that works.

**Why.** Agents love adding code. Every added line is future reading, testing, and debugging. Deletions are the only changes that make a codebase easier.

**The small leaks** (they compound):
- a pass-through parameter,
- a duplicated decision,
- a second boolean that shadows the first,
- a new file for 10 lines that belong next to their only caller.

**Bad.** A new `utils/formatDate.ts` (+40), when `lib/time.ts:12` already formats dates.

**Good.** The subtract scan finds `lib/time.ts:12` and an unused `legacyFormat()`. Call the former, delete the latter: net −18.

**Check yourself.** Run `../../loop/scripts/diffstat.sh <fence>`. Net positive? Name what the added lines buy that deletion, reuse, or configuration couldn't. New file? Name why it can't live next to its caller.
