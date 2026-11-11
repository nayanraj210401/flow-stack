#!/usr/bin/env bash
# blind.checks: held-out checks run only via blind-run.sh (installed, run, removed,
# verdict recorded), and every other path to them (Read, Grep, shell) is denied.
. "$(dirname "$0")/lib.sh"; sandbox blind.checks
toy_task demo "mul multiplies" "no division"
B=.flow/tasks/demo/blind; BR="$S/verify/scripts/blind-run.sh"
mkdir -p "$B"
printf '. src/calc.sh\n[ "$(mul 3 3)" = 9 ] || { echo "FAIL mul-square"; exit 1; }\necho ok\n' >"$B/square.sh"
printf 'run: bash tests/blind_square.sh\nfile: square.sh -> tests/blind_square.sh\n' >"$B/MANIFEST"
echo 'pre-existing' >tests/blind_square.sh

echo "-- blind-run.sh"
rc=0; out="$("$BR" 2>&1)" || rc=$?
[ $rc -ne 0 ] && has "$out" "blind checks: FAIL (1 file(s))" && ok "FAIL before mul exists" || bad "rc=$rc out=$out"
has "$out" "mul-square" && ok "failing check named" || bad "no failing name"
[ "$(cat tests/blind_square.sh)" = pre-existing ] && ok "pre-existing target restored" || bad "target not restored"
rm tests/blind_square.sh
printf 'mul() { echo $(( $1 * $2 )); }\n' >>src/calc.sh
sees "PASS once mul exists" "flow-evidence: PASS" "$BR"
[ ! -e tests/blind_square.sh ] && ok "installed copy removed after the run" || bad "blind file left in tree"
grep -qE '^### .* · blind · PASS' .flow/tasks/demo/EVIDENCE.md && ok "verdict in EVIDENCE.md" || bad "no blind row"
grep -q 'mul 3 3' .flow/tasks/demo/EVIDENCE.md && bad "assertion leaked into EVIDENCE" || ok "assertion body not in EVIDENCE"

echo "-- every other route is denied"
expect read-guard.sh "$(pre Read "$(jq -nc --arg f "$PWD/$B/square.sh" '{file_path:$f}')")" deny "Read blind file"
expect read-guard.sh "$(pre Grep '{"pattern":"mul","path":".flow/tasks/demo/blind"}')" deny "Grep blind dir"
expect read-guard.sh "$(pre Glob '{"pattern":".flow/tasks/*/blind/*"}')" deny "Glob blind files"
expect read-guard.sh "$(pre Grep '{"pattern":"mul","path":".flow/tasks/demo"}')" deny "Grep task dir (ancestor of blind)"
expect read-guard.sh "$(pre Grep '{"pattern":"mul","path":".flow/tasks/demo/"}')" deny "Grep task dir with trailing slash"
expect read-guard.sh "$(pre Grep '{"pattern":"mul","path":".flow/tasks"}')" deny "Grep .flow/tasks"
expect read-guard.sh "$(pre Grep '{"pattern":"mul","path":".flow"}')" deny "Grep .flow"
expect read-guard.sh "$(pre Grep "$(jq -nc --arg p "$PWD/.flow" '{pattern:"mul",path:$p}')")" deny "Grep absolute .flow"
expect read-guard.sh "$(pre Grep '{"pattern":"mul","path":".","glob":".flow/**"}')" deny "Grep glob reaching .flow"
expect read-guard.sh "$(pre Glob '{"pattern":".flow/**/*"}')" deny "Glob .flow/**"
expect read-guard.sh "$(pre Glob '{"pattern":".flow/tasks/*/*"}')" deny "Glob task dir contents"
expect read-guard.sh "$(pre Grep '{"pattern":"mul","path":".flow/tasks/demo/INTENT.md"}')" allow "Grep INTENT.md"
expect read-guard.sh "$(pre Grep '{"pattern":"mul","path":".flow/features"}')" allow "Grep .flow/features"
expect read-guard.sh "$(pre Grep '{"pattern":"mul","path":"."}')" allow "Grep repo-wide path=."
expect read-guard.sh "$(pre Grep '{"pattern":"mul"}')" allow "Grep without path"
expect read-guard.sh "$(pre Glob '{"pattern":"src/**/*.sh"}')" allow "Glob src"
expect guard.sh "$(bashcmd "cat $B/square.sh")" deny "cat blind file"
expect guard.sh "$(bashcmd "bash $BR")" allow "blind-run.sh itself"
expect read-guard.sh "$(pre Read "$(jq -nc --arg f "$PWD/src/calc.sh" '{file_path:$f}')")" allow "Read ordinary source"
finish
