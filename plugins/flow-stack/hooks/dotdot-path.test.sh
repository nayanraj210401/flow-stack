#!/usr/bin/env bash
# dotdot-path.test.sh: "." and ".." segments are resolved before edit-guard judges a path, so
# src/../docs/a.md does not pass a src/** fence and src/../tests/x.sh does not skip its seal.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"; PLUGIN="$(cd "$H/.." && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/dotdot.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR" "$SB/repo"
cd "$SB/repo"
# shellcheck source=/dev/null
. "$PLUGIN/evals/_lib/toy.sh"
toy_repo
toy_task demo "mul multiplies" "no division"
toy_mul_check
toy_slice demo S1 doing "bash tests/test_mul.sh" "src/** tests/test_add.sh"

# want <path> <allow|deny|ask> <label>
want() {
  local out d
  out="$(jq -nc --arg cwd "$PWD" --arg f "$1" \
    '{cwd:$cwd, hook_event_name:"PreToolUse", tool_name:"Edit", tool_input:{file_path:$f, old_string:"a", new_string:"b"}}' |
    "$H/edit-guard.sh" 2>/dev/null)" || true
  d="allow"; [ -z "$out" ] || d="$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out")"
  if [ "$d" = "$2" ]; then ok "$3 → $2"; else bad "$3 → got $d, want $2"; fi
}

echo "-- dot segments cannot leave the fence"
want "$PWD/src/../docs/a.md" deny "src/../docs/a.md"
want "src/../docs/a.md" deny "relative src/../docs/a.md"
want "src/../../outside.txt" deny "climbing above the root"
want "$PWD/tests/../src/../README.md" deny "tests/../src/../README.md"
echo "-- dot segments cannot skip the seal"
want "$PWD/src/../tests/test_mul.sh" ask "src/../tests/test_mul.sh"
want "tests/./test_mul.sh" ask "tests/./test_mul.sh"
echo "-- plain forms are unchanged"
want "$PWD/src/calc.sh" allow "src/calc.sh"
want "./src/calc.sh" allow "./src/calc.sh"
want "$PWD/src/./calc.sh" allow "src/./calc.sh"
want "$PWD/tests/../src/calc.sh" allow "tests/../src/calc.sh (resolves inside src/**)"
want "$PWD/tests/test_mul.sh" ask "tests/test_mul.sh"

[ "$FAILS" -eq 0 ] && { echo "== dotdot-path · PASS"; exit 0; }
echo "== dotdot-path · FAIL ($FAILS)"; exit 1
