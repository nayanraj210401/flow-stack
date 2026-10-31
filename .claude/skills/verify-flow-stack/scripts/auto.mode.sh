#!/usr/bin/env bash
# auto.mode: `--auto` anywhere in a prompt means the human is away for this session. Every ask
# becomes deny-and-queue (GATES.md), AskUserQuestion is denied, outward-facing commands wait;
# `--no-auto` ends it, and other sessions are never affected.
. "$(dirname "$0")/lib.sh"; sandbox auto.mode
"$S/profile/scripts/init.sh" solo-hacker >/dev/null
mkdir -p .flow && printf '{"commands":{}}\n' >.flow/config.json
printf -- '- ask: terraform[[:space:]]+apply · changes shared infra\n' >.flow/gates.md
prompt() { jq -nc --arg cwd "$PWD" --arg s "$1" --arg p "$2" '{cwd:$cwd, session_id:$s, hook_event_name:"UserPromptSubmit", prompt:$p}'; }
in_s() { jq -c --arg s "$1" '. + {session_id:$s}' <<<"$2"; } # in_s <session> <payload>
ASK="$(pre AskUserQuestion '{"questions":[]}')"

echo "-- off by default"
hook anchor.sh "$(prompt A "fix the bug")"; has "$OUT" "[flow auto]" && bad "anchor silent without --auto" || ok "anchor silent without --auto"
expect guard.sh "$(in_s A "$(bashcmd "terraform apply")")" ask "repo ask gate asks"
expect guard.sh "$(in_s A "$ASK")" allow "AskUserQuestion allowed"
expect guard.sh "$(in_s A "$(bashcmd "git push origin feat")")" allow "plain push not gated"

echo "-- --auto mid-sentence turns it on for this session"
hook anchor.sh "$(prompt A "keep going on the slices --auto, back tomorrow")"
has "$OUT" "[flow auto] the human is away" && ok "anchor announces auto" || bad "anchor announces auto ($OUT)"
hook anchor.sh "$(prompt A "next")"; has "$OUT" "[flow auto]" && ok "stays on for later prompts" || bad "stays on for later prompts"
expect guard.sh "$(in_s A "$(bashcmd "terraform apply")")" deny "repo ask gate → queued"
has "$OUT" "GATES.md" && ok "deny reason says queue in GATES.md" || bad "deny reason says queue in GATES.md"
expect guard.sh "$(in_s A "$(bashcmd "git reset --hard")")" deny "built-in ask → queued"
expect guard.sh "$(in_s A "$ASK")" deny "AskUserQuestion denied"
expect guard.sh "$(in_s A "$(bashcmd "git push -u origin feat")")" deny "git push waits"
expect guard.sh "$(in_s A "$(bashcmd "gh pr create --draft --title x")")" deny "draft PR waits"
expect guard.sh "$(in_s A "$(bashcmd "gh pr merge 7")")" deny "merge waits"
for c in "FOO=1 git push origin feat" "FOO=1 BAR=2 gh pr create --title x" "git -C . push origin feat" "git -c k=v push origin feat" \
         "gh -R a/b pr create --title x" "gh --repo a/b pr merge 3" "gh -R a/b pr ready 7" "gh -R a/b release create v1" \
         "npm --prefix x publish" "FOO=1 npm publish" "if true; then git push origin feat; fi" "! git push origin feat" \
         "if ! git push origin feat; then echo no; fi"; do
  expect guard.sh "$(in_s A "$(bashcmd "$c")")" deny "outward form waits: $c"
done
for c in "echo \"git push\"" "grep 'gh pr create' file" "echo FOO=1 git push" "git -C . status" "FOO=1 git status" "gh -R a/b pr view 3" "npm --prefix x test"; do
  expect guard.sh "$(in_s A "$(bashcmd "$c")")" allow "lookalike runs: $c"
done
expect guard.sh "$(in_s A "$(bashcmd "$(printf "git commit -F - <<'M'\nthen git push later\nM")")")" allow "heredoc text mentioning git push"
expect guard.sh "$(in_s A "$(bashcmd "git status")")" allow "harmless command still runs"
expect guard.sh "$(in_s A "$(bashcmd "rm -rf /")")" deny "hard stop still denies"
expect edit-guard.sh "$(in_s A "$(edit src/calc.sh)")" allow "edits still run"

echo "-- other sessions are unaffected; quoted or glued --auto doesn't trigger"
expect guard.sh "$(in_s B "$(bashcmd "terraform apply")")" ask "session B still asks"
hook anchor.sh "$(prompt B 'what does the "--auto" flag do? see x--auto')"; has "$OUT" "[flow auto]" && bad "quoted --auto ignored" || ok "quoted --auto ignored"
expect guard.sh "$(in_s B "$ASK")" allow "session B can ask"
hook anchor.sh "$(prompt B "$(printf 'Another Claude session sent a message:\n<agent-message from="x">\n  it runs on --auto, but\n</agent-message>')")"
expect guard.sh "$(in_s B "$ASK")" allow "an agent message quoting --auto doesn't turn it on"
hook anchor.sh "$(prompt B "$(printf '<task-notification>\nran with --auto\n</task-notification>')")"
expect guard.sh "$(in_s B "$ASK")" allow "a task notification quoting --auto doesn't turn it on"

echo "-- --auto ship: push, PR, and merge proceed once ready.sh has stamped HEAD"
hook anchor.sh "$(prompt C "ship the queue --auto ship, I trust the gates")"
has "$OUT" "ship" && ok "anchor announces the ship grant" || bad "anchor ship ($OUT)"
expect guard.sh "$(in_s C "$(bashcmd "gh pr merge --squash")")" deny "ship, HEAD not stamped: merge waits"
printf '%s\t%s\tready\tpass\t\n' "$(date -u +%FT%TZ)" "$(git rev-parse HEAD)" >>.flow/ready.tsv
git checkout -q -b feat
printf '%s\t%s\tready\tpass\t\n' "$(date -u +%FT%TZ)" "$(git rev-parse HEAD)" >>.flow/ready.tsv
expect guard.sh "$(in_s C "$(bashcmd "git push -u origin feat")")" allow "ship + stamped: push the current branch"
for c in "git push origin refs/heads/main" "git push origin heads/main" "git push origin refs/heads/feat" "git push origin v1.0.0" "git push origin other"; do
  expect guard.sh "$(in_s C "$(bashcmd "$c")")" deny "ship refuses: $c"
done
has "$OUT" "--body-file" && ok "deny reason points to --body-file / --fill" || bad "reason: $OUT"
expect guard.sh "$(in_s C "$(bashcmd "gh pr merge --squash")")" allow "ship + stamped: merge"
expect guard.sh "$(in_s C "$(bashcmd "gh pr create --title x --body y")")" allow "ship + stamped: PR create"
for c in "git push origin main" "git push origin main;" "git push origin main && echo ok" "git push origin HEAD:refs/heads/main" \
         "git push origin +main" "git push origin 'main'" "git push" "git push origin HEAD" "git push --all" \
         "git push origin feat --force" "gh pr merge 99 --squash" "gh pr merge --admin --squash" "git push origin feat; git push origin main"; do
  expect guard.sh "$(in_s C "$(bashcmd "$c")")" deny "ship refuses: $c"
done
expect guard.sh "$(in_s C "$(bashcmd "npm publish")")" deny "ship doesn't cover publish"
expect guard.sh "$(in_s C "$(bashcmd "terraform apply")")" deny "ship doesn't open other gates"
expect guard.sh "$(in_s A "$(bashcmd "gh pr merge --squash")")" deny "plain --auto session A: merge still waits despite C's grant"
git commit -q --allow-empty -m "after stamp"
expect guard.sh "$(in_s C "$(bashcmd "gh pr merge --squash")")" deny "new HEAD needs a new stamp"
hook anchor.sh "$(prompt C "keep going --auto")"
printf '%s\t%s\tready\tpass\t\n' "$(date -u +%FT%TZ)" "$(git rev-parse HEAD)" >>.flow/ready.tsv
expect guard.sh "$(in_s C "$(bashcmd "gh pr merge --squash")")" deny "plain --auto drops the ship grant"

echo "-- --no-auto ends it"
hook anchor.sh "$(prompt A "I'm back --no-auto")"
has "$OUT" "[flow auto] off" && ok "anchor confirms off" || bad "anchor confirms off ($OUT)"
expect guard.sh "$(in_s A "$(bashcmd "terraform apply")")" ask "asks again after --no-auto"
expect guard.sh "$(in_s A "$ASK")" allow "AskUserQuestion allowed again"
finish
