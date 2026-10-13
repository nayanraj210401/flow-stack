#!/usr/bin/env bash
# usage.sh counts transcripts under a path with spaces (#51).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
mkdir -p "$t/projects/p1" "$t/projects/my proj"
line='{"name":"Skill","input":{"skill":"flow-stack:flow"}}'
printf '%s\n%s\n' "$line" "$line" >"$t/projects/p1/s.jsonl"
printf '%s\n%s\n' "$line" "$line" >"$t/projects/my proj/t.jsonl"
out="$(CLAUDE_CONFIG_DIR="$t" "$here/usage.sh" 30)"
grep -Eq '^ *4 flow-stack:flow$' <<<"$out" || { echo "FAIL: expected 4 flow-stack:flow"; echo "$out"; exit 1; }
echo ok
