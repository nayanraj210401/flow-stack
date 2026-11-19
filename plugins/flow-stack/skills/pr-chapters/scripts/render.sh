#!/usr/bin/env bash
# render.sh: check a filled story and draw it as the artifact page.
#   render.sh <story.json> <out.html>
# Refuses (exit 1, no page) while any why is uncited with no question for the author, any
# changed file is in no chapter, or any source, quote or hunk points at something not collected.
set -euo pipefail
[ $# -eq 2 ] || { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"; tpl="$here/../templates/story.html"
jq -e '.prs | type == "array"' "$1" >/dev/null 2>&1 || { echo "render.sh: $1 is not collect.sh output" >&2; exit 2; }
errs="$(jq -r -L "$here" 'include "story"; errors[]' "$1")"
if [ -n "$errs" ]; then echo "render.sh: not publishable yet:" >&2; sed 's/^/  - /' <<<"$errs" >&2; exit 1; fi
mkdir -p "$(dirname "$2")"
TITLE="$(jq -r -L "$here" 'include "story"; .story.title | e' "$1")"
BODY="$(jq -r -L "$here" 'include "story"; page' "$1")"
TITLE="$TITLE" BODY="$BODY" perl -pe 's/\{\{TITLE\}\}/$ENV{TITLE}/; s/\{\{BODY\}\}/$ENV{BODY}/' "$tpl" >"$2"
echo "$2"
