#!/usr/bin/env bash
# render.sh: fill the board template with collect.sh's JSON.
#   render.sh <board.json> <out.html>
# The JSON is embedded in a <script type="application/json"> block; "</" is escaped
# so no value can close the tag. The page renders everything from that block.
set -euo pipefail
[ $# -eq 2 ] || { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
tpl="$(cd "$(dirname "$0")/../templates" && pwd)/board.html"
jq -e '.repos | type == "array"' "$1" >/dev/null || { echo "render.sh: $1 is not a board JSON" >&2; exit 2; }
mkdir -p "$(dirname "$2")"
JSON="$(jq -c . "$1" | sed 's#</#<\\/#g')" perl -pe 's/\{\{BOARD_JSON\}\}/$ENV{JSON}/' "$tpl" >"$2"
grep -q '{{BOARD_JSON}}' "$2" && { echo "render.sh: placeholder not filled" >&2; exit 1; }
echo "$2"
