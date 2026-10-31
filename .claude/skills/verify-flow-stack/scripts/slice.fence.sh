#!/usr/bin/env bash
# slice.fence: while a slice is `doing`, Edit/Write outside its fence is denied.
. "$(dirname "$0")/lib.sh"; sandbox slice.fence
toy_task demo "mul multiplies" "no division"
toy_slice demo S1 doing "bash tests/test_mul.sh" "src/calc.sh tests/**"

expect edit-guard.sh "$(edit "$PWD/src/calc.sh")" allow "inside fence: src/calc.sh"
expect edit-guard.sh "$(edit "$PWD/tests/deep/test_x.sh" Write)" allow "inside fence: tests/** (Write, nested)"
expect edit-guard.sh "$(edit "$PWD/src/other.sh")" deny "outside fence: src/other.sh"
has "$OUT" "outside slice S1's fence" && ok "reason names the slice" || bad "reason: $OUT"
expect edit-guard.sh "$(edit "$PWD/.flow/tasks/demo/DECISIONS.tsv")" allow "bookkeeping in .flow/"
expect edit-guard.sh "$(edit "/tmp/outside-repo.txt")" allow "outside the repo"
echo "-- dot segments are resolved before the fence is judged"
expect edit-guard.sh "$(edit "$PWD/src/../docs/a.md")" deny "src/../docs/a.md leaves the fence"
expect edit-guard.sh "$(edit "src/../docs/a.md")" deny "relative src/../docs/a.md leaves the fence"
expect edit-guard.sh "$(edit "$PWD/tests/../src/other.sh")" deny "tests/../src/other.sh leaves the fence"
expect edit-guard.sh "$(edit "src/../../outside.txt")" deny "climbing above the root is outside every fence"
expect edit-guard.sh "$(edit "$PWD/src/../tests/a.test.sh")" allow "src/../tests/a.test.sh lands inside tests/**"
expect edit-guard.sh "$(edit "$PWD/src/./calc.sh")" allow "src/./calc.sh is src/calc.sh"
expect edit-guard.sh "$(edit "./src/calc.sh")" allow "./src/calc.sh is src/calc.sh"
expect edit-guard.sh "$(edit "$PWD/src//calc.sh")" allow "src//calc.sh is src/calc.sh"
echo "-- no doing slice → no fence"
toy_slice demo S1 todo "bash tests/test_mul.sh" "src/calc.sh"
expect edit-guard.sh "$(edit "$PWD/src/other.sh")" allow "no slice doing"
echo "-- toggle: hooks.fence=false"
toy_slice demo S1 doing "bash tests/test_mul.sh" "src/calc.sh"
jq '.hooks.fence=false' .flow/config.json >c && mv c .flow/config.json
expect edit-guard.sh "$(edit "$PWD/src/other.sh")" allow "fence off"
echo "-- no active task → no fence"
jq '.hooks.fence=true' .flow/config.json >c && mv c .flow/config.json
rm .flow/ACTIVE
expect edit-guard.sh "$(edit "$PWD/src/other.sh")" allow "no active task"
finish
