#!/usr/bin/env bash
# env-read.test.sh: guard.sh denies reading a .env file however it's quoted, pathed or suffixed,
# even next to a .env.example arg, and allows the example/sample/template names. Runs the working tree's hook.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/env-read.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
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

echo "-- .env reads: deny"
expect deny 'cat .env'
expect deny 'cat "./.env"'
expect deny "cat '.env'"
expect deny 'cat .env .env.example'
expect deny 'cat .env.example .env'
expect deny 'cat .env.production.local'
expect deny 'cat .env..'
expect deny 'head -n 3 config/.env.local'
expect deny 'echo hi && tail .env|wc -l'
expect deny 'grep API_KEY .env'
expect deny 'sed -n p .env'
expect deny 'awk 1 .env'
expect deny 'tac .env'
expect deny 'nl .env'
expect deny 'sort .env'
expect deny 'cut -c1-100 .env'
expect deny 'od -c .env'
expect deny 'base64 .env'
expect deny 'cat<.env'
expect deny 'cat < .env'
expect deny 'while read l; do echo $l; done < .env'
echo "-- example/sample/template and non-.env names: allow"
expect allow 'cat .env.example'
expect allow 'cat ".env.sample" .env.template'
expect allow 'cat src/env.ts'
expect allow 'cat .envrc.md'
expect allow 'grep FOO README.md'
expect allow 'grep FOO .env.example'
expect allow 'sed -n p .env.sample'
expect allow 'cat<.env.example'
expect allow 'cp .env.example .env'
expect allow 'wc -l < README.md'

[ "$FAILS" -eq 0 ] && { echo "env-read: PASS"; exit 0; }
echo "env-read: FAIL ($FAILS)"; exit 1
