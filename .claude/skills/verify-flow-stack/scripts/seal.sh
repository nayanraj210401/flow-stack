#!/usr/bin/env bash
# seal: lock acceptance checks (seal.sh) and prove both guards make edits to
# sealed files a human decision, while normal source edits stay free.
. "$(dirname "$0")/lib.sh"; sandbox seal
toy_task demo "mul multiplies" "no division"
toy_mul_check
T=.flow/tasks/demo; SEAL="$S/seal/scripts/seal.sh"

echo "-- seal.sh"
sees "list shows the sealed check" "tests/test_mul.sh" "$SEAL" list
sees "verify: intact" "seals intact (1 files)" "$SEAL" verify
echo "-- edit-guard (Edit/Write tool)"
expect edit-guard.sh "$(edit "$PWD/tests/test_mul.sh")" ask "Edit sealed check"
expect edit-guard.sh "$(edit "$PWD/$T/INTENT.md")" ask "Edit sealed INTENT.md"
expect edit-guard.sh "$(edit "$PWD/src/calc.sh")" allow "Edit source (not sealed)"
echo "-- dot segments do not skip the seal"
expect edit-guard.sh "$(edit "$PWD/src/../tests/test_mul.sh")" ask "src/../tests/test_mul.sh is the sealed check"
expect edit-guard.sh "$(edit "tests/./test_mul.sh")" ask "tests/./test_mul.sh is the sealed check"
expect edit-guard.sh "$(edit "$PWD/tests/x/../test_mul.sh")" ask "tests/x/../test_mul.sh is the sealed check"
expect edit-guard.sh "$(edit "$PWD/tests/../src/calc.sh")" allow "tests/../src/calc.sh is plain source"
echo "-- guard (shell writes)"
expect guard.sh "$(bashcmd "sed -i '' 's/6/7/' tests/test_mul.sh")" ask "sed -i on sealed check"
expect guard.sh "$(bashcmd "echo x > $T/SEALS")" ask "overwrite SEALS"
expect guard.sh "$(bashcmd "$SEAL reseal")" ask "seal.sh reseal"
expect guard.sh "$(bashcmd "cat tests/test_mul.sh")" allow "read sealed check"
echo "-- tamper detection"
echo "# tampered" >>tests/test_mul.sh
fails "verify fails after a change" "$SEAL" verify
sees "verify names the changed file" "CHANGED  tests/test_mul.sh" "$SEAL" verify
check "reseal (approved change)" "$SEAL" reseal
check "verify intact again" "$SEAL" verify
rm tests/test_mul.sh
sees "verify flags a deleted check" "MISSING  tests/test_mul.sh" "$SEAL" verify
check "rm unseals" "$SEAL" rm tests/test_mul.sh
[ -z "$(awk '{print $2}' "$T/SEALS")" ] && ok "SEALS empty after rm" || bad "SEALS still lists: $(cat "$T/SEALS")"
echo "-- prefix paths"
mkdir -p tests && echo a >tests/foo.test.ts && echo b >tests/foo.test
check "seal the longer name" "$SEAL" add tests/foo.test.ts
check "seal its prefix" "$SEAL" add tests/foo.test
sees "list keeps the longer-named seal" "tests/foo.test.ts" "$SEAL" list
check "re-adding the same path" "$SEAL" add tests/foo.test
[ "$(awk '$2 == "tests/foo.test"' "$T/SEALS" | wc -l | tr -d ' ')" = 1 ] && ok "one seal line per path" || bad "duplicate seal lines: $(cat "$T/SEALS")"
echo z >>tests/foo.test.ts
sees "edit to the longer-named file is detected" "CHANGED  tests/foo.test.ts" "$SEAL" verify
check "rm of the prefix" "$SEAL" rm tests/foo.test
sees "rm of the prefix keeps the longer-named seal" "tests/foo.test.ts" "$SEAL" list
echo "-- toggle: hooks.seal=false"
toy_mul_check
jq '.hooks.seal=false' .flow/config.json >c && mv c .flow/config.json
expect edit-guard.sh "$(edit "$PWD/tests/test_mul.sh")" allow "Edit sealed check with seal off"
finish
