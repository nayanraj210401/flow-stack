#!/usr/bin/env bash
# checkout-branch.test.sh: in TDD green, guard.sh locks tests against `git checkout <path>` but
# lets `git checkout <branch>` through, even when the branch name looks like a test path (#64).
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/checkout-branch.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID
cd "$SB/repo" && git init -q && git config user.email a@b && git config user.name a
mkdir -p .flow/tasks/x src tests; echo x > .flow/ACTIVE
printf '# Intent\n## Goal\ng\n' > .flow/tasks/x/INTENT.md
printf '## S1 a\nstatus: doing\nfence: src/** tests/**\n' > .flow/tasks/x/SLICES.md
echo 'echo ok' > tests/a.test.sh
git add -A && git commit -qm i
echo 'S1 green 1' > .flow/tasks/x/TDD

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

echo "-- switching branches passes"
expect allow 'git checkout main'
expect allow 'git checkout feature/tests/x'
expect allow 'git checkout -b tests/x'
expect allow 'git checkout -b feat/a.test.sh origin/feat/a.test.sh'
echo "-- writing a test through checkout/restore is denied"
expect deny 'git checkout -- tests/a.test.sh'
expect deny 'git checkout HEAD -- tests/a.test.sh'
expect deny 'git checkout tests/a.test.sh'
expect deny 'git checkout HEAD tests/a.test.sh'
expect deny 'git restore tests/a.test.sh'

[ "$FAILS" -eq 0 ] && { echo "== checkout-branch · PASS"; exit 0; }
echo "== checkout-branch · FAIL ($FAILS)"; exit 1
