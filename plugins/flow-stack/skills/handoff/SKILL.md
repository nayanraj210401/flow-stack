---
name: handoff
description: Write HANDOFF.md so a fresh session resumes cold; /handoff resume loads it. Use for "context is getting full", "continue tomorrow", phase boundaries.
---

# handoff: resume from files, not memory

A compacted conversation keeps a lossy summary. A handoff keeps what the next session needs, chosen on purpose.

## Write

Fill `.flow/tasks/<slug>/HANDOFF.md` from the template (it replaces any previous one). Keep it to at most 40 lines:
- **Goal**: one line from INTENT.
- **Done**: slice · what · evidence label. Only what EVIDENCE backs.
- **Next**: the single next action, concrete enough to start cold ("make S3's check pass: rate-limit.spec 'resets after window' fails because refill uses wall clock at src/limit.ts:58").
- **Open questions / gates**: exactly what's waiting on the human.
- **Traps**: what cost time this session. Wrong assumptions, flaky commands, misleading files. This is the most valuable section.
- **Pointers**: `file:line` references the next session needs. Nothing else.

Then tell the human in 2 lines: the handoff is written, and they should start a new session with `/flow resume` (or `/clear` then `/flow resume`).

The PreCompact hook writes `HANDOFF.auto.md` (a mechanical snapshot) automatically. Your hand-written HANDOFF.md is better. Write it before compaction when you can.

## Resume (`/handoff resume`, or via `/flow resume`)

1. `../flow/scripts/task.sh active`, then read HANDOFF.md (or HANDOFF.auto.md when newer), INTENT.md, and SLICES.md. Nothing else yet.
2. Re-run the current slice's check through `evidence.sh` to confirm the state matches the handoff. Code may have changed in between.
3. Say in one line where you are resuming, then continue.
