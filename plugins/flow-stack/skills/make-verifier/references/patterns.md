# Driver patterns

Every scenario script: `set -euo pipefail`, prints what it did, exits non-zero on failure, and writes artifacts to `${FLOW_ARTIFACTS:-.flow/artifacts}/`.

## CLI
- Build once, run the binary with realistic args in a temp dir (`mktemp -d`), and assert on stdout, the exit code, and the files produced.
- Cover `--help`, the happy path, one bad-input path, and one idempotency path (run twice).

## HTTP service
- `up.sh`: start in the background, write the PID to `.flow/run/<name>.pid`, and poll `/health` (or the first route) until 200, with a timeout.
- Scenarios: `curl -sS -o resp.json -w '%{http_code}'`, then assert the status plus `jq` assertions on the body. Save the response as an artifact.
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
