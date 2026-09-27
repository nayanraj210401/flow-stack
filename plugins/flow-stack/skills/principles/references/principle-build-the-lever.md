# Build the lever

**Rule.** When the work repeats, write the script that does it. The script is the reviewable artifact, and it can be re-run.

**Why.** Hand edits drift, miss cases, and can't be reviewed as a unit. Reviewing a 20-line codemod is easier than reviewing 300 identical hunks.

**Bad.** Hand-editing 140 call sites to add a parameter.

**Good.** A 25-line codemod in the task folder, run once, with the suite green after. `tour` marks the 140 hunks "safe to skip: codemod output".

**Check yourself.** Am I doing the same edit a sixth time?
