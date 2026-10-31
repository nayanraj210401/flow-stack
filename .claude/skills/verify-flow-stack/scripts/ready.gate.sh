#!/usr/bin/env bash
# ready.gate: a PR can't be marked ready for human review (non-draft gh pr create, gh pr ready)
# until ready.sh has stamped HEAD; the stamp needs live checks plus recorded review/deslop/tour;
# a new commit invalidates it; review records count rounds per branch; review_gate: yolo turns it off, and the repo config overrides the profile.
. "$(dirname "$0")/lib.sh"; sandbox ready.gate
R="$S/review/scripts/ready.sh"
"$S/profile/scripts/init.sh" solo-hacker >/dev/null
mkdir -p .flow && printf '{"commands":{"lint":"bash -n src/calc.sh"}}\n' >.flow/config.json
toy_features >/dev/null 2>&1
base="$(git branch --show-current)"
git switch -qc feat
printf 'add() { echo $(( $1 + $2 )); }  # sums\n' >src/calc.sh && git commit -qam "tweak add"
PR='gh pr create --title x --body y'

echo "-- no stamp: ready-for-review is blocked, drafts are not"
expect guard.sh "$(bashcmd "$PR")" deny "non-draft PR without stamp"
expect guard.sh "$(bashcmd "$PR --draft")" allow "draft PR"
expect guard.sh "$(bashcmd "gh pr ready 7")" deny "gh pr ready without stamp"
expect guard.sh "$(bashcmd "gh pr ready 7 --undo")" allow "gh pr ready --undo"
expect guard.sh "$(bashcmd "$(printf "git commit -F - <<'M'\nguard denies a non-draft gh pr create and gh pr ready\nM")")" allow "heredoc text mentioning gh pr create"
expect guard.sh "$(bashcmd "perl -pi -e 's/x/gh pr create and more/' f")" allow "quoted text mentioning gh pr create"
expect guard.sh "$(bashcmd "git push -u origin x && gh pr create --title x")" deny "gh pr create after &&"
expect guard.sh "$(bashcmd "eval \"gh pr create --title x\"")" deny "wrapped: eval"
expect guard.sh "$(bashcmd "sh -c 'gh pr create --title x'")" deny "wrapped: sh -c"
expect guard.sh "$(bashcmd "bash -lc 'gh pr ready 7'")" deny "wrapped: bash -lc"
expect guard.sh "$(bashcmd "command gh pr create --title x")" deny "wrapped: command"
expect guard.sh "$(bashcmd "env GH_TOKEN=x gh pr create --title x")" deny "wrapped: env VAR=x"
expect guard.sh "$(bashcmd "sh -c 'gh pr create --draft --title x'")" allow "wrapped draft still passes"
expect guard.sh "$(bashcmd "sh -c 'gh pr create --draft'")" allow "wrapped draft, flag last before the quote"
expect guard.sh "$(bashcmd "gh pr create --body 'see --undo'")" deny "body text ending in --undo is not a flag"
expect guard.sh "$(bashcmd "gh pr create --title \"a -d\"")" deny "title text ending in -d is not a flag"
expect guard.sh "$(bashcmd "echo 1 | xargs -I{} gh pr create --title x")" deny "wrapped: xargs with flags"
expect guard.sh "$(bashcmd "env -u GH_HOST gh pr ready 7")" deny "wrapped: env with flags"
expect guard.sh "$(bashcmd "GH pr create --title x")" deny "uppercase GH (case-insensitive filesystems run it)"
echo "-- command start: env prefixes, gh global options, if/then, ! still count; text that only mentions it does not"
for c in "FOO=1 gh pr create --title x" "FOO=1 BAR=2 gh pr ready 7" "cd x && FOO=1 gh pr create --title x" "gh -R a/b pr create --title x" \
         "gh --repo a/b pr ready 7" "GH_TOKEN=x gh --repo=a/b pr create" "if true; then gh pr create --title x; fi" "! gh pr create --title x" \
         "if ! gh pr create --title x; then echo no; fi"; do
  expect guard.sh "$(bashcmd "$c")" deny "non-draft: $c"
done
for c in "FOO=1 gh pr create --draft --title x" "gh -R a/b pr create --draft --title x" "FOO=1 gh pr ready 7 --undo" "echo \"gh pr create\"" \
         "grep 'gh pr create' file" "echo FOO=1 gh pr create" "gh -R a/b pr view 3" "FOO=1 gh pr view 3"; do
  expect guard.sh "$(bashcmd "$c")" allow "passes: $c"
done
fails "ready.sh fails with nothing recorded" "$R"
sees "names what's missing" "✗ review: none for this HEAD" "$R"

echo "-- recorded review/deslop/tour + live checks → stamp"
"$R" record review ship "0 blockers" >/dev/null; "$R" record deslop done "-0 lines" >/dev/null; "$R" record tour done >/dev/null
check "ready.sh passes" "$R"
expect guard.sh "$(bashcmd "$PR")" allow "non-draft PR with stamp"
expect guard.sh "$(bashcmd "gh pr ready 7")" allow "gh pr ready with stamp"

echo "-- a new commit makes the stamp stale"
printf '# calc\n' >>README.md && git commit -qam "docs"
expect guard.sh "$(bashcmd "$PR")" deny "stale stamp after new commit"

echo "-- each requirement bites"
"$R" record review fix-first "1 blocker" >/dev/null; "$R" record deslop done >/dev/null; "$R" record tour done >/dev/null
sees "review fix-first blocks" "✗ review: fix-first" "$R"
"$R" record review ship >/dev/null
printf '{"commands":{"lint":"false"}}\n' >.flow/config.json
sees "failing lint blocks" "✗ lint fails" "$R"
printf '{"commands":{"lint":"bash -n src/calc.sh"}}\n' >.flow/config.json
echo x >>src/calc.sh
sees "dirty tree blocks" "✗ clean tree" "$R"
git checkout -q src/calc.sh
printf 'add() { echo 0; }\n' >src/calc.sh && git commit -qam "break add"
"$R" record review ship >/dev/null; "$R" record deslop done >/dev/null; "$R" record tour done >/dev/null
sees "failing impacted scenario blocks" "✗ impacted feature scenarios fail: calc.add" "$R"
git checkout -q .flow && git revert --no-edit HEAD >/dev/null
"$R" record review ship >/dev/null; "$R" record deslop done >/dev/null; "$R" record tour done >/dev/null
check "all green again passes" "$R"

echo "-- repo quality gates: ready[] run commands and do steps"
printf '{"commands":{"lint":"bash -n src/calc.sh"},"ready":[{"id":"e2e","run":"false"},{"id":"sec-scan","do":"Run the security MCP on the diff"}]}\n' >.flow/config.json
sees "failing run gate blocks" "✗ e2e fails: false" "$R"
sees "unrecorded do step blocks and says what to do" "✗ sec-scan: not done for this HEAD. Run the security MCP on the diff" "$R"
fails "record refuses an unknown id" "$R" record nope done
fails "record refuses a run id (it's live, not recorded)" "$R" record e2e done
printf '{"commands":{"lint":"bash -n src/calc.sh"},"ready":[{"id":"e2e","run":"bash tests/test_add.sh"},{"id":"sec-scan","do":"Run the security MCP on the diff"}]}\n' >.flow/config.json
check "record accepts a do id" "$R" record sec-scan done "0 findings"
sees "passing run gate shows" "✓ e2e" "$R"
check "all custom gates green passes" "$R"
printf '{"commands":{"lint":"bash -n src/calc.sh"}}\n' >.flow/config.json

echo "-- flow task: acceptance checks are part of the bar"
toy_task mul "Users can multiply" "no division"
toy_mul_check
git add -A && git commit -qm "task check"
"$R" record review ship >/dev/null; "$R" record deslop done >/dev/null; "$R" record tour done >/dev/null
sees "failing acceptance check blocks" "✗ C1 acceptance check fails" "$R"
git checkout -q .flow; printf 'mul() { echo $(( $1 * $2 )); }\n' >>src/calc.sh && git commit -qam "mul"
"$R" record review ship >/dev/null; "$R" record deslop done >/dev/null; "$R" record tour done >/dev/null
check "acceptance green passes" "$R"
"$S/flow/scripts/task.sh" close >/dev/null

echo "-- review rounds: counted per branch; round 3 without ship sends the builder to challenge"
git checkout -q .flow; git switch -qc rounds "$base"
printf 'r1\n' >>README.md && git commit -qam r1
sees "round 1 names the re-review range" "review round 1 on this branch; a re-review reads only: git diff $(git rev-parse --short=7 HEAD)..HEAD" "$R" record review fix-first
sees "same sha recorded twice is still round 1" "review round 1" "$R" record review fix-first
printf 'r2\n' >>README.md && git commit -qam r2
o="$("$R" record review fix-first)"; has "$o" "review round 2" && ! has "$o" "challenge" && ok "round 2: no challenge yet" || bad "round 2: $o"
printf 'r3\n' >>README.md && git commit -qam r3
sees "round 3 without ship says challenge" "round 3 without ship: stop patching findings; run the challenge skill" "$R" record review fix-first
o="$("$R" record review ship)"; ! has "$o" "challenge" && ok "ship at round 3: no challenge" || bad "ship at round 3: $o"
git switch -q feat

echo "-- yolo and the repo override"
git checkout -q .flow; printf 'more\n' >>README.md && git commit -qam "more"
perl -pi -e 's/^review_gate:\s*\w+/review_gate: yolo/' "$FLOW_STACK_HOME/profile.md"
grep -q '^review_gate: yolo' "$FLOW_STACK_HOME/profile.md" && ok "profile has review_gate" || bad "profile has no review_gate line"
expect guard.sh "$(bashcmd "$PR")" allow "profile yolo: no gate"
sees "ready.sh says yolo" "yolo" "$R"
printf '{"commands":{"lint":"bash -n src/calc.sh"},"review_gate":"on"}\n' >.flow/config.json
expect guard.sh "$(bashcmd "$PR")" deny "repo on overrides profile yolo"
finish
