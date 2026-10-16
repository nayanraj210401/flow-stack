#!/usr/bin/env bash
# ready-stdin.test.sh: a ready[] run entry that reads stdin must not swallow the entries after it (#119).
set -uo pipefail
R="$(cd "$(dirname "$0")" && pwd)/ready.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/ready-stdin.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
cd "$SB/repo" && git init -q && git config user.email a@b && git config user.name a
mkdir -p .flow
echo hi >f && git add f && git commit -qm i
cat >.flow/config.json <<'JSON'
{"ready":[{"id":"reader","run":"cat >/dev/null"},{"id":"later-ok","run":"test -f f"},{"id":"later-bad","run":"test -f nope"}]}
JSON
out="$("$R" </dev/null 2>&1)"
grep -q '✓ later-ok' <<<"$out" && ok "an entry after a stdin reader still runs" || bad "later-ok never reported: $out"
grep -q '✗ later-bad' <<<"$out" && ok "a failing entry after a stdin reader is reported" || bad "later-bad never reported: $out"
[ "$FAILS" = 0 ] || { echo "== ready-stdin · FAIL ($FAILS)"; exit 1; }
echo "== ready-stdin · PASS"
