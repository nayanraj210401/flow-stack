---
id: scripts.quiet
title: Scripts and test suites are quiet on pass
owns: plugins/flow-stack/hooks/*.test.sh plugins/flow-stack/skills/**/*.test.sh plugins/flow-stack/skills/review/scripts/ready.sh plugins/flow-stack/skills/make-routines/scripts/routines.sh
entries: cli bash <any>.test.sh | cli ready.sh [-v] | cli routines.sh check [-v]
scenario: bash .claude/skills/verify-flow-stack/scripts/scripts.quiet.sh
status: unverified
verified:
---
# Scripts and test suites are quiet on pass

flow-stack's own test suites and scripts used to print every passing assertion (`✓ …`) back as tool output, and every byte stayed in context; bash results totalled 8.4M characters in 14 days. Now a passing run prints one short summary line (usually `<suite>: N passed`; the exact wording varies by suite), detail only on failure, and `ready.sh` / `routines.sh check` print a short summary by default with the full detail behind `-v`. The `flow-evidence: PASS` and `ready for review: <sha> stamped` last-line contracts are unchanged.

## Sub-features
- scripts.quiet.suite · a passing `*.test.sh` prints ≤ 3 lines (the summary); a failing run still shows each `✗`
- scripts.quiet.ready · `ready.sh` prints the header + `ready for review: <sha> stamped` on pass, `✓` detail only with `-v`
- scripts.quiet.routines · `routines.sh check` prints `N routines in sync`, `✓` detail only with `-v`

## How to get to it
- Run any `*.test.sh`; run `ready.sh -v` for the full bar; run `routines.sh check -v` for per-routine detail.

## Driving it
Every script test in `.github/workflows/test.yml` runs on push/PR; a passing run now emits one line. `.claude/skills/verify-flow-stack/scripts/scripts.quiet.sh` runs `redact.test.sh` (passes quiet, exit 0), then a copy with `redact()` broken (shows `✗`, exits non-zero).

## Proof
- a passing run of each suite prints ≤ 3 lines and exits 0; a failing suite shows its `✗` lines and a non-zero exit.

## Gotchas
- `ready.sh -v` and `routines.sh check -v` restore the per-check detail; a failing run always prints its `✗` lines and exits nonzero.
- Section headers in test suites are `#` comments, not `echo`, so a passing suite prints one line.
