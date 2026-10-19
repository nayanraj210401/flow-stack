#!/usr/bin/env bash
# glob-match.test.sh: lib.sh glob_match lets `**/` match zero or more directories, `*` and `**`
# still cross directories, and flow_is_test honours such globs (#28).
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/glob-match.XXXXXX")"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
# shellcheck source=/dev/null
. "$H/lib.sh"

# m <yes|no> <path> <glob>
m() {
  local got=no; glob_match "$2" "$3" && got=yes
  if [ "$got" = "$1" ]; then ok "$2 ~ $3 → $1"; else bad "$2 ~ $3 → got $got, want $1"; fi
}

echo "-- **/ matches zero directories"
m yes src/a.ts       'src/**/*.ts'
m yes a.ts           '**/*.ts'
m yes tests/api/x.sh 'tests/**/api/**/x.sh'
m yes src/x/a.ts     'src/**/x/**/*.ts'

echo "-- ** and * still cross directories"
m yes src/b/c/a.ts   'src/**/*.ts'
m yes src/b/a.ts     'src/**/*.ts'
m yes tests/api/v1/x 'tests/api/**'
m yes src/b/a.ts     'src/*.ts'

echo "-- non-matches stay non-matches"
m no  lib/a.ts       'src/**/*.ts'
m no  src/a.js       'src/**/*.ts'
m no  srcx/a.ts      'src/**/*.ts'
m no  a.ts           'src/**/*.ts'

echo "-- flow_is_test with a **/ glob"
flow_is_test src/a.spec.ts 'tests/api/** src/**/*.spec.ts' && ok "src/a.spec.ts is a test" || bad "src/a.spec.ts not a test"
flow_is_test src/a.ts 'tests/api/** src/**/*.spec.ts' && bad "src/a.ts counted as a test" || ok "src/a.ts is not a test"

[ "$FAILS" -eq 0 ] && { echo "== glob-match · PASS"; exit 0; }
echo "== glob-match · FAIL ($FAILS)"; exit 1
