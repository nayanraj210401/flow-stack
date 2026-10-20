#!/usr/bin/env bash
# sealed-intent.test.sh: in a sealed task, guard.sh asks when INTENT.md or SEALS is written
# (redirect or cp target, sed -i, tee, mv, rm, truncate) and allows commands that only read them,
# even when a word contains "rm"/"mv"/"cp"/"tee" or the command redirects stderr (#145).
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/sealed-intent.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID
cd "$SB/repo" && git init -q && git config user.email a@b && git config user.name a
mkdir -p .flow/tasks/x src tests; echo x > .flow/ACTIVE
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

echo "-- reading the contract is allowed"
expect allow 'cat .flow/tasks/x/INTENT.md'
expect allow 'grep -n confirm .flow/tasks/x/INTENT.md'
expect allow 'grep -c format .flow/tasks/x/INTENT.md'
expect allow 'grep Goal .flow/tasks/x/INTENT.md 2>&1'
expect allow 'grep -c committee .flow/tasks/x/SEALS'
expect allow 'cp .flow/tasks/x/INTENT.md /tmp/intent-copy.md'
expect allow 'wc -l .flow/tasks/x/SEALS > /tmp/count'

echo "-- writing the contract asks"
expect ask 'echo x > .flow/tasks/x/INTENT.md'
expect ask 'echo x >> .flow/tasks/x/SEALS'
expect ask 'cp /tmp/x .flow/tasks/x/INTENT.md'
expect ask 'sed -i s/g/h/ .flow/tasks/x/INTENT.md'
expect ask 'echo x | tee .flow/tasks/x/INTENT.md'
expect ask 'mv /tmp/x .flow/tasks/x/SEALS'
expect ask 'rm .flow/tasks/x/SEALS'
expect ask 'rm -f .flow/tasks/x/INTENT.md'
expect ask 'truncate -s 0 .flow/tasks/x/INTENT.md'
expect ask 'cd .flow/tasks/x && /bin/rm INTENT.md'

[ "$FAILS" -eq 0 ] && { echo "== sealed-intent · PASS"; exit 0; }
echo "== sealed-intent · FAIL ($FAILS)"; exit 1
