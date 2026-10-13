#!/usr/bin/env bash
# task-validate.test.sh: `new` rejects an unknown playbook and `estimate` rejects non-numbers (#100).
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd)/task.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/task-validate.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
cd "$SB/repo" && git init -q && git config user.email a@b && git config user.name a && git commit -q --allow-empty -m i

"$T" new bogus-pb nonesuch >/dev/null 2>&1 && bad "new accepted an unknown playbook" || ok "new rejects an unknown playbook"
[ -e .flow/tasks/bogus-pb ] && bad "rejected task was still created" || ok "no task folder left behind"
"$T" new real bug >/dev/null 2>&1 && ok "new accepts a built-in playbook" || bad "new rejected 'bug'"
"$T" estimate abc x y >/dev/null 2>&1 && bad "estimate accepted text" || ok "estimate rejects text"
"$T" estimate 1.5 20 30 >/dev/null 2>&1 && ok "estimate accepts numbers" || bad "estimate rejected numbers"
grep -q 'usd=1.5 ctx_pct=20 human_min=30' "$(ls .flow/tasks/real/ESTIMATE)" && ok "estimate stored" || bad "estimate not stored"
[ "$FAILS" = 0 ] || { echo "$FAILS failed"; exit 1; }
echo "all passed"
