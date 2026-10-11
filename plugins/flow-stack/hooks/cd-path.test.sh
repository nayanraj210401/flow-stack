#!/usr/bin/env bash
# cd-path.test.sh: guard.sh's blind-check and sealed-file checks see paths as the shell resolves
# them, so `cd <dir> && ...` and globs like .flow/tasks/*/bl* don't hide them. Runs the working tree's hook.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/cd-path.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
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

echo "-- blind checks: deny however the path is reached"
expect deny 'cat .flow/tasks/x/blind/a'
expect deny 'cd .flow/tasks/x && cat blind/a'
expect deny 'cd .flow/tasks/x/blind; cat a'
expect deny 'cd .flow && cd tasks/x && cat blind/a'
expect deny "cd $PWD/.flow/tasks/x && cat blind/a"
expect deny 'ls .flow/tasks/*/bl*'
expect deny 'cat .flow/tasks/x/b?ind/a'
echo "-- sealed checks: ask however the path is reached"
expect ask 'echo x > tests/a.test.sh'
expect ask 'cd tests && echo x > a.test.sh'
expect ask 'cd tests && echo x >a.test.sh'
expect ask 'cd tests && sed -i s/t/u/ a.test.sh'
expect ask 'cd src && rm ../tests/a.test.sh'
echo "-- unrelated commands pass"
expect allow 'cd .flow/tasks/x && cat SLICES.md'
expect allow 'ls .flow/tasks/*/SLICES.md'
expect allow 'cd tests && echo x > b.test.sh'
expect allow 'cd src && cat a.test.sh'
expect allow 'cd tests && cat a.test.sh'

[ "$FAILS" -eq 0 ] && { echo "== cd-path · PASS"; exit 0; }
echo "== cd-path · FAIL ($FAILS)"; exit 1
