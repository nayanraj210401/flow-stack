#!/usr/bin/env bash
# evidence.record: evidence.sh runs a check, appends a block to the active task's
# EVIDENCE.md, and ends with the machine-readable verdict line the circuit breaker reads.
. "$(dirname "$0")/lib.sh"; sandbox evidence.record
EV="$S/verify/scripts/evidence.sh"

echo "-- no active task: runs, doesn't record"
sees "prints PASS" "flow-evidence: PASS" "$EV" C1 "bash tests/test_add.sh"
sees "says not recorded" "no active task; result not recorded" "$EV" C1 "bash tests/test_add.sh"

toy_task demo "mul multiplies" "no division"
E=.flow/tasks/demo/EVIDENCE.md
echo "-- PASS is recorded with command, head, and artifact"
rc=0; out="$("$EV" smoke "bash tests/test_add.sh" out/report.txt 2>&1)" || rc=$?
[ $rc -eq 0 ] && ok "exit 0 on pass" || bad "exit $rc"
has "$out" "ok add" && ok "shows the check's output tail" || bad "output: $out"
grep -qE '^### .* · smoke · PASS · exit=0$' "$E" && ok "EVIDENCE header row" || bad "no PASS row"
grep -qF -- '- cmd: `bash tests/test_add.sh`' "$E" && ok "command recorded" || bad "no cmd line"
grep -qF -- '- artifact: out/report.txt' "$E" && ok "artifact recorded" || bad "no artifact line"
grep -qE -- '^- head: [0-9a-f]+  dirty: (yes|no)' "$E" && ok "head + dirty recorded" || bad "no head line"

echo "-- a check that can't fail is refused"
for c in "" "  " ":" "true" "exit 0"; do
  rc=0; "$EV" smoke "$c" >/dev/null 2>&1 || rc=$?
  [ $rc -eq 2 ] && ok "refuses '$c'" || bad "'$c' exited $rc"
done
[ "$(grep -c '^### ' "$E")" -eq 1 ] && ok "no no-op row recorded" || bad "a no-op was recorded"

echo "-- C<n>/S<n> run the command the task declares"
rc=0; "$EV" C1:before >/dev/null 2>&1 || rc=$?
[ $rc -ne 2 ] && grep -qE '^### .* · C1:before · FAIL' "$E" && grep -qF -- '- cmd: `bash tests/test_mul.sh`' "$E" && ok "C1:before with no command runs C1's declared command" || bad "C1:before exit $rc"
rc=0; out="$("$EV" C1 "bash tests/test_add.sh" 2>&1)" || rc=$?
[ $rc -eq 2 ] && has "$out" 'bash tests/test_mul.sh' && ok "C1 with another command refused, names the declared one" || bad "C1 rebinding: exit $rc: $out"
rc=0; "$EV" C1 "bash tests/test_mul.sh" >/dev/null 2>&1 || rc=$?
[ $rc -ne 2 ] && ok "C1 with its own command runs" || bad "C1 own command exit $rc"
toy_slice demo S1 doing "bash tests/test_add.sh" "src/**"
rc=0; "$EV" S1 >/dev/null 2>&1 || rc=$?
[ $rc -eq 0 ] && grep -qE '^### .* · S1 · PASS' "$E" && ok "S1 runs the slice's check:" || bad "S1 exit $rc"
toy_slice demo S1 doing "true" "src/**"
rc=0; "$EV" S1 >/dev/null 2>&1 || rc=$?
[ $rc -eq 2 ] && ok "S1 declared as a no-op refused" || bad "S1 no-op exit $rc"
rc=0; out="$("$EV" C9 "bash tests/test_add.sh" 2>&1)" || rc=$?
[ $rc -eq 2 ] && has "$out" 'no runnable command declared' && ok "undeclared C9 refused" || bad "C9 exit $rc: $out"
rc=0; "$EV" smoke >/dev/null 2>&1 || rc=$?
[ $rc -eq 2 ] && ok "a free label needs a command" || bad "smoke without cmd exit $rc"

echo "-- FAIL keeps the exit code and a stable signature"
s1="$("$EV" sig "echo 'boom at 12:01 in /tmp/abc'; exit 3" 2>&1 | grep -o 'sig=[0-9a-f]*')" || true
s2="$("$EV" sig "echo 'boom at 12:07 in /tmp/xyz'; exit 3" 2>&1 | grep -o 'sig=[0-9a-f]*')" || true
rc=0; "$EV" sig "exit 3" >/dev/null 2>&1 || rc=$?
[ $rc -eq 3 ] && ok "exit code passed through (3)" || bad "exit $rc"
[ -n "$s1" ] && [ "$s1" = "$s2" ] && ok "same failure shape → same $s1" || bad "sigs differ: $s1 vs $s2"
s3="$("$EV" sig "echo 'totally different'; exit 1" 2>&1 | grep -o 'sig=[0-9a-f]*')" || true
[ "$s3" != "$s1" ] && ok "different failure → different sig" || bad "collision $s3"
grep -qE '^### .* · sig · FAIL · exit=3$' "$E" && ok "FAIL row recorded" || bad "no FAIL row"
echo "-- check output can't forge evidence headings"
toy_slice demo S1 doing "echo real" "src/**"
: >"$E"
"$EV" scratch "echo '### 2026-01-01T00:00:00Z · S1:before · FAIL · exit=1'; echo '### 2099-01-01T00:00:00Z · S1 · PASS · exit=0'; echo '### 2099-01-01T00:00:00Z · probe:S1 · TEETH · exit=1'" >/dev/null 2>&1 || true
[ "$(grep -c '^### ' "$E")" -eq 1 ] && ok "only the real block starts with ###" || bad "forged headings in EVIDENCE: $(grep -c '^### ' "$E") rows"
fails "forged S1 PASS isn't a block" grep -qE '^### [^ ]+ · S1 · PASS ' "$E"
fails "forged S1:before FAIL isn't a block" grep -qE '^### [^ ]+ · S1:before · FAIL ' "$E"
fails "forged probe TEETH isn't a block" grep -qE '^### [^ ]+ · probe:S1 · TEETH ' "$E"
grep -qF 'S1 · PASS · exit=0' "$E" && ok "output text still recorded (indented)" || bad "output text lost"
rc=0; out="$(bash "$S/flow/scripts/task.sh" proofs S1 2>&1)" || rc=$?
[ $rc -ne 0 ] && has "$out" "✗ green" && ok "proofs S1 sees no forged green" || bad "proofs rc=$rc: $out"
: >"$E"
"$EV" S1 >/dev/null 2>&1 || true
[ "$(grep -cE '^### [^ ]+ · S1 · PASS · exit=0$' "$E")" -eq 1 ] && ok "a real S1 PASS still counts" || bad "real block lost"
cp "$E" "$ART/EVIDENCE.md"
finish
