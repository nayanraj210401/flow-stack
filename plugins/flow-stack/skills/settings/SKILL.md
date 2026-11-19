---
name: settings
description: "See and change flow-stack's settings: turn default hooks on or off, and set how much of the test suite verification runs. /flow-stack:settings [show|hook <name> on|off|default|tests scope impacted|full]."
disable-model-invocation: true
---

# settings

Your settings live in `~/.flow-stack/settings.json` and apply to every repo. A repo's committed `.flow/config.json` sets the same keys for the team and wins. Paths are relative to this skill's base directory.

```bash
scripts/settings.sh                          # every hook: on/off, which file says so, what it guards; the test settings
scripts/settings.sh hook claims off          # in settings.json; add --repo for this repo's .flow/config.json
scripts/settings.sh hook claims default      # drop the key, so the next layer (or on) decides
scripts/settings.sh tests scope full         # impacted (default): only the suites a change touches
scripts/settings.sh tests unmatched skip     # a change no suite claims: full (default) or skip
scripts/settings.sh chapters format slides   # the chapters page: scroll (default), slides, or rounds
scripts/settings.sh init                     # create settings.json, carrying over ~/.flow-stack/config.json toggles
```

Precedence, first set wins: repo `.flow/config.json` → `~/.flow-stack/settings.json` → `~/.flow-stack/config.json` (older global toggles) → on.

## Commands

- **show** (default): run `scripts/settings.sh` and pass its table on as is. Name anything turned off and what that gives up.
- **hook `<name>` on|off|default**: the human names the hook in their own words ("the evidence hook" is `claims`, "the fence" is `fence`); map it to a name from `show`, then run it. Turning off `guard`, `seal`, `claims`, `fence` or `tdd` removes a safety check: say which one in one line before you write. The guard hook warns you and the human on any hook-off write (never blocks, even in `--auto`). Write `--repo` only when the human says the change is for the repo or the team.
- **tests**: `scope` and `unmatched` decide how much of the suite runs (`../verify/scripts/suites.sh`). The sub-suites are repo-specific, so they go in `.flow/config.json` `tests.suites`, not here: `[{"id": "auth", "paths": ["src/auth/**"], "run": "npm test -- auth"}]`. Lint them with `../verify/scripts/suites.sh check`.

Never edit these files with a hand-written jq or a text editor: `settings.sh` refuses unknown hook names and won't write over invalid JSON.
