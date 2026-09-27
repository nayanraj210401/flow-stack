---
description: feature-map builds a valid map (one file per user-facing feature, sub-feature IDs, entries, owns) that passes features.sh check.
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Edit, Write, Bash, Skill]
append_system_prompt: "The user is away; don't ask questions. There is no verify driver; leave scenario empty where you can't write one."
---

/flow-stack:feature-map build the feature map for this repo.
