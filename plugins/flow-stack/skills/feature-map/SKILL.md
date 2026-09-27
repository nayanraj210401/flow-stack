---
name: feature-map
description: "Build and maintain .flow/features/: one file per user-facing feature with sub-feature IDs, every entry point, the code it owns, a scenario, and proof. flow, intent, verify, tour, and tend use it to know which features a change touches. Use for /feature-map, \"map the features\", or when a change touches a feature the map lacks."
---

# feature-map: what this repo does, and how to prove each part

The feature map is the repo's maintained, user-level answer to two questions: **what can a user do here**, and **how do we prove each thing still works**. It links every feature to the code it `owns`, so a diff maps to the features it touches (`scripts/features.sh impact`). flow-stack then verifies exactly those features, through every entry point, instead of guessing or running everything.

Scripts are relative to this skill's base directory. The format is in [references/feature-template.md](references/feature-template.md); a filled example is in [references/example/](references/example/).

## Build (first time)

1. **Inventory from the repo, not the human.** Read `.flow/map.md` (run `map` first if it's missing). Collect user-facing capabilities from:
   - routes and API handlers,
   - CLI commands,
   - UI pages and menus,
   - public exports (for a library),
   - scheduled jobs and consumers,
   - docs and README feature lists.
   Group them by what the *user* does, not by module. "Log in" is one feature even if it spans three directories.
2. **Pick IDs.** Lowercase and dotted by area: `auth.login`, `billing.invoice.pdf`. Sub-features extend the ID (`auth.login.lockout`). IDs are permanent: checks, traces, and evidence cite them.
3. **Write one file per feature**, starting from the template (`scripts/features.sh new <id> "<title>"`), and fill:
   - `owns:` the globs of the code behind it, tests included. They must be specific enough that `impact` doesn't flag every feature on every change.
   - `entries:` **every** way a user reaches it (web, API, CLI, shortcut, deep link). A proof through one entry point is incomplete when others exist.
   - Sub-features: one line each, an observable behavior.
   - Driving it and Proof: the steps and the observable end state, including one absence ("no cookie is set").
   - `scenario:` the command that proves it. Usually a script in the verify driver; leave it empty until `make-verifier` writes it.
   Aim for the 5 to 10 most important features first; completeness comes through `coverage`.
4. **Check it.**
   - `scripts/features.sh check` must pass.
   - `scripts/features.sh coverage` lists unowned code. Assign it to a feature, or put truly non-feature paths (build scripts, generated code) in `.flow/features/.ignore`.
   - `scripts/features.sh index` regenerates the README table.
5. **Prove it.** If a verify driver exists, `scripts/features.sh run --all` marks the passing features verified. If not, suggest `/flow-stack:make-verifier`, which writes one scenario per feature.
6. Offer to commit `.flow/features/`. It's shared team knowledge.

## Keep it current (flow runs this at Close)

- **A task added a feature or sub-feature**: add or extend its file, and give the new sub-feature an ID the task's checks already cite.
- **A task moved code**: update `owns:`. `check` flags globs that match nothing.
- **A task changed an entry point**: update `entries:` and the scenario.
- **Periodically, or via `tend`**: `features.sh stale --write`, then `features.sh run` the stale ones.

## How other skills use it

| Skill | Uses |
|---|---|
| flow | `impact` during Understand; the feature IDs go in the route line; Close updates the map |
| intent | acceptance checks cite feature and sub-feature IDs (`C1 · auth.login.lockout · …`) |
| slice | fences start from the touched features' `owns:` |
| verify | `run --impacted` after the acceptance checks; every listed entry point |
| review | an impacted feature with no check or scenario run is a finding |
| tour | groups the diff by feature |
| make-verifier | writes one scenario per feature and sets `scenario:` |
| tend | `stale`, `coverage`, `check`, then re-run the stale scenarios |
