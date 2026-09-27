#!/usr/bin/env bash
# usage.sh [days]: what the user actually uses, from local Claude Code transcripts.
# Counts Skill invocations, slash commands, MCP servers, and subagent types over
# the last N days (default 30). Prints counts only; no transcript content.
set -uo pipefail
C="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
days="${1:-30}"
files="$(find "$C/projects" -name '*.jsonl' -mtime "-$days" 2>/dev/null)"
[ -n "$files" ] || { echo "no transcripts in the last $days days"; exit 0; }
n="$(wc -l <<<"$files" | tr -d ' ')"
echo "# usage · last $days days · $n transcripts"
section() { echo "## $1"; cat | sort | uniq -c | sort -rn | head -n "${2:-15}"; }
xargs grep -ho '"name":"Skill","input":{"skill":"[^"]*"' <<<"$files" 2>/dev/null | sed 's/.*"skill":"//; s/"$//' | section skills
xargs grep -ho '<command-name>[^<]*</command-name>' <<<"$files" 2>/dev/null | sed 's/<[^>]*>//g' | section "slash commands"
xargs grep -ho '"name":"mcp__[A-Za-z0-9_-]*__' <<<"$files" 2>/dev/null | sed 's/"name":"mcp__//; s/__$//' | section "mcp servers"
xargs grep -ho '"subagent_type":"[^"]*"' <<<"$files" 2>/dev/null | sed 's/.*:"//; s/"$//' | section "subagent types" 10
exit 0
