#!/usr/bin/env bash
# test-hollow.sh: end-to-end check for probe.sh --hollow and the new-files-only note.
# Builds a throwaway repo, runs probe.sh against it, exits non-zero on the first miss.
set -uo pipefail
probe="$(cd "$(dirname "$0")" && pwd)/probe.sh"
fail() { echo "FAIL: $*"; exit 1; }

d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
cd "$d" && git init -q && git config user.email t@t && git config user.name t
mkdir -p src tests .flow/tasks/t
echo t > .flow/ACTIVE
printf 'base=1\n' > src/base.sh
git add -A && git commit -qm init

# A new feature: keys() and a test that loops over its output.
printf 'keys() { echo "a b c"; }\n' > src/keys.sh
printf 'a b c\n' > tests/translation.txt
loop='. src/keys.sh || exit 1; for k in $(keys); do grep -qw "$k" tests/translation.txt || exit 1; done'
counted='. src/keys.sh || exit 1; set -- $(keys); [ $# = 3 ] || exit 1; for k in "$@"; do grep -qw "$k" tests/translation.txt || exit 1; done'
before="$(cat src/keys.sh)"

# Revert mode on brand-new code: TEETH, but it must say that only proves the import.
out="$(bash "$probe" loop "$loop" 2>&1)"; code=$?
[ "$code" = 0 ] || fail "revert probe of new file should be TEETH (exit $code): $out"
grep -qi "new file" <<<"$out" || fail "revert probe of only-new files must warn it proves little: $out"

# Hollow mode: empty the output; the looping test still passes -> TOOTHLESS.
out="$(bash "$probe" loop "$loop" --hollow src/keys.sh 'echo "a b c"' 'echo ""' 2>&1)"; code=$?
[ "$code" = 1 ] || fail "hollow probe of a loop-only test should be TOOTHLESS (exit $code): $out"
grep -q "flow-probe: TOOTHLESS" <<<"$out" || fail "missing TOOTHLESS verdict: $out"
[ "$(cat src/keys.sh)" = "$before" ] || fail "hollow probe did not restore src/keys.sh"

# A length-checked test catches the emptied output -> TEETH.
bash "$probe" counted "$counted" --hollow src/keys.sh 'echo "a b c"' 'echo ""' >/dev/null 2>&1 \
  || fail "hollow probe of a length-checked test should be TEETH"
[ "$(cat src/keys.sh)" = "$before" ] || fail "hollow probe did not restore src/keys.sh after TEETH"

# A replacement that matches nothing is a usage error and touches nothing.
bash "$probe" x "true" --hollow src/keys.sh 'no such text' '' >/dev/null 2>&1; code=$?
[ "$code" = 2 ] || fail "unmatched --hollow text should exit 2 (got $code)"

ev=".flow/tasks/t/EVIDENCE.md"
grep -q ' · probe:loop:hollow · TOOTHLESS · ' "$ev" || fail "EVIDENCE lacks probe:loop:hollow TOOTHLESS: $(cat "$ev")"
grep -q ' · probe:counted:hollow · TEETH · ' "$ev" || fail "EVIDENCE lacks probe:counted:hollow TEETH"
echo "ok hollow"
