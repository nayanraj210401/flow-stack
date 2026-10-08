# Driver patterns

Every scenario: written for the runner `scripts/ecosystem.sh` reports (`node --test`, `pytest`, `bun test`, … or `set -euo pipefail` bash), prints what it did, fails the runner on failure, and writes artifacts to `${FLOW_ARTIFACTS:-<main checkout>/.flow/artifacts}/`; from a linked worktree, find the main checkout with `dirname "$(git rev-parse --path-format=absolute --git-common-dir)"`, so artifacts never land in the worktree.

## Stay inside auto mode
The driver runs unattended, so nothing in it may look like an attack on the user's machine:
- **Stop only what you started.** Spawn the app from the fixture in its own process group (`detached: true`, `start_new_session=True`) and kill that group in teardown, since `npm start` and friends fork; in bash, kill the PID your `up.sh` wrote. Never `pkill`, `killall`, or `kill $(lsof -ti :PORT)`: a process already on the port may be the user's; fail with "port busy" instead.
- **Install only from the lockfile**, with `ecosystem.sh`'s `install` line. No global installs, `curl | sh`, `npx <pkg>` that isn't a dependency, or `pip install` outside the repo's venv.
- **Credentials**: `.env.example` and seed users only. Never read `.env`, keychains, or `~/.config`.
- **Write** only to the repo, `mktemp -d`, and `.flow/artifacts/`. Never to `$HOME`, shell rc files, or `.claude/settings*.json`.
- **Git** read-only in scenarios. Breaking code on purpose (teeth) happens in a throwaway worktree.
- **One plain command per scenario.** No `eval`, base64, or generated-then-executed code; the classifier must be able to read what runs.

## CLI
- Build once, run the binary with realistic args in a temp dir (`mktemp -d`), and assert on stdout, the exit code, and the files produced.
- Cover `--help`, the happy path, one bad-input path, and one idempotency path (run twice).

## HTTP service
- `_app` fixture (`before`/`after` in node:test, a session fixture in pytest): spawn the start command, poll `/health` (or the first route) until 200 with a timeout, and kill the child in teardown. With `runner bash`, `up.sh` does the same in the background and writes the PID to `.flow/run/<name>.pid` for `down.sh`.
- Scenarios: request with the language's own client (`fetch`, `httpx`/`urllib`; `curl -sS -w '%{http_code}'` + `jq` in bash), assert the status and the body fields, and save the response as an artifact.
- Auth: log in through the real endpoint with the seed user and reuse the cookie or token file.

## Web UI
- Prefer Playwright. Either:
  - **Playwright MCP** (interactive): the SKILL.md lists the pages, the selectors that matter (by role/label, not CSS), and the steps; the agent drives it and saves screenshots.
  - **Playwright script** (repeatable): `npx playwright test <scenario>.spec.ts --reporter=line` with `trace: 'retain-on-failure'`; scenarios live in the driver dir, not the app's test suite.
- Always capture a screenshot of the end state as the artifact. Check the empty, loading, and error states for the feature touched.
- Use the dev server from the run driver, not a production build, unless the bug is build-specific.

## Mobile
- iOS: `xcrun simctl` boot/install/launch, plus screenshots via `simctl io booted screenshot`. Android: `adb` + `emulator`. Deep links to reach screens directly.
- If UI automation isn't set up, the driver covers launch and deep-link screenshots only, and says so in its gaps.

## Library
- A scratch consumer: a temp project that installs the package from the working tree (npm pack / pip install -e / go workspace) and calls the public API the way users do.

## Worker / queue
- Enqueue a real message against a local broker (docker compose), wait for the side effect (a db row, a file, a log line), and assert it.

## Data pipeline
- Run on a small fixture slice with `--dry-run` or into a scratch schema, and assert row counts, schema, and one known-value spot check. Never touch production.
