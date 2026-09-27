# Slices · {{slug}}
<!-- One block per slice, in delivery order. Exactly one slice is `doing` at a time.
     status: todo | doing | done | blocked
     check:  command that proves this slice (run via verify's evidence.sh)
     fence:  repo-relative globs this slice may edit; the fence hook enforces it
     budget: max changed lines (added + removed)
     red:    omit, or "n/a <reason>" when the check can't fail first (e.g. a refactor pin)
     teeth:  omit, or "n/a <reason>" when probing can't apply
     "done" is gated by task.sh: red first, green after the last edit, probe TEETH, budget. -->

## S1 · 
status: todo
check: 
fence: 
budget: 150
