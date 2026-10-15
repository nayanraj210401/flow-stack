#!/usr/bin/env bash
# render.test.sh: render.sh fills the template even when the board data contains the placeholder text.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
SB="$(mktemp -d "${TMPDIR:-/tmp}/render.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
printf '{"repos":[{"name":"fill {{BOARD_JSON}} placeholder </script>"}]}\n' >"$SB/b.json"
want='<script id="board-data" type="application/json">{"repos":[{"name":"fill {{BOARD_JSON}} placeholder <\/script>"}]}</script>'
if "$H/render.sh" "$SB/b.json" "$SB/out.html" >/dev/null 2>&1 && grep -qF "$want" "$SB/out.html"; then
  echo "  ✓ data containing {{BOARD_JSON}} renders verbatim, </ escaped"; echo PASS
else
  echo "  ✗ render.sh failed on data containing {{BOARD_JSON}}"; exit 1
fi
