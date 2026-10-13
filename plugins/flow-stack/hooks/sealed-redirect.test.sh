#!/usr/bin/env bash
# sealed-redirect.test.sh: guard.sh asks only when a sealed check is written, not when it is read, run or copied from (#63).
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/sealed-redirect.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID
cd "$SB/repo" && git init -q && git config user.email a@b && git config user.name a
mkdir -p .flow/tasks/x/blind src tests; echo x > .flow/ACTIVE
printf '# Intent\n## Goal\ng\n' > .flow/tasks/x/INTENT.md
printf '## S1 a\nstatus: doing\nfence: src/**\n' > .flow/tasks/x/SLICES.md
printf 'abc  tests/a.test.sh\n' > .flow/tasks/x/SEALS
git add -A && git commit -qm i

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

expect allow 'cat tests/a.test.sh > /dev/null'
expect allow 'bash tests/a.test.sh > out.txt'
expect allow 'cp tests/a.test.sh /tmp/x'
expect allow 'cat tests/a.test.sh 2>&1'
expect ask   'echo x > tests/a.test.sh'
expect ask   'echo x >> tests/a.test.sh'
expect ask   'cp /tmp/x tests/a.test.sh'
expect ask   'mv tests/a.test.sh /tmp/x'
expect ask   'rm tests/a.test.sh'
expect ask   'sed -i s/a/b/ tests/a.test.sh'
expect ask   'cat x | tee tests/a.test.sh'
expect ask   'git checkout tests/a.test.sh'
expect ask   'echo x >| tests/a.test.sh'
expect ask   'install /tmp/x tests/a.test.sh'
expect ask   'dd if=/tmp/x of=tests/a.test.sh'
expect ask   'sed --in-place s/a/b/ tests/a.test.sh'
expect ask   'cd tests && echo x > a.test.sh'

[ "$FAILS" -eq 0 ] && echo ok || { echo "$FAILS failed"; exit 1; }
