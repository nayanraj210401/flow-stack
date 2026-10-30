#!/usr/bin/env bash
# worktree.lanes: a delegate worker in a linked git worktree gets the same guards as the
# main checkout (seal, fence, plan files), reads the shared .flow/, and writes only to its
# own lane; the plan can't be changed from a lane; the delegate imports lane evidence.
. "$(dirname "$0")/lib.sh"; sandbox worktree.lanes
T="$S/flow/scripts/task.sh"
toy_task mul "Users can multiply two integers" "no division"
toy_mul_check
toy_slice mul S1 doing "bash tests/test_mul.sh" "src/**"
git add -A && git commit -qm "task checks"
toy_features
F="$S/feature-map/scripts/features.sh"
MAIN="$PWD"; WT="$SB/wt"; TD="$MAIN/.flow/tasks/mul"; LANE="$TD/lanes/worker_s1"
lane() { git worktree add -q "$1" -b "$2"; ( cd "$1" && "$T" join mul >/dev/null ); }
git worktree add -q "$SB/free" -b worktree/free
echo "-- a worktree is a lane only once it joined"
[ -z "$(cd "$SB/free" && "$T" active)" ] && ok "unjoined worktree has no task" || bad "unjoined worktree resolves '$(cd "$SB/free" && "$T" active)'"
expect edit-guard.sh "$(cd "$SB/free" && edit "$SB/free/README.md")" allow "unjoined worktree: edit outside main's fence is allowed"
[ ! -d "$TD/lanes/worktree_free" ] && ok "unjoined worktree wrote no lane" || bad "unjoined worktree wrote a lane"
lane "$SB/wt" worker/s1

echo "-- guards hold inside the worktree"
cd "$WT"
expect edit-guard.sh "$(edit "$WT/tests/test_mul.sh")" ask "wt: edit sealed check"
expect edit-guard.sh "$(edit "$WT/README.md")" deny "wt: edit outside fence"
expect edit-guard.sh "$(edit "$WT/src/calc.sh")" allow "wt: edit inside fence"
expect edit-guard.sh "$(edit "$TD/SEALS")" ask "wt: edit main's SEALS"
expect edit-guard.sh "$(edit "$TD/INTENT.md")" ask "wt: edit main's INTENT.md"
expect read-guard.sh "$(pre Read "$(jq -nc --arg f "$TD/blind/MANIFEST" '{file_path:$f}')")" deny "wt: read blind/"

echo "-- worker writes land in its lane only"
printf 'mul() { echo $(( $1 * $2 )); }\n' >>src/calc.sh
check "evidence.sh PASS in wt" "$S/verify/scripts/evidence.sh" S1 "bash tests/test_mul.sh"
grep -q '· S1 · PASS' "$LANE/EVIDENCE.md" 2>/dev/null && ok "evidence in lanes/worker_s1/" || bad "no lane evidence"
grep -q '· S1 · PASS' "$TD/EVIDENCE.md" && bad "worker wrote the shared EVIDENCE.md" || ok "shared EVIDENCE.md untouched"
hook post-tool.sh "$(jq -nc --arg cwd "$WT" --arg f "$WT/src/calc.sh" '{cwd:$cwd,hook_event_name:"PostToolUse",tool_name:"Edit",tool_input:{file_path:$f},tool_response:{}}')"
[ -s "$LANE/trail.jsonl" ] && ok "trail in lane" || bad "no lane trail"
[ -f "$TD/trail.jsonl" ] && grep -q calc.sh "$TD/trail.jsonl" && bad "trail leaked to shared" || ok "shared trail untouched"
sees "proofs read the lane" "green:" "$T" proofs S1

echo "-- feature runs in a lane stay in the lane"
"$F" run calc.add >/dev/null 2>&1
grep -q '^status: unverified' "$MAIN/.flow/features/calc.add.md" && ok "shared feature status untouched by the lane" || bad "lane wrote shared status: $(grep '^status' "$MAIN/.flow/features/calc.add.md")"
grep -q $'^calc.add\tPASS\t' "$MAIN/.flow/features/lanes/worker_s1.tsv" 2>/dev/null && ok "lane result in features/lanes/worker_s1.tsv" || bad "no lane result"
git add -A && git commit -qm "mul"

echo "-- the plan is read-only from a lane"
sees "slice done refused" "refused in worktree lane" "$T" slice S1 done
sees "close refused" "refused in worktree lane" "$T" close
sees "seal add refused" "refused in worktree lane" "$S/seal/scripts/seal.sh" add src/calc.sh
check "seal verify works in wt" "$S/seal/scripts/seal.sh" verify
[ "$("$T" active)" = mul ] && ok "ACTIVE still set" || bad "ACTIVE lost"

echo "-- delegate accepts from the main checkout"
cd "$MAIN"
git merge -q --no-edit worker/s1
sees "accept imports lane evidence" "accepted: 2 evidence block" "$T" accept worker_s1
grep -q '^status: verified' .flow/features/calc.add.md && grep -q "^verified: .* $(git rev-parse --short HEAD)\$" .flow/features/calc.add.md \
  && ok "accept re-proves impacted features at the merged HEAD" || bad "after accept: $(grep -E '^(status|verified)' .flow/features/calc.add.md | tr '\n' ' ')"

echo "-- a merge that breaks an impacted feature is refused"
lane "$SB/wt2" worker/s2
( cd "$SB/wt2" && printf 'add() { echo 0; }\n' >>src/calc.sh && "$S/verify/scripts/evidence.sh" S1 "bash tests/test_mul.sh" >/dev/null 2>&1; git commit -qam "s2" )
git merge -q --no-edit worker/s2
rc=0; out="$("$T" accept worker_s2 2>&1)" || rc=$?
[ $rc -ne 0 ] && has "$out" "calc.add" && ok "accept refused, names the broken feature" || bad "accept rc=$rc: $out"
grep -q 'accepted from lane worker_s2' "$TD/EVIDENCE.md" && bad "evidence imported anyway" || ok "refused lane's evidence not imported"
grep -qE '^### .* · feat:calc.add · FAIL' "$TD/EVIDENCE.md" && ok "the failing re-run is recorded as evidence" || bad "no feat:calc.add FAIL row"
grep -q '^status: broken' .flow/features/calc.add.md && ok "feature marked broken" || bad "status: $(grep '^status' .flow/features/calc.add.md)"

echo "-- undoing the merge doesn't let a retry through"
git reset -q --hard HEAD^
rc=0; out="$("$T" accept worker_s2 2>&1)" || rc=$?
[ $rc -ne 0 ] && has "$out" "not merged" && ok "after reset, accept refuses: lane not merged" || bad "retry after reset rc=$rc: $out"

echo "-- two lanes merged before either is accepted; a stash in between"
lane "$SB/wt3" worker/s3
lane "$SB/wt4" worker/s4
( cd "$SB/wt3" && printf '# s3\n' >>src/calc.sh && "$S/verify/scripts/evidence.sh" smoke "bash tests/test_add.sh" >/dev/null 2>&1; git commit -qam "s3" )
( cd "$SB/wt4" && printf '# s4\n' >>src/export/csv.sh && "$S/verify/scripts/evidence.sh" smoke "bash tests/test_export.sh" >/dev/null 2>&1; git commit -qam "s4" )
git merge -q --no-edit worker/s3; git merge -q --no-edit worker/s4
echo x >>README.md; git stash -q; git stash pop -q; git checkout -q README.md
out="$("$T" accept worker_s3 2>&1)" && has "$out" "feat:calc.add · PASS" && ! has "$out" "export.csv" && ok "accept s3 re-proves s3's feature only" || bad "accept s3: $out"
out="$("$T" accept worker_s4 2>&1)" && has "$out" "feat:export.csv · PASS" && ok "accept s4 re-proves s4's feature" || bad "accept s4: $out"

echo "-- a lane with no recorded base is refused, not waved through"
mkdir -p "$TD/lanes/ghost" && printf '### x · S1 · PASS · exit=0\n' >"$TD/lanes/ghost/EVIDENCE.md"
rc=0; out="$("$T" accept ghost 2>&1)" || rc=$?
[ $rc -ne 0 ] && ok "lane without BRANCH/BASE refused" || bad "ghost accepted: $out"
grep -q '· S1 · PASS' "$TD/EVIDENCE.md" && ok "lane evidence now in task EVIDENCE.md" || bad "not imported"
fails "accept of unknown lane fails" "$T" accept nope
finish
