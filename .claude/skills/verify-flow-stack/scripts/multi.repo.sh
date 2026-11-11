#!/usr/bin/env bash
# multi.repo: one task spans a profile workspace. The task folder lives in the workspace's primary
# repo; other repos point at it. Slice fences, seals, and evidence are per repo, and the guards hold
# in every repo of the task.
. "$(dirname "$0")/lib.sh"; sandbox multi.repo
T="$S/flow/scripts/task.sh"; SEAL="$S/seal/scripts/seal.sh"
HOME_R="$PWD"; OTHER="$SB/other"
mkdir -p "$OTHER" && (cd "$OTHER" && toy_repo >/dev/null)
"$S/profile/scripts/init.sh" solo-hacker >/dev/null
perl -0pi -e "s|## example-repo\n- path: ~/Project/example-repo|## repo\n- path: $HOME_R\n- role: primary\n\n## other\n- path: $OTHER\n- role: dep|" "$FLOW_STACK_HOME/profile.md"
printf '\n# Workspaces\n## ws\n- repos: repo, other\n' >>"$FLOW_STACK_HOME/profile.md"

echo "-- a workspace task lives in the primary repo; the others point at it"
(cd "$OTHER" && "$T" new mr feature --workspace ws >/dev/null)
[ -d "$HOME_R/.flow/tasks/mr" ] && ok "task folder in the primary repo" || bad "no task in primary"
[ ! -d "$OTHER/.flow/tasks/mr" ] && ok "no copy in the other repo" || bad "task duplicated in other"
[ "$(cat "$OTHER/.flow/ACTIVE" 2>/dev/null)" = "@$HOME_R:mr" ] && ok "other repo's ACTIVE points home" || bad "pointer: $(cat "$OTHER/.flow/ACTIVE" 2>/dev/null)"
grep -q "^other	$OTHER$" "$HOME_R/.flow/tasks/mr/REPOS" 2>/dev/null && ok "REPOS lists other" || bad "REPOS: $(cat "$HOME_R/.flow/tasks/mr/REPOS" 2>/dev/null)"
(cd "$OTHER" && [ "$("$T" dir)" = "$HOME_R/.flow/tasks/mr" ]) && ok "task.sh dir from other resolves home" || bad "dir from other"

printf '# Slices · mr\n\n## S1 · other change\nstatus: doing\nrepo: other\ncheck: bash tests/test_o.sh\nfence: src/**\nbudget: 40\n' >"$HOME_R/.flow/tasks/mr/SLICES.md"
printf 'echo ok\n' >"$OTHER/tests/test_o.sh"; printf 'echo home\n' >"$HOME_R/tests/test_o.sh"
(cd "$OTHER" && "$SEAL" add tests/test_o.sh >/dev/null)
grep -q ' other:tests/test_o.sh$' "$HOME_R/.flow/tasks/mr/SEALS" && ok "seal is repo-qualified" || bad "SEALS: $(cat "$HOME_R/.flow/tasks/mr/SEALS")"

echo "-- guards in the other repo"
cd "$OTHER"
hook session-start.sh "$(jq -nc --arg cwd "$PWD" '{cwd:$cwd,hook_event_name:"SessionStart",source:"startup"}')"
has "$OUT" "## Active task: mr" && ok "session start shows the linked task" || bad "no task in session start"
expect edit-guard.sh "$(edit "$OTHER/src/calc.sh")" allow "other: edit in fence"
expect edit-guard.sh "$(edit "$OTHER/README.md")" deny "other: edit outside fence"
expect edit-guard.sh "$(edit "$OTHER/tests/test_o.sh")" ask "other: edit its sealed check"
expect guard.sh "$(bashcmd "echo x > tests/test_o.sh")" ask "other: shell write to its sealed check"

echo "-- guards in the home repo"
cd "$HOME_R"
expect edit-guard.sh "$(edit "$HOME_R/src/calc.sh")" deny "home: slice S1 works in other"
expect edit-guard.sh "$(edit "$HOME_R/tests/test_o.sh")" deny "home: same-named file isn't the sealed one"
expect edit-guard.sh "$(edit "$OTHER/src/calc.sh")" allow "from home: edit other's file in fence"
expect edit-guard.sh "$(edit "$OTHER/README.md")" deny "from home: other's file outside fence"
expect edit-guard.sh "$(edit "$OTHER/tests/test_o.sh")" ask "from home: other's sealed check"
expect guard.sh "$(bashcmd "echo x > $OTHER/tests/test_o.sh")" ask "from home: shell write to other's sealed check"

echo "-- evidence and seals across repos"
(cd "$OTHER" && "$S/verify/scripts/evidence.sh" S1 "bash tests/test_o.sh" >/dev/null)
grep -q '^- repo: other' "$HOME_R/.flow/tasks/mr/EVIDENCE.md" && ok "evidence records its repo" || bad "no repo line in EVIDENCE"
check "seal verify from home" "$SEAL" verify
fails "seal rm of an unsealed path errors" "$SEAL" rm tests/nope.sh
echo 'echo changed' >>"$OTHER/tests/test_o.sh"
fails "seal verify catches a change in the other repo" "$SEAL" verify
(cd "$OTHER" && git checkout -q tests/test_o.sh 2>/dev/null || printf 'echo ok\n' >tests/test_o.sh)

echo "-- board and close"
[ "$("$S/board/scripts/collect.sh" --no-cost --no-prs "$HOME_R" "$OTHER" | jq -r '.repos[] | select(.name=="repo") | .tasks[0].repos | join(",")')" = "repo,other" ] && ok "board task lists its repos" || bad "board repos"
(cd "$OTHER" && "$T" close >/dev/null)
[ ! -f "$HOME_R/.flow/ACTIVE" ] && [ ! -f "$OTHER/.flow/ACTIVE" ] && ok "close from other clears every repo" || bad "ACTIVE left behind"

echo "-- another lead's pointer is never moved"
cd "$HOME_R"; echo "@/elsewhere:x" >"$OTHER/.flow/ACTIVE"
sees "main: switch refuses a repo on another task" "close it there first" "$T" switch mr
[ "$(cat "$OTHER/.flow/ACTIVE")" = "@/elsewhere:x" ] && ok "that repo's pointer is untouched" || bad "other: $(cat "$OTHER/.flow/ACTIVE")"
rm "$OTHER/.flow/ACTIVE"; "$T" switch mr >/dev/null
git worktree add -q "$SB/wk" -b lead/k
(cd "$SB/wk" && "$T" new steal feature --workspace ws >/dev/null 2>&1) && bad "worktree took main's repos" || ok "worktree: new refuses repos main's task holds"
[ "$(cat "$OTHER/.flow/ACTIVE")" = "@$HOME_R:mr" ] && ok "main's multi-repo pointer kept" || bad "other: $(cat "$OTHER/.flow/ACTIVE")"

echo "-- a lead worktree on a multi-repo task closes its own pointers only"
"$T" new solo feature >/dev/null
git worktree add -q "$SB/wl" -b lead/l
(cd "$SB/wl" && "$T" switch mr >/dev/null) && ok "worktree leads mr while main is on solo" || bad "switch mr in worktree"
[ "$(cat "$HOME_R/.flow/ACTIVE")" = solo ] && [ "$(cat "$OTHER/.flow/ACTIVE")" = "@$HOME_R:mr" ] && ok "pointers: main solo, other → mr" || bad "main=$(cat "$HOME_R/.flow/ACTIVE") other=$(cat "$OTHER/.flow/ACTIVE")"
(cd "$SB/wl" && "$T" close >/dev/null)
[ ! -f "$OTHER/.flow/ACTIVE" ] && [ "$(cat "$HOME_R/.flow/ACTIVE")" = solo ] && ok "close in the worktree clears other's pointer, keeps main's" || bad "after close: main=$(cat "$HOME_R/.flow/ACTIVE" 2>/dev/null) other=$(cat "$OTHER/.flow/ACTIVE" 2>/dev/null)"
finish
