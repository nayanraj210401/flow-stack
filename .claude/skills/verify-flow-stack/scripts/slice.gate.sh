#!/usr/bin/env bash
# slice.gate: `task.sh slice <id> done` refuses until the slice has red-first,
# green, probe TEETH, and fits its budget; SLICES.md can't be flipped to done by hand.
. "$(dirname "$0")/lib.sh"; sandbox slice.gate
toy_task demo "mul multiplies" "no division"
toy_mul_check
toy_slice demo S1 doing "bash tests/test_mul.sh" "src/calc.sh"
T=.flow/tasks/demo; TASK="$S/flow/scripts/task.sh"; EV="$S/verify/scripts/evidence.sh"
status() { awk '/^status:/{print $2; exit}' "$T/SLICES.md"; }

echo "-- no proofs → refused"
fails "slice S1 done without proofs" "$TASK" slice S1 done
sees "proofs lists what's missing" "✗ red first" "$TASK" proofs S1
[ "$(status)" = doing ] && ok "status still doing" || bad "status is $(status)"

echo "-- red → build → green → teeth"
"$EV" S1:before "bash tests/test_mul.sh" >/dev/null 2>&1 || true
printf 'mul() { echo $(( $1 * $2 )); }\n' >>src/calc.sh
check "S1 check passes via evidence.sh" "$EV" S1 "bash tests/test_mul.sh"
check "probe S1 has teeth" "$S/probe/scripts/probe.sh" S1 "bash tests/test_mul.sh"
perl -pi -e 's/^budget: .*/budget: 0/' "$T/SLICES.md"
sees "over budget is refused" "✗ budget" "$TASK" proofs S1
fails "done refused over budget" "$TASK" slice S1 done
perl -pi -e 's/^budget: .*/budget: 40/' "$T/SLICES.md"
"$TASK" proofs S1 >"$ART/proofs.txt" 2>&1 && ok "all proofs present" || bad "proofs: $(cat "$ART/proofs.txt")"
check "slice S1 done accepted" "$TASK" slice S1 done
[ "$(status)" = done ] && ok "SLICES.md shows done" || bad "status is $(status)"

echo "-- stale green: an edit after the last PASS reopens the gate"
"$TASK" slice S1 doing >/dev/null
printf '{"ts":"2999-01-01T00:00:00Z","tool":"Edit","target":"src/calc.sh"}\n' >>"$T/trail.jsonl"
sees "PASS older than last edit" "older than the last edit" "$TASK" proofs S1
fails "done refused after a later edit" "$TASK" slice S1 done

echo "-- --force logs the override"
check "--force with a reason" "$TASK" slice S1 done --force "spike, proof deferred"
grep -q "spike, proof deferred" "$T/DECISIONS.tsv" && ok "override in DECISIONS.tsv" || bad "no DECISIONS row"
fails "--force without a reason" "$TASK" slice S1 done --force

echo "-- hand-flipping status is blocked"
"$TASK" slice S1 doing >/dev/null
expect guard.sh "$(bashcmd "sed -i '' 's/status: doing/status: done/' $T/SLICES.md")" deny "sed SLICES.md to done"
expect guard.sh "$(bashcmd "printf 'status: done\n' >> $T/SLICES.md")" deny "append done to SLICES.md"
expect guard.sh "$(bashcmd "perl -pi -e 's/status: doing/status: done/' $T/SLICES.md")" deny "perl -pi SLICES.md to done"
expect guard.sh "$(bashcmd "grep -c '^status: done' $T/SLICES.md")" allow "read SLICES.md for done count"
expect guard.sh "$(bashcmd "echo 'guard blocks SLICES.md with status: done' >> notes.md")" allow "write elsewhere that mentions both"
expect edit-guard.sh "$(pre Edit "$(jq -nc --arg f "$PWD/$T/SLICES.md" '{file_path:$f, old_string:"status: doing", new_string:"status: done"}')")" deny "Edit SLICES.md to done"
expect edit-guard.sh "$(pre Edit "$(jq -nc --arg f "$PWD/$T/SLICES.md" '{file_path:$f, old_string:"budget: 40", new_string:"budget: 60"}')")" allow "Edit other SLICES.md fields"
SF="$PWD/$T/SLICES.md"
expect edit-guard.sh "$(pre MultiEdit "$(jq -nc --arg f "$SF" '{file_path:$f, edits:[{old_string:"status: doing", new_string:"status: done"}]}')")" deny "MultiEdit SLICES.md to done"
expect edit-guard.sh "$(pre MultiEdit "$(jq -nc --arg f "$SF" '{file_path:$f, edits:[{old_string:"budget: 40", new_string:"budget: 60"},{old_string:"status: doing", new_string:"status: done"}]}')")" deny "MultiEdit with done in a later edit"
expect edit-guard.sh "$(pre MultiEdit "$(jq -nc --arg f "$SF" '{file_path:$f, edits:[{old_string:"budget: 40", new_string:"budget: 60"}]}')")" allow "MultiEdit other SLICES.md fields"
expect edit-guard.sh "$(pre MultiEdit "$(jq -nc --arg f "$SF" '{file_path:$f, edits:[{old_string:"status: done", new_string:"status: done"}]}')")" allow "MultiEdit keeping an already-done slice"
sees "diffstat reports changed lines" "changed=1" "$S/loop/scripts/diffstat.sh" src/calc.sh
cp "$T/SLICES.md" "$T/EVIDENCE.md" "$ART/" 2>/dev/null || true
finish
