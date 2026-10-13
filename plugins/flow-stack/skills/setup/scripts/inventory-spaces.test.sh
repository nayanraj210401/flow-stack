#!/usr/bin/env bash
# inventory-spaces.test.sh: skills/agents/commands with a space in the name stay one entry (#98).
set -uo pipefail
I="$(cd "$(dirname "$0")" && pwd)/inventory.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/inventory-spaces.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json" FLOW_STACK_HOME="$SB/home" HOME="$SB/hm"
mkdir -p "$SB/claude/skills/my skill" "$SB/claude/skills/plain" "$SB/claude/agents" "$SB/claude/commands" "$SB/repo/.claude/skills/repo one" "$SB/hm"
touch "$SB/claude/agents/my agent.md" "$SB/claude/commands/do it.md"
cd "$SB/repo" && git init -q
out="$("$I")"
chk() { [ "$(jq -c "$1" <<<"$out")" = "$2" ] && ok "$1 = $2" || bad "$1 = $(jq -c "$1" <<<"$out"), want $2"; }
jq -e . <<<"$out" >/dev/null || { echo "$out"; bad "output is not json"; }
chk .user_skills '["my skill","plain"]'
chk .repo_skills '["repo one"]'
chk .user_agents '["my agent"]'
chk .user_commands '["do it"]'
[ "$FAILS" = 0 ] || { echo "$FAILS failed"; exit 1; }
echo "all passed"
