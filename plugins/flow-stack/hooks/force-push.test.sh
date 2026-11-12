#!/usr/bin/env bash
# force-push.test.sh: guard.sh denies a force-push or delete of main/master however the flags are
# spelled, asks for any other force-push or a work-discarding reset/clean, and leaves ordinary pushes alone. Runs the working tree's hook.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
PASSES=0
ok()  { PASSES=$((PASSES + 1)); }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/force-push.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID
cd "$SB/repo" && git init -q

decide() {
  local out
  out="$(jq -nc --arg c "$PWD" --arg cmd "$1" '{hook_event_name:"PreToolUse",session_id:"s",cwd:$c,tool_name:"Bash",tool_input:{command:$cmd}}' | "$H/guard.sh")"
  [ -n "$out" ] || { echo allow; return; }
  jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out"
}
expect() { # expect <want> <command>
  local got; got="$(decide "$2")"
  [ "$got" = "$1" ] && ok "$1: $2" || bad "$2 → $got, want $1"
}

# -- force-push to main/master: deny
expect deny 'git push --force origin main'
expect deny 'git push origin main --force'
expect deny 'git -C . push --force origin main'
expect deny 'git -c user.name=x push --force origin main'
expect deny 'git push -fu origin main'
expect deny 'git push -uf origin master'
expect deny 'git push origin +main'
expect deny 'git push origin HEAD:+main'
expect deny 'git push origin HEAD:refs/heads/main -f'
expect deny "git push origin '+main'"
expect deny 'git push origin "+HEAD:main"'
expect deny 'git --work-tree . push -f origin main'
expect deny 'git --namespace foo push --force origin main'
expect deny 'git --git-dir .git --exec-path /x push -f origin main'
expect deny 'git --attr-source HEAD push -f origin main'
# -- deleting main/master: deny
expect deny 'git push origin :main'
expect deny 'git push origin :refs/heads/master'
expect deny 'git push --delete origin main'
expect deny 'git push -d origin master'
expect deny 'git -C . push origin --delete main'
expect deny "git push origin :'main'"
expect deny "git push origin '':main"
expect deny 'git push origin "":main'
expect deny 'bash -c "git push origin :main"'
expect deny 'git push origin refs/heads/main --force'
# -- force-push elsewhere: ask
expect ask 'git push -f origin feat/x'
expect ask 'git -C . push -f origin feat/x'
expect ask 'git -c k=v push -fu origin feat/x'
expect ask 'git push origin +feat/x'
expect ask 'git push -f origin feature/main'
expect ask 'git push --force origin HEAD:refs/heads/feature/main'
expect ask 'git push --force-with-lease origin feat/x'
expect ask "git push origin '+feat/x'"
expect ask 'git push --mirror'
expect ask "git push --prune origin 'refs/heads/*:refs/heads/*'"
expect ask 'git --super-prefix x push -f origin feat/x'
# -- ordinary pushes: allow
expect allow 'git push origin main'
expect allow 'git push -u origin main'
expect allow 'git push -u origin feat/maintenance'
expect allow 'git push origin :feat/x'
expect allow 'git push --delete origin feat/main'
expect allow 'git --work-tree . push origin main'
# -- discarding uncommitted work: ask, with global options or split/long flags
expect ask 'git reset --hard'
expect ask 'git -C . reset --hard'
expect ask 'git reset -q --hard HEAD~1'
expect ask 'git clean -fd'
expect ask 'git -c x=y clean -fd'
expect ask 'git clean -d -f'
expect ask 'git clean --force -d'
expect ask 'bash -c "git clean -fd"'
expect ask '(git clean -fdx)'
expect ask 'git clean -fd;ls'
expect ask 'git clean -fd&& ls'
expect allow 'git reset --soft HEAD~1'
expect allow 'git clean -n -d'

[ "$FAILS" -eq 0 ] && { echo "force-push: PASS ($PASSES passed)"; exit 0; }
echo "force-push: FAIL ($FAILS)"; exit 1
