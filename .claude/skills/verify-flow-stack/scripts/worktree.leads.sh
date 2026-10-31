#!/usr/bin/env bash
# worktree.leads: a linked worktree whose git dir holds a flow-active pointer is a lead of its
# own task. Its fence, anchor, evidence, and status follow that task; the main checkout and
# other worktrees keep theirs; .flow/ stays the main checkout's.
. "$(dirname "$0")/lib.sh"; sandbox worktree.leads
T="$S/flow/scripts/task.sh"
toy_task alpha "Alpha docs exist" "no code"
toy_slice alpha S1 doing "test -f docs/a.md" "docs/**"
toy_task beta "Beta tests exist" "no docs"
toy_slice beta S1 doing "test -f tests/b.sh" "tests/**"
toy_task mul "Users can multiply two integers" "no division"
toy_slice mul S1 doing "bash tests/test_mul.sh" "src/**"
git add -A && git commit -qm "tasks"
MAIN="$PWD"
git worktree add -q "$SB/wa" -b lead/a
git worktree add -q "$SB/wb" -b lead/b
point() { echo "$2" >"$(git -C "$1" rev-parse --absolute-git-dir)/flow-active"; }
point "$SB/wa" alpha; point "$SB/wb" beta
prompt() { jq -nc --arg cwd "$PWD" '{cwd:$cwd, hook_event_name:"UserPromptSubmit", prompt:"go"}'; }

echo "-- each checkout resolves its own task"
for c in "$MAIN:mul" "$SB/wa:alpha" "$SB/wb:beta"; do
  cd "${c%:*}"
  [ "$("$T" active)" = "${c##*:}" ] && ok "$(basename "${c%:*}") → ${c##*:}" || bad "$(basename "${c%:*}") → '$("$T" active)', want ${c##*:}"
  hook anchor.sh "$(prompt)"; has "$OUT" "flow anchor · ${c##*:}" && ok "anchor names ${c##*:}" || bad "anchor: $OUT"
  [ "$(jq -r .task <<<"$("$S/flow/scripts/status.sh" "$PWD")")" = "${c##*:}" ] && ok "status.sh → ${c##*:}" || bad "status.sh: $("$S/flow/scripts/status.sh" "$PWD")"
done

echo "-- fences follow the worktree's task"
cd "$SB/wa"
expect edit-guard.sh "$(edit "$SB/wa/docs/a.md" Write)" allow "lead a: edit inside alpha's fence"
expect edit-guard.sh "$(edit "$SB/wa/src/calc.sh")" deny "lead a: edit in mul's fence"
cd "$SB/wb"
expect edit-guard.sh "$(edit "$SB/wb/tests/b.sh" Write)" allow "lead b: edit inside beta's fence"
expect edit-guard.sh "$(edit "$SB/wb/docs/a.md" Write)" deny "lead b: edit in alpha's fence"
cd "$MAIN"
expect edit-guard.sh "$(edit "$MAIN/src/calc.sh")" allow "main: edit inside mul's fence"

echo "-- a lead worktree writes its task's own state, not a lane"
cd "$SB/wa"; mkdir -p docs && echo a >docs/a.md
check "evidence.sh S1 PASS in lead a" "$S/verify/scripts/evidence.sh" S1 "test -f docs/a.md"
grep -q '· S1 · PASS' "$MAIN/.flow/tasks/alpha/EVIDENCE.md" && ok "evidence in tasks/alpha/EVIDENCE.md" || bad "no alpha evidence"
[ -d "$MAIN/.flow/tasks/alpha/lanes" ] && bad "lead wrote a lane" || ok "no lanes/ for a lead"
grep -q '· S1 · PASS' "$MAIN/.flow/tasks/mul/EVIDENCE.md" && bad "alpha evidence leaked into mul" || ok "mul's evidence untouched"
[ ! -e "$SB/wa/.flow/tasks" ] && [ ! -e "$SB/wa/.flow/ACTIVE" ] && ok "no task state inside the worktree" || bad "worktree grew .flow/tasks or ACTIVE"
[ "$(cat "$MAIN/.flow/ACTIVE")" = mul ] && ok "main ACTIVE still mul" || bad "main ACTIVE: $(cat "$MAIN/.flow/ACTIVE")"

echo "-- the pointer survives a branch switch; a worktree without one has no task"
git switch -q -c lead/a2
[ "$("$T" active)" = alpha ] && ok "after git switch, still alpha" || bad "after switch: '$("$T" active)'"
git worktree add -q "$SB/wc" -b worker/c
cd "$SB/wc"
[ -z "$("$T" active)" ] && ok "unpointed worktree has no task" || bad "unpointed: '$("$T" active)'"
expect edit-guard.sh "$(edit "$SB/wc/README.md")" allow "unpointed worktree: edit outside main's fence is not fenced"
hook anchor.sh "$(prompt)"; has "$OUT" "flow anchor · mul" && bad "unpointed worktree anchored to main's mul" || ok "unpointed worktree: no anchor for main's task"
[ ! -e "$(git rev-parse --absolute-git-dir)/flow-lane" ] && ok "no flow-lane for an unpointed worktree" || bad "flow-lane written"

echo "-- S2: new/switch/close make an unpointed worktree a lead; a slug has one owner"
cd "$MAIN"; git worktree add -q "$SB/wd" -b lead/d; cd "$SB/wd"
"$T" new gamma --goal "Gamma" --check "test -f g" >/dev/null 2>&1
gd="$(git rev-parse --absolute-git-dir)"
[ "$(cat "$gd/flow-active" 2>/dev/null)" = gamma ] && ok "new in an unpointed worktree writes its flow-active" || bad "no flow-active: $(cat "$gd/flow-active" 2>/dev/null)"
[ "$(cat "$MAIN/.flow/ACTIVE")" = mul ] && ok "main ACTIVE unchanged by the worktree's new" || bad "main ACTIVE: $(cat "$MAIN/.flow/ACTIVE")"
[ "$("$T" active)" = gamma ] && ok "worktree d leads gamma" || bad "active: '$("$T" active)'"
sees "switch to main's task is refused, naming main" "main checkout" "$T" switch mul
sees "switch to another worktree's task is refused, naming it" "$SB/wa" "$T" switch alpha
[ "$(cat "$gd/flow-active")" = gamma ] && ok "refused switch left the pointer" || bad "pointer moved"
cd "$MAIN"
sees "main switch to a worktree's task is refused, naming it" "$SB/wd" "$T" switch gamma
[ "$(cat "$MAIN/.flow/ACTIVE")" = mul ] && ok "refused switch left main ACTIVE" || bad "main ACTIVE moved"
cd "$SB/wd"; "$T" close >/dev/null 2>&1
[ ! -e "$gd/flow-active" ] && ok "close removes the worktree's own pointer" || bad "pointer left"
[ "$(cat "$MAIN/.flow/ACTIVE")" = mul ] && [ "$(cat "$(git -C "$SB/wa" rev-parse --absolute-git-dir)/flow-active")" = alpha ] && ok "close left main's and a's pointers" || bad "close touched another owner"
cd "$MAIN"; sees "list marks tasks active in a worktree" "feature (worktree $SB/wa)" "$T" list

echo "-- S3: a worker spawned by a lead worktree joins that lead's task; one spawned from main does not"
# the spawning session's row in Claude Code's registry: its cwd is the lead's checkout
session_row() { mkdir -p "$CLAUDE_CONFIG_DIR/sessions"; echo "{\"pid\":$1,\"cwd\":\"$2\"}" >"$CLAUDE_CONFIG_DIR/sessions/$1.json"; }
session_row 101 "$SB/wa"; session_row 102 "$MAIN"
sub() { edit "$1" | jq -c '. + {session_id:"s", agent_id:"agent1"}'; }
cd "$SB/wa"; git add -A; git commit -qm "lead a docs"
git worktree add -q "$SB/wk" -b worker/k; git worktree add -q "$SB/wm" -b worker/m
cd "$SB/wm"; export FLOW_SESSION_PID=102; hook edit-guard.sh "$(sub "$SB/wm/src/calc.sh")"; unset FLOW_SESSION_PID
[ "$(cat "$(git rev-parse --absolute-git-dir)/flow-lane" 2>/dev/null)" = "$(printf 'mul\n%s' "$MAIN")" ] && [ "$("$T" active)" = mul ] && ok "worker of main auto-joined main's mul (slug + main root)" || bad "main-spawned worker: '$("$T" active)' / $(cat "$(git rev-parse --absolute-git-dir)/flow-lane" 2>/dev/null)"
session_row 103 "$SB/wc"
cd "$SB/wc"; export FLOW_SESSION_PID=103; hook edit-guard.sh "$(edit "$SB/wc/README.md" | jq -c '. + {session_id:"h"}')"
[ ! -e "$(git rev-parse --absolute-git-dir)/flow-lane" ] && [ -z "$("$T" active)" ] && ok "a human session in an unpointed worktree stays task-less" || bad "human worktree joined: '$("$T" active)'"
hook edit-guard.sh "$(sub "$SB/wc/README.md")"; unset FLOW_SESSION_PID
[ ! -e "$(git rev-parse --absolute-git-dir)/flow-lane" ] && ok "a subagent of an unpointed worktree's own session does not join" || bad "subagent of its own unpointed session joined"
cd "$SB/wm"
cd "$SB/wk"; export FLOW_SESSION_PID=101; hook edit-guard.sh "$(sub "$SB/wk/docs/a.md")"; unset FLOW_SESSION_PID
kd="$(git rev-parse --absolute-git-dir)"
[ "$(cat "$kd/flow-lane" 2>/dev/null)" = "$(printf 'alpha\n%s' "$SB/wa")" ] && ok "worker of lead a auto-joined (slug + lead root)" || bad "flow-lane: $(cat "$kd/flow-lane" 2>/dev/null)"
[ "$("$T" active)" = alpha ] && ok "joined worker resolves alpha" || bad "joined worker: '$("$T" active)'"
sees "a joined worker is still refused new" "remove that file to lead" "$T" new zeta
echo k >k.txt; check "worker evidence" "$S/verify/scripts/evidence.sh" wk:1 "test -f k.txt"
git add -A; git commit -qm "worker k"
ls "$MAIN/.flow/tasks/alpha/lanes/worker_k/EVIDENCE.md" >/dev/null 2>&1 && ok "evidence in tasks/alpha/lanes/worker_k/" || bad "no alpha lane evidence"
[ ! -d "$MAIN/.flow/tasks/mul/lanes/worker_k" ] && ok "nothing leaked into mul's lanes" || bad "leaked into mul"
[ "$(cat "$MAIN/.flow/tasks/alpha/lanes/worker_k/BASE")" = "$(git -C "$SB/wa" rev-parse HEAD)" ] && ok "BASE forks from the lead's HEAD" || bad "BASE: $(cat "$MAIN/.flow/tasks/alpha/lanes/worker_k/BASE")"
cd "$SB/wa"; git merge -q worker/k
sees "accept run in the lead worktree" "accepted:" "$T" accept worker_k
grep -q 'wk:1' "$MAIN/.flow/tasks/alpha/EVIDENCE.md" && ok "lane evidence imported into alpha" || bad "alpha EVIDENCE lacks the lane block"
cd "$SB/wm"; "$T" join mul >/dev/null; [ "$(head -n1 "$(git rev-parse --absolute-git-dir)/flow-lane")" = mul ] && ok "task.sh join writes flow-lane" || bad "join"

echo "-- join can't trap a lead; a joined lane says how to get out"
cd "$SB/wa"
sees "join refused in a lead worktree" "close it before joining" "$T" join beta
git worktree add -q "$SB/wj" -b lane/j; cd "$SB/wj"
check "join in an unpointed worktree" "$T" join alpha
sees "new in a joined lane names flow-lane" "remove that file to lead" "$T" new gamma
sees "join with no slug prints usage" "usage: task.sh join" "$T" join

finish
