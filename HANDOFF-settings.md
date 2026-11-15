# Handoff · settings.json hook toggles + impacted test suites

**Branch:** `claude/flow-stack-settings-hooks-dt156j` · **PR:** https://github.com/nayanraj210401/flow-stack/pull/290 · **HEAD:** 3395c4e (pushed)

## Goal
`~/.flow-stack/settings.json` turns default hooks on/off for every repo, and verification runs only the test sub-suites a change touches.

## Done (all in 3395c4e)
- **Hook toggles.** `flow_enabled` reads repo `.flow/config.json` → `~/.flow-stack/settings.json` → legacy `~/.flow-stack/config.json` → on (`plugins/flow-stack/hooks/lib.sh:63`).
- **`/flow-stack:settings` skill** + `skills/settings/scripts/settings.sh`: `show`, `hook <name> on|off|default [--repo]`, `tests scope|unmatched`, `init`, `path`. It has a catalog of 16 hook names, refuses unknown names (`evidence` → points to `claims`), and never writes over invalid JSON.
- **Sub-suites.** `skills/verify/scripts/suites.sh` `list|pick|run|check`. Repos declare them in `.flow/config.json` `tests.suites` (`id`, `paths`, `run`) plus `tests.ignore`. A file no suite claims → full suite (`commands.test`, or every suite if there's none) unless `tests.unmatched: skip`. `tests.scope: full` or `--all` always runs the full suite. Each run goes through `evidence.sh` with label `test:<id>`.
- **Wiring.** `ready.sh` runs the impacted suites when a repo declares any (`skills/review/scripts/ready.sh:95`). The verify and loop SKILL.md files, setup/adapt, conventions.md, README, and the `templates/config.json` `tests` block are updated too.
- **Proof:**
  - `settings.test.sh` and `suites.test.sh` pass. Both fail when the code under test is broken.
  - New feature `.flow/features/settings.md` and its scenario `.claude/skills/verify-flow-stack/scripts/settings.sh` pass. They drive real hook JSON and `ready.sh`.
  - Every scenario from `features.sh run --impacted` passes, and `plugin.install` passes.
  - None of this has been re-run on your machine yet.

## Next
1. `git fetch origin && git checkout claude/flow-stack-settings-hooks-dt156j`
2. Re-run the proof locally (this cloud run was Linux; macOS uses BSD sed and mktemp):
   ```bash
   bash plugins/flow-stack/skills/settings/scripts/settings.test.sh
   bash plugins/flow-stack/skills/verify/scripts/suites.test.sh
   bash .claude/skills/verify-flow-stack/scripts/settings.sh
   ```
3. Check CI and review comments on PR #290.
4. Run `review/scripts/ready.sh`. Review, deslop and tour are **not recorded** for HEAD yet, so it won't stamp until they are. Stamp before marking the PR ready.

## Open questions / gates
- Should this repo declare its own `tests.suites` (dogfooding)? Not done; it's optional.
- PR #290 merge needs your approval.

## Traps
- `plugins/flow-stack/hooks/holds.test.sh` **already fails on the base commit** in the cloud container (stale ⚡ / claim not taken). It isn't caused by this change. Check whether it passes locally.
- In the toy repo the default branch isn't necessarily `main`, so the scenario passes a SHA to `--base`.
- `jq -r` on empty input prints nothing and exits 0, so a test helper that ends in `|| echo allow` never fires the fallback. Use `| grep . || echo allow`.
- Suites are repo-only. `tests.suites` in settings.json is ignored on purpose; only `scope` and `unmatched` are global.
- `holds` also reads a non-boolean top-level `"holds": "hard"` that `settings.sh` doesn't manage.

## Pointers
- `plugins/flow-stack/skills/settings/scripts/settings.sh`: `catalog()` (keep it in sync with the `flow_enabled <name>` calls; `settings.test.sh` enforces this)
- `plugins/flow-stack/skills/verify/scripts/suites.sh`: `pick_raw()` holds the selection logic
- `.flow/features/settings.md`: sub-feature IDs `settings.toggle|layers|catalog|suites|fallback|ready`
