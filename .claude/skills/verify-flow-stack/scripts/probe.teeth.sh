#!/usr/bin/env bash
# probe.teeth: probe.sh reverts the uncommitted source change, reruns the check,
# restores everything, and says TEETH (check failed without the change) or TOOTHLESS.
. "$(dirname "$0")/lib.sh"; sandbox probe.teeth
P="$S/probe/scripts/probe.sh"

sees "clean tree → SKIPPED" "flow-probe: SKIPPED" "$P" x "bash tests/test_add.sh"

echo "-- toothless: the check passes without the change"
toy_task demo "mul multiplies" "no division"
echo '# a comment' >>src/calc.sh
sees "comment-only change → TOOTHLESS" "flow-probe: TOOTHLESS" "$P" S1 "bash tests/test_add.sh"
fails "TOOTHLESS exits non-zero" "$P" S1 "bash tests/test_add.sh"
grep -qE '^### .* · probe:S1 · TOOTHLESS' .flow/tasks/demo/EVIDENCE.md && ok "TOOTHLESS recorded" || bad "no probe row"

echo "-- teeth: the check needs the change"
git checkout -q src/calc.sh
printf 'mul() { echo $(( $1 * $2 )); }\n' >>src/calc.sh
printf '. src/calc.sh\n[ "$(mul 2 3)" = 6 ]\n' >tests/test_mul.sh      # test paths are kept
printf 'helper() { :; }\n' >src/new_helper.sh                          # untracked source is reverted too
before="$(shasum src/calc.sh src/new_helper.sh tests/test_mul.sh)"
sees "real change → TEETH" "flow-probe: TEETH" "$P" S2 "bash tests/test_mul.sh"
check "TEETH exits 0" "$P" S2 "bash tests/test_mul.sh"
[ "$(shasum src/calc.sh src/new_helper.sh tests/test_mul.sh)" = "$before" ] && ok "all files restored byte-for-byte" || bad "restore differs"
sees "reports what it reverted" "reverted 2 source file(s)" "$P" S2 "bash tests/test_mul.sh"

echo "-- colliding stash names keep every file"
git checkout -q src/calc.sh; rm -f src/new_helper.sh tests/test_mul.sh
mkdir -p src/a src/a__b
echo base1 >src/a/b__c.sh; echo base2 >src/a__b/c.sh; git add -A; git commit -qm collide
echo USER1 >src/a/b__c.sh; echo USER2 >src/a__b/c.sh
sees "colliding tracked paths → reverted 2" "reverted 2 source file(s)" "$P" S4 "true"
[ "$(cat src/a/b__c.sh)/$(cat src/a__b/c.sh)" = "USER1/USER2" ] && ok "both colliding edits restored" || bad "colliding edit lost"
git checkout -q src/a/b__c.sh src/a__b/c.sh
echo NEW1 >src/a/n__x.sh; mkdir -p src/a__n; echo NEW2 >src/a__n/x.sh
sees "colliding untracked paths → reverted 2" "reverted 2 source file(s)" "$P" S5 "true"
[ "$(cat src/a/n__x.sh)/$(cat src/a__n/x.sh)" = "NEW1/NEW2" ] && ok "both untracked files restored" || bad "untracked file lost"
rm -rf src/a/n__x.sh src/a__n
echo "-- colliding hollow targets keep every file"
echo 'H1 one' >src/a/b__c.sh; echo 'H2 two' >src/a__b/c.sh
"$P" S6 "true" --hollow src/a/b__c.sh one 1 --hollow src/a__b/c.sh two 2 >/dev/null 2>&1 || true
[ "$(cat src/a/b__c.sh)/$(cat src/a__b/c.sh)" = "H1 one/H2 two" ] && ok "hollowed files restored" || bad "hollow restore wrong"
git checkout -q src/a/b__c.sh src/a__b/c.sh

echo "-- --keep leaves a path in place"
sees "--keep src → nothing to revert" "flow-probe: SKIPPED" "$P" S3 "true" --keep src
cp .flow/tasks/demo/EVIDENCE.md "$ART/EVIDENCE.md"
finish
