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
# grep over the transcript list, one path per line; NUL-delimited so a path with spaces stays whole.
grep_files() { tr '\n' '\0' <<<"$files" | xargs -0 grep -ho "$1" 2>/dev/null; }
section() { echo "## $1"; cat | sort | uniq -c | sort -rn | head -n "${2:-15}"; }
grep_files '"name":"Skill","input":{"skill":"[^"]*"' | sed 's/.*"skill":"//; s/"$//' | section skills
grep_files '<command-name>[^<]*</command-name>' | sed 's/<[^>]*>//g' | section "slash commands"
grep_files '"name":"mcp__[A-Za-z0-9_-]*__' | sed 's/"name":"mcp__//; s/__$//' | section "mcp servers"
grep_files '"subagent_type":"[^"]*"' | sed 's/.*:"//; s/"$//' | section "subagent types" 10
exit 0
