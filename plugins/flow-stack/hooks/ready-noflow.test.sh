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
RUNNER_TEMP="$SB" GITHUB_ACTIONS=true GITHUB_RUN_ID=1 RUNNER_ENVIRONMENT=github-hosted is allow ship 'gh pr review 1 --comment --body ok'

echo "-- --auto ship with a stamped HEAD: the REST twins of gh pr create/ready pass (cloud has no GraphQL)"
mkdir -p .flow && printf '%s\t%s\tready\tpass\n' "$(date +%s)" "$(git rev-parse HEAD)" >.flow/ready.tsv
is allow ship 'gh api -X POST repos/o/r/pulls -f head=feat -f base=main'
is allow ship 'gh api -X POST repos/o/r/pulls/1/ccr/ready_for_review'
is deny ship 'gh api -X POST repos/o/r/pulls/1/merge'
is deny ship 'gh pr comment 1 --body hi'
[ "$FAILS" -eq 0 ] && echo "== ready-noflow · PASS" || { echo "== ready-noflow · FAIL ($FAILS)"; exit 1; }
