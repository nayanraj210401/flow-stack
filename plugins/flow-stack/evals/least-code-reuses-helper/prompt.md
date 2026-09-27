---
description: Delete > add. The agent reuses an existing helper instead of writing a new one, and creates no new files.
max_turns: 12
allowed_tools: [Read, Glob, Grep, Edit, Write, Skill]
---

Add a `make_filename` function to src/export.sh that turns a report title into a safe file name: lowercase, words joined by dashes, no punctuation, ending in ".csv". Example: "Q3 Sales: Final!" → "q3-sales-final.csv".
