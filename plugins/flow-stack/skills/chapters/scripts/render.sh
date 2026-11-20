#!/usr/bin/env bash
# render.sh: check a filled story and draw it as the artifact page.
#   render.sh <story.json> <out.html>
# Refuses (exit 1, no page) while any why is uncited with no question for the author, any
# changed file is in no chapter, or any source, quote or hunk points at something not collected.
set -euo pipefail
[ $# -eq 2 ] || { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"; tpl="$here/../templates/story.html"
jq -e '.prs | type == "array"' "$1" >/dev/null 2>&1 || { echo "render.sh: $1 is not collect.sh output" >&2; exit 2; }
# story.jq is prepended, not included: jq's include would find a story.jq in the working directory first
lib="$(cat "$here/story.jq")"
errs="$(jq -r "$lib errors[]" "$1")"
if [ -n "$errs" ]; then echo "render.sh: not publishable yet:" >&2; sed 's/^/  - /' <<<"$errs" >&2; exit 1; fi
mkdir -p "$(dirname "$2")"
# one pass over the whole template, so a {{BODY}} inside the title is never expanded; in jq, so no
# page size hits the per-variable limit an env var or argument has
jq -j --rawfile tpl "$tpl" "$lib (.story.title | e) as \$t | page as \$b
  | \$tpl | gsub(\"\\\\{\\\\{(?<k>TITLE|BODY)\\\\}\\\\}\"; if .k == \"TITLE\" then \$t else \$b end)" "$1" >"$2"
echo "$2"
