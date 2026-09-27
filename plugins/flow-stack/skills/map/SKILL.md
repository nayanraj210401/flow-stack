---
name: map
description: Build or refresh .flow/map.md, a cached repo map read at session start instead of re-exploring. Use for /map, "map this repo", "onboard me to this codebase".
---

# map: explore once, reuse every session

Re-exploring a repo every session burns tokens and minutes. A map read at session start costs a few hundred tokens. Principle: `principle-spend-cheap-save-expensive`.

## Build

1. **Stale?** `.flow/map.md` records `source-commit:` near its top. If `git rev-list --count <that>..HEAD` is under about 50, and none of the changed files are in the map's module list, refresh only the changed modules.
2. **Gather** with the best tool available:
   - graphify (if installed): generate the knowledge graph and summarize its top-level communities and hubs.
   - serena (if connected): `get_symbols_overview` per top-level module.
   - Otherwise: Explore subagents, one per top-level directory, each returning ≤ 10 lines.
   Also read: package manifests, CI config, Makefile or scripts, docker-compose, and the top of the README.
3. **Write `.flow/map.md`** at ≤ 150 lines:

```
# Map · <repo>
source-commit: <sha> · generated: <date>

## What this is            (2 lines)
## Run / test / lint       (exact commands)
## Entry points            (file:line · what starts here)
## Modules                 (dir · owns · talks to)
## Data                    (stores, schemas, where migrations live)
## Flows                   (3–5 key request/job paths, one line each with file refs)
## Conventions             (patterns to copy, with an example file for each)
## Hazards                 (generated code, vendored dirs, slow tests, prod-touching scripts)
```

4. Offer to commit it. It is useful to teammates, and to their agents.
5. If `.flow/config.json` has empty `commands`, fill them from what you found.
