#!/usr/bin/env bash
# tdd.phase: opt-in TDD lock. task.sh tdd <id> red → only tests are editable; green (after a
# fresh failing run) → tests are locked, implementation is editable; off → no lock.
. "$(dirname "$0")/lib.sh"; sandbox tdd.phase
T="$S/flow/scripts/task.sh"; E="$S/verify/scripts/evidence.sh"
toy_task demo "mul multiplies" "no division"
toy_slice demo S1 doing "bash tests/test_mul.sh" "src/** tests/**"
printf '. src/calc.sh\n[ "$(mul 2 3)" = 6 ] || exit 1\n' > tests/test_mul.sh

echo "-- off by default: no lock"
expect edit-guard.sh "$(edit "$PWD/tests/test_mul.sh")" allow "no tdd: test edit"
expect edit-guard.sh "$(edit "$PWD/src/calc.sh")" allow "no tdd: impl edit"

echo "-- red: tests only"
sees "tdd red starts" "S1 → red" "$T" tdd S1 red
expect edit-guard.sh "$(edit "$PWD/tests/test_mul.sh")" allow "red: test edit"
expect edit-guard.sh "$(edit "$PWD/src/calc.sh")" deny "red: impl edit"
has "$OUT" "task.sh tdd S1 green" && ok "red reason says how to move on" || bad "reason: $OUT"
expect edit-guard.sh "$(edit "$PWD/.flow/tasks/demo/DECISIONS.tsv")" allow "red: bookkeeping"

echo "-- green needs a failing run made during red"
fails "green refused without a red FAIL" "$T" tdd S1 green
"$E" S1:red >/dev/null 2>&1 || true
sees "green after the red FAIL" "S1 → green" "$T" tdd S1 green
expect edit-guard.sh "$(edit "$PWD/src/calc.sh")" allow "green: impl edit"
expect edit-guard.sh "$(edit "$PWD/tests/test_mul.sh")" deny "green: test edit"
has "$OUT" "locked" && ok "green reason says tests are locked" || bad "reason: $OUT"
expect edit-guard.sh "$(edit "$PWD/tests/helpers/fixture.sh" Write)" deny "green: new file under tests/"
expect edit-guard.sh "$(edit "$PWD/src/calc.test.js" Write)" deny "green: *.test.* file"
expect guard.sh "$(bashcmd "echo 'exit 0' > tests/test_mul.sh")" deny "green: shell redirect into a test"
expect guard.sh "$(bashcmd "sed -i '' s/6/5/ tests/test_mul.sh")" deny "green: sed -i on a test"
expect guard.sh "$(bashcmd "bash tests/test_mul.sh > /tmp/out.txt")" allow "green: running a test is fine"
expect guard.sh "$(bashcmd "rm -rf .pytest_cache && bash tests/test_mul.sh")" allow "green: rm elsewhere, then run a test"
expect guard.sh "$(bashcmd "cp tests/test_mul.sh /tmp/copy.sh")" allow "green: a test as cp source"
expect guard.sh "$(bashcmd "sed -i '' s/a/b/ src/calc.sh; bash tests/test_mul.sh")" allow "green: sed -i on code, then run a test"
expect guard.sh "$(bashcmd "bash tests/committee_test.sh")" allow "green: 'tee' inside a word"
expect guard.sh "$(bashcmd "echo x | tee -a tests/test_mul.sh")" deny "green: tee into a test"
expect guard.sh "$(bashcmd "cp /tmp/x.sh tests/test_mul.sh")" deny "green: cp onto a test"
expect guard.sh "$(bashcmd "rm tests/test_mul.sh")" deny "green: rm a test"
expect guard.sh "$(bashcmd "sed -i '' 's/test/check/g' src/calc.sh")" allow "green: sed script mentioning test, on code"
expect guard.sh "$(bashcmd "sed -i -e s/6/5/ tests/test_mul.sh")" deny "green: sed -e on a test"
expect guard.sh "$(bashcmd "(rm tests/test_mul.sh)")" deny "green: rm in a subshell"
expect guard.sh "$(bashcmd "git checkout -- tests/test_mul.sh")" deny "green: git checkout a test"

echo "-- back to red needs a fresh FAIL before green again"
sees "back to red" "S1 → red" "$T" tdd S1 red
fails "old red FAIL does not count" "$T" tdd S1 green
sees "green --force logs a reason" "forced" "$T" tdd S1 green --force "test had a typo"
grep -q "tdd green without a fresh red" .flow/tasks/demo/DECISIONS.tsv && ok "force logged" || bad "force not logged"

echo "-- slice field tests: narrows what counts as a test"
printf 'tests: checks/**\n' >> .flow/tasks/demo/SLICES.md
expect edit-guard.sh "$(edit "$PWD/checks/mul.sh")" deny "green: custom tests: glob is locked"
expect edit-guard.sh "$(edit "$PWD/tests/test_mul.sh")" allow "green: tests: replaces the default patterns"

echo "-- off ends the lock and is logged"
sees "tdd off" "off" "$T" tdd off
grep -q "TDD lock off" .flow/tasks/demo/DECISIONS.tsv && ok "off logged" || bad "off not logged"
expect edit-guard.sh "$(edit "$PWD/tests/test_mul.sh")" allow "off: test edit"

echo "-- toggle: hooks.tdd=false"
"$T" tdd S1 red >/dev/null
jq '.hooks.tdd=false' .flow/config.json >c && mv c .flow/config.json
expect edit-guard.sh "$(edit "$PWD/src/calc.sh")" allow "tdd hook off"
finish
