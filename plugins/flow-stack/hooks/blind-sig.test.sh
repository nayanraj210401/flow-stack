#!/usr/bin/env bash
# blind-sig.test.sh: the circuit breaker keeps a blind-run failure's full signature (#137).
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)/post-tool.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/blind-sig.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
cd "$SB/repo" && git init -q && git config user.email a@b && git config user.name a
mkdir -p .flow/tasks/x; echo x >.flow/ACTIVE; git add -A; git commit -qm i --allow-empty

fire() { # <stdout of the Bash tool>
  jq -n --arg o "$1" '{tool_name:"Bash",session_id:"s1",cwd:env.PWD,tool_input:{command:"blind-run.sh"},tool_response:{stdout:$o,stderr:""}}' | "$H"
}
r=""
for sig in blind1a2b3 blind4c5d6 blind7e8f9; do r="$(fire "flow-evidence: FAIL sig=$sig")"; done
[ -z "$r" ] && ok "three different blind failures do not trip the breaker" || bad "tripped: $r"
for i in 1 2 3; do r="$(fire "flow-evidence: FAIL sig=blindaaaaa")"; done
grep -q 'sig blindaaaaa' <<<"$r" && ok "three identical blind failures trip it, with the full sig" || bad "identical repeat did not trip: $r"
[ "$FAILS" = 0 ] || { echo "== blind-sig · FAIL ($FAILS)"; exit 1; }
echo "== blind-sig · PASS"
