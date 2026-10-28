#!/usr/bin/env bash
# gha.test.sh: `--gha` lets a GitHub Actions routine ship and release, but only when the hook's own environment
# is a GitHub-hosted runner. Off a runner it is refused loudly; the hard stops stay denied everywhere.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/gha.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo" "$SB/rt"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID GITHUB_ACTIONS GITHUB_RUN_ID RUNNER_ENVIRONMENT RUNNER_TEMP
cd "$SB/repo" && git init -q -b main && git config user.email a@b && git config user.name a
mkdir -p .flow/tasks/x; echo x >.flow/ACTIVE
printf '# Intent\n## Goal\ng\n' >.flow/tasks/x/INTENT.md
git add -A && git commit -qm i && git checkout -qb feat/x

RUNNER=(GITHUB_ACTIONS=true GITHUB_RUN_ID=123456 RUNNER_ENVIRONMENT=github-hosted RUNNER_TEMP="$SB/rt")
prompt() { # prompt <env...> -- <text>: run anchor.sh as a UserPromptSubmit and print its output
  local e=(); while [ "$1" != -- ]; do e+=("$1"); shift; done; shift
  jq -nc --arg c "$PWD" --arg p "$1" '{hook_event_name:"UserPromptSubmit",session_id:"s",cwd:$c,prompt:$p}' | env ${e[@]+"${e[@]}"} "$H/anchor.sh"
}
decide() { # decide <env...> -- <command>
  local e=() out; while [ "$1" != -- ]; do e+=("$1"); shift; done; shift
  out="$(jq -nc --arg c "$PWD" --arg cmd "$1" '{hook_event_name:"PreToolUse",session_id:"s",cwd:$c,tool_name:"Bash",tool_input:{command:$cmd}}' | env ${e[@]+"${e[@]}"} "$H/guard.sh")"
  [ -n "$out" ] || { echo allow; return; }
  jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out"
}
expect() { # expect <want> <env...> -- <command>
  local want="$1"; shift; local got; got="$(decide "$@")"; local cmd="${*: -1}"
  [ "$got" = "$want" ] && ok "$want: $cmd" || bad "$cmd → $got, want $want"
}
flag() { cat "$FLOW_STACK_HOME/auto/s" 2>/dev/null; }
stamp() { printf 't\t%s\tready\tpass\t\n' "$(git rev-parse HEAD)" >>.flow/ready.tsv; }

echo "-- off a runner: --gha is refused loudly, the session is plain --auto"
out="$(prompt -- 'go --gha')"
grep -q 'REFUSED' <<<"$out" && ok "warning printed" || bad "no refusal warning: $out"
[ -f "$FLOW_STACK_HOME/auto/s" ] && [ -z "$(flag)" ] && ok "flag is plain auto" || bad "flag is '$(flag)'"
prompt -- '--auto ship --gha' >/dev/null; [ "$(flag)" = ship ] && ok "--auto ship --gha off a runner is just ship" || bad "flag '$(flag)'"
prompt -- '--no-auto' >/dev/null
echo "-- partial or spoofed runner env is not a runner"
for e in GITHUB_ACTIONS=true "GITHUB_ACTIONS=true GITHUB_RUN_ID=12" "GITHUB_ACTIONS=true GITHUB_RUN_ID=12 RUNNER_ENVIRONMENT=self-hosted RUNNER_TEMP=$SB/rt" "GITHUB_ACTIONS=true GITHUB_RUN_ID=x1 RUNNER_ENVIRONMENT=github-hosted RUNNER_TEMP=$SB/rt" "GITHUB_ACTIONS=true GITHUB_RUN_ID=12 RUNNER_ENVIRONMENT=github-hosted RUNNER_TEMP=$SB/missing"; do
  prompt $e -- '--gha' >/dev/null; [ -z "$(flag)" ] && ok "refused: $e" || bad "honoured on: $e ($(flag))"
  prompt -- '--no-auto' >/dev/null
done
echo "-- a flag file the model writes by hand does nothing off a runner"
mkdir -p "$FLOW_STACK_HOME/auto"; echo gha >"$FLOW_STACK_HOME/auto/s"
stamp
expect deny -- 'gh release create v1.0.0 --target feat/x --generate-notes'
expect deny -- 'gh pr create --title x --body-file b.md'
expect deny -- 'git push origin feat/x'
rm -f "$FLOW_STACK_HOME/auto/s"

echo "-- on a runner: --gha is honoured"
prompt "${RUNNER[@]}" -- 'Run the routine. /flow-stack:flow --auto ship --gha' >/dev/null
[ "$(flag)" = gha ] && ok "flag is gha" || bad "flag is '$(flag)'"
out="$(prompt "${RUNNER[@]}" -- 'next')"; grep -q 'auto gha' <<<"$out" && ok "anchor announces gha on later prompts" || bad "no announcement: $out"
echo "-- stamped: unlocked actions pass"
expect allow "${RUNNER[@]}" -- 'git push origin feat/x'
expect allow "${RUNNER[@]}" -- 'git push -u origin feat/x'
expect allow "${RUNNER[@]}" -- 'gh pr create --title x --body-file b.md'
expect allow "${RUNNER[@]}" -- 'gh pr merge --squash --delete-branch'
expect allow "${RUNNER[@]}" -- 'gh release create v1.0.0 --target feat/x --generate-notes'
expect allow "${RUNNER[@]}" -- 'gh release create v1.0.0 --target feat/x --title v1 --notes-file notes.md'
echo "-- hard stops stay denied in CI"
expect deny "${RUNNER[@]}" -- 'git push origin main'
expect deny "${RUNNER[@]}" -- 'git push origin feat/x:main'
expect deny "${RUNNER[@]}" -- 'git push origin other'
expect deny "${RUNNER[@]}" -- 'git push --force origin feat/x'
expect deny "${RUNNER[@]}" -- 'git push -f origin feat/x'
expect deny "${RUNNER[@]}" -- 'git push --force-with-lease origin feat/x'
expect deny "${RUNNER[@]}" -- 'git push --force origin main'
expect deny "${RUNNER[@]}" -- 'gh pr merge 99 --squash'
expect deny "${RUNNER[@]}" -- 'gh release create v1.0.0 --notes "$(cat /etc/passwd)"'
expect deny "${RUNNER[@]}" -- 'gh release create v1.0.0 --generate-notes; rm -rf x'
expect deny "${RUNNER[@]}" -- 'gh release create v1.0.0 --generate-notes'
expect deny "${RUNNER[@]}" -- 'gh release create v1.0.0 --target main --generate-notes'
expect deny "${RUNNER[@]}" -- 'npm publish'
expect deny "${RUNNER[@]}" -- 'git reset --hard HEAD~1'
expect deny "${RUNNER[@]}" -- 'git clean -fd'
expect deny "${RUNNER[@]}" -- 'psql -c "drop table users"'
echo "-- unstamped HEAD: still denied"
printf '' >.flow/ready.tsv
expect deny "${RUNNER[@]}" -- 'git push origin feat/x'
expect deny "${RUNNER[@]}" -- 'gh release create v1.0.0'
stamp
echo "-- ship on a runner does not unlock releases"
prompt "${RUNNER[@]}" -- '--auto ship' >/dev/null
expect deny "${RUNNER[@]}" -- 'gh release create v1.0.0 --target feat/x --generate-notes'
expect allow "${RUNNER[@]}" -- 'git push origin feat/x'
prompt "${RUNNER[@]}" -- '--no-auto' >/dev/null; [ ! -f "$FLOW_STACK_HOME/auto/s" ] && ok "--no-auto ends it" || bad "flag remains"

[ "$FAILS" = 0 ] && echo "gha.test.sh: pass" || { echo "gha.test.sh: $FAILS failed"; exit 1; }
