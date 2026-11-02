#!/usr/bin/env bash
# ready-noflow.test.sh: --auto ship holds its ready stamp even in a fresh clone with no .flow/ (runners, cloud):
# without a stamp every gh pr create, draft or not, waits. Pair mode in a repo without .flow/ keeps today's
# behavior (no gate). Off a runner, auto mode also holds gh api writes, comments and reviews (#238).
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/ready-noflow.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"; trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude"
unset GITHUB_ACTIONS GITHUB_RUN_ID RUNNER_ENVIRONMENT HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID
mkdir -p "$FLOW_STACK_HOME/auto" "$SB/repo" && cd "$SB/repo" && git init -q && git commit -q --allow-empty -m init
decide() { # decide <session> <command>
  local out; out="$(jq -nc --arg c "$PWD" --arg s "$1" --arg cmd "$2" '{hook_event_name:"PreToolUse",session_id:$s,cwd:$c,tool_name:"Bash",tool_input:{command:$cmd}}' | "$H/guard.sh")"
  [ -n "$out" ] && jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out" || echo allow
}
is() { local got; got="$(decide "$2" "$3")"; [ "$got" = "$1" ] && ok "$1: [$2] $3" || bad "[$2] $3 → $got, want $1"; }

# the session "ship" runs --auto ship (the flag file anchor.sh writes)
printf ship >"$FLOW_STACK_HOME/auto/ship"
[ ! -d .flow ] || bad "fixture has .flow/"
is deny ship 'gh pr create --fill'
is deny ship 'gh pr create --draft --fill'
is allow pair 'gh pr create --fill'

echo "-- gh api and comment writes (#238)"
is deny ship 'gh api -X POST repos/o/r/pulls -f head=x -f base=main'
is deny ship 'gh api --method=PATCH repos/o/r/pulls/1'
is deny ship 'gh api repos/o/r/pulls/1/ccr/ready_for_review -f x=1'
is deny ship 'gh pr comment 1 --body hi'
is deny ship 'gh issue create --title x --body y'
is allow ship 'gh api repos/o/r/pulls/1'
is deny ship 'gh api -X DELETE repos/o/r/git/refs/heads/x'
is allow ship 'gh api repos/o/r/pulls/1 --jq .title'
is allow pair 'gh api -X POST repos/o/r/pulls -f head=x'
is deny ship 'gh api repos/o/r/issues/1/comments -fbody=x'
is deny ship 'gh api repos/o/r/issues/1/comments -Fbody=@f'
is deny ship 'gh api --method post repos/o/r/pulls/1/merge'
is allow ship 'gh api -X GET search/issues -f q=is:open'
# the session "plain" runs plain --auto: a GET elsewhere in a chain doesn't excuse a write
printf '' >"$FLOW_STACK_HOME/auto/plain"
is deny plain 'gh api -X GET user; gh api repos/o/r/issues/1/comments -f body=x'
is deny plain 'gh api repos/o/r/issues/1/comments -f body=x && gh api -X GET user'
is allow plain 'gh api -X GET user; gh api repos/o/r/pulls/1 --jq .title'
is deny plain 'gh api -X GET user $(gh api repos/o/r/issues/1/comments -f body=x)'
is deny plain 'gh api -X GET user `gh api repos/o/r/issues/1/comments -f body=x`'
is deny plain "gh api repos/o/r/issues/1/comments -f 'body=a -X GET b'"
is allow plain "gh api -X GET search/issues -f 'q=is:open label:bug'"
is deny plain 'gh api -X "DELETE" repos/o/r/git/refs/heads/main'
is deny plain "gh api --method 'PATCH' repos/o/r/issues/1"
is deny plain 'gh api repos/o/r/issues/1/comments -f body=x # -X GET'
is deny plain 'gh api repos/o/r/issues/1/comments -f "body=\"x -X GET \""'
is deny plain 'gh pr -R o/r comment 1 --body x'
is deny plain 'gh issue -R o/r edit 1 --title x'
is allow plain 'gh pr -R o/r view 1'
is deny plain "gh api repos/o/r/issues/1/comments -f 'a=\\' -f 'b= -X GET '"
is deny plain 'gh issue -R o/r create -t x -b y'
is deny plain 'gh issue --repo o/r create -t x -b y'
is deny plain 'gh api "repos/o/r/issues/1/comments?a=1&b=2" -f body=x'
is deny plain "gh api -H 'Accept: a|b' -X DELETE repos/o/r/git/refs/heads/main"
is deny plain 'gh api -X $M repos/o/r/issues/1'
is allow plain "git commit -m 'hold \`gh pr comment\`'"
is allow plain 'gh api "search/issues?q=a&per_page=5" -X GET'
is deny plain 'gh api repos/o/r/issues/1/comments --jq "map(.id)" -f body=x'
is deny plain "gh api -X GET user \\'; gh api repos/o/r/issues/1/comments -f body=x; echo \\'"
is deny plain "gh api repos/o/r/issues/1/comments -f \"p='\" -f z=\\' -f \"q= -X GET \""
is deny plain "gh pr 'comment' 1 --body x"
is deny plain 'gh pr comm\ent 1 --body x'
is deny plain '/usr/bin/gh api -X POST repos/o/r/issues/1/comments'
is deny plain 'bash -c "gh issue comment 1 --body x"'
is allow plain 'gh pr list --search "review edit close"'
is allow plain 'gh api repos/o/r/pulls/1 --jq "map(.id)"'
is deny plain 'gh api -if body=x repos/o/r/issues/1/comments'
is deny plain 'gh api -iXPOST repos/o/r/issues/1/comments'
is deny plain 'gh api -iX DELETE repos/o/r/git/refs/heads/main'
is deny plain "$(printf 'bash <<EOF\ngh pr comment 1 -b x\nEOF')"
is allow plain "$(printf 'cat <<EOF >notes.md\ngh pr comment 1 -b x\nEOF')"
is allow plain 'git commit -m "fix (gh pr comment) parsing"'
is allow plain 'git commit -m "tidy {gh pr edit} docs"'
is deny plain 'gh issue new -t x -b y'
is allow plain "gh api graphql -f query='query { viewer { login } }'"
is deny plain "gh api graphql -f query='mutation { addComment(input: {}) { clientMutationId } }'"
is deny plain 'gh api -X=DELETE repos/o/r/git/refs/heads/main'
is deny plain 'gh api graphql -F query=@q.graphql'
is deny plain 'gh api graphql -f query="$Q"'
is deny plain 'gh api graphql --input body.json'
is deny plain "$(printf 'cat <<-EOF\n\tx\n\tEOF\ngh pr comment 1 -b x')"
is deny plain "$(printf 'tr a b <<<"hello"\ngh pr comment 1 -b x')"
is deny plain 'gh api -X D$M repos/o/r/git/refs/heads/main'
is deny plain 'gh api --method `echo PATCH` repos/o/r/issues/1'
is deny plain 'gh api -X `echo DELETE` repos/o/r/git/refs/heads/main'
is deny plain 'gh `echo pr` comment 1 -b x'
is deny plain "$(printf 'cat <<EOF | bash\ngh pr comment 1 -b x\nEOF')"
is deny plain 'gh pr update-branch 1'
is deny plain 'gh issue unpin 1'
is allow plain 'gh --version'
is allow plain 'gh auth status'
is allow plain 'gh api -X HEAD repos/o/r'
is deny plain 'gh p`echo r` comment 1 -b x'
is deny plain 'gh pr comm`echo ent` 1 -b x'
is deny plain 'gh a`echo pi` -X DELETE repos/o/r/git/refs/heads/main'
is deny plain 'gh api $X DELETE repos/o/r/git/refs/heads/main'
is deny plain 'gh api repos/o/r/issues/1/comments $F body=x'
is deny plain 'echo comment 1 -b x | xargs gh pr'
is deny plain 'gh pr revert 1'
is deny plain 'gh issue artifact delete 1'
is deny plain "$(printf 'cat <<EOF | $SHELL\ngh pr comment 1 -b x\nEOF')"
is allow plain "$(printf 'which gh\ncommand -v gh\nbrew install gh')"
is allow plain "$(printf 'git commit -F - <<EOF; ls /bin/sh\nmentions gh pr comment\nEOF')"
is allow plain 'gh pr view 1 --json title'
is allow plain 'gh pr checks 1'
is allow plain 'gh run list -L 2'
is allow plain 'gh api repos/$REPO/pulls/1 --jq .title'
is allow plain 'gh pr list --search "review:required"'
is deny plain 'if ! gh pr comment 1 -b x; then echo no; fi'
is deny plain 'for i in 1 2; do gh issue comment 1 -b x; done'
is deny plain 'true && { gh issue comment 1 -b x; }'
is deny plain '! gh pr close 1'
is deny plain 'echo `gh pr close 1`'
is deny plain 'timeout 30s gh pr comment 1 -b x'
is deny plain 'sudo -u bob gh pr close 1'
is deny plain 'env -u GH_HOST gh pr close 1'
is deny plain 'xargs -I {} gh pr close {}'
is deny plain '"$GH" pr comment 1 -b x'
is deny plain "$(printf 'printf \"echo \x27a<<EOF\x27\"\ngh pr comment 1 -b x')"
is deny plain "$(printf '# note: <<EOF\ngh pr comment 1 -b x')"
is deny plain 'gh pr view 1 --jq "$(gh issue comment 1 -b x)"'
is deny plain 'gh pr list --search "$(gh pr close 1)"'
is deny plain 'gh api -X GET search/issues -f q="$(gh issue comment 1 -b x)"'
is deny plain 'gh label clone o/src'
is allow plain 'gh run view "$RUN_ID" --log-failed'
is allow plain 'gh pr view "$PR" --json title'
is allow plain 'gh search prs --author @me'
is allow plain 'gh status'
is allow plain 'gh pr --help'
is allow plain 'gh repo clone o/r'
is allow plain 'rg -n gh src'
is allow plain 'gh pr view 1 | grep gh'
is allow plain 'go build ./cmd/gh'
is allow plain 'ls ~/.config/gh'
is allow plain 'echo gh'
is deny plain 'nix develop -c gh pr comment 1 -b x'
is deny plain 'if "$GH" pr close 1; then :; fi'
is deny plain 'sudo $GH pr close 1'
is deny plain '"$GH" release delete v1 -y'
is deny plain '"$GH" repo delete o/r --yes'
is deny plain "$(printf 'echo \"<<EOF\"\ngh pr comment 1 -b x\nEOF')"
is deny plain 'gh pr comment 1 --body --help'
is allow plain "$(printf 'git commit -F - <<\x27EOF\x27\nmentions gh pr comment\nEOF')"
RUNNER_TEMP="$SB" GITHUB_ACTIONS=true GITHUB_RUN_ID=1 RUNNER_ENVIRONMENT=github-hosted is allow ship 'gh pr review 1 --comment --body ok'

echo "-- --auto ship with a stamped HEAD: the REST twins of gh pr create/ready pass (cloud has no GraphQL)"
mkdir -p .flow && printf '%s\t%s\tready\tpass\n' "$(date +%s)" "$(git rev-parse HEAD)" >.flow/ready.tsv
is allow ship 'gh api -X POST repos/o/r/pulls -f head=feat -f base=main'
is allow ship 'gh api -X POST repos/o/r/pulls/1/ccr/ready_for_review'
is deny ship 'gh api -X POST repos/o/r/pulls/1/merge'
is deny ship 'gh pr comment 1 --body hi'
is deny ship "$(printf 'gh api -X POST repos/o/r/pulls -f head=feat\ngh api -X DELETE repos/o/r/git/refs/heads/main')"
is deny ship "$(printf 'gh api -X POST repos/o/r/pulls -f head=feat\ngh pr comment 1 --body x')"
[ "$FAILS" -eq 0 ] && echo "== ready-noflow · PASS" || { echo "== ready-noflow · FAIL ($FAILS)"; exit 1; }
