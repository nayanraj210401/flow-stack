#!/usr/bin/env bash
# status-empty-title.test.sh: `status.sh --full` keeps an empty slice title empty instead of shifting the status into it (#131).
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/status-empty-title.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
cd "$SB/repo" && git init -q && git config user.email a@b && git config user.name a && git commit -q --allow-empty -m i
"$D/task.sh" new t bug >/dev/null || { echo "setup failed"; exit 1; }
printf '# Slices\n\n## S1 · \nstatus: doing\n\n## S2 · named\nstatus: todo\n' >.flow/tasks/t/SLICES.md

out="$("$D/status.sh" --full 2>/dev/null)"
s1="$(jq -c '.slices[] | select(.id == "S1") | [.title, .status]' <<<"$out" 2>/dev/null)"
[ "$s1" = '["","doing"]' ] && ok "empty title stays empty, status kept" || bad "S1 → $s1"
s2="$(jq -c '.slices[] | select(.id == "S2") | [.title, .status]' <<<"$out" 2>/dev/null)"
[ "$s2" = '["named","todo"]' ] && ok "a titled slice is unchanged" || bad "S2 → $s2"
[ "$FAILS" = 0 ] || { echo "== status-empty-title · FAIL ($FAILS)"; exit 1; }
echo "== status-empty-title · PASS"
