---
id: settings
title: Settings: hook toggles and impacted test suites
owns: plugins/flow-stack/skills/settings/** plugins/flow-stack/skills/verify/scripts/suites.sh plugins/flow-stack/skills/verify/scripts/suites.test.sh plugins/flow-stack/templates/config.json .claude/skills/verify-flow-stack/scripts/settings.sh
entries: skill /flow-stack:settings | cli skills/settings/scripts/settings.sh show|hook|tests|init|path | file ~/.flow-stack/settings.json | cli skills/verify/scripts/suites.sh list|pick|run|check | config .flow/config.json tests.suites|tests.ignore|tests.scope|tests.unmatched | cli skills/review/scripts/ready.sh
scenario: bash .claude/skills/verify-flow-stack/scripts/settings.sh
status: unverified
verified:
---
# Settings: hook toggles and impacted test suites

One global file, `~/.flow-stack/settings.json`, turns any of flow-stack's default hooks on or off for every repo, and sets how much of the test suite verification runs. A repo declares test sub-suites by path in `.flow/config.json`, and verification runs only the ones a change touches.

## Sub-features
- settings.toggle · `hooks.<name>: false` in settings.json silences that hook; `settings.sh hook <name> off|on|default` writes it
- settings.layers · repo `.flow/config.json` beats settings.json, which beats the older `~/.flow-stack/config.json`; `show` names the deciding file
- settings.catalog · `show` lists every hook name a hook checks; an unknown name (e.g. `evidence`) is refused and points at `claims`
- settings.suites · `suites.sh run` runs only the suites whose `paths` the change touches, each through evidence.sh (`test:<id>`)
- settings.fallback · an unclaimed changed file, `tests.scope: full`, or `--all` runs the full suite (`commands.test`); `tests.unmatched: skip` skips unclaimed files
- settings.ready · ready.sh runs the impacted suites when the repo declares any, and a failing suite blocks the stamp

## How to get to it
- `/flow-stack:settings`, or `skills/settings/scripts/settings.sh` directly.
- `skills/verify/scripts/suites.sh run` from verify and loop; `ready.sh` before a PR.

## Driving it
`.claude/skills/verify-flow-stack/scripts/settings.sh` pipes real PreToolUse/Stop payloads to the hooks with each layer set, then runs `suites.sh` and `ready.sh` in a toy repo with two suites.

## Proof
- the guard's decision on `git push --force origin main` flips from ask/deny to allow with `hooks.guard: false` in settings.json, and back with `default`.
- a change under one suite's paths writes only that suite's mark; the full suite's mark must not appear.

## Gotchas
- Hook toggles are booleans; `holds` also reads a top-level `"holds": "hard"` that settings.sh doesn't manage.
- `settings.sh` won't write over invalid JSON; a hook reading invalid JSON treats the key as unset (on).
- Suites are repo-specific: `tests.suites` in settings.json is ignored.
