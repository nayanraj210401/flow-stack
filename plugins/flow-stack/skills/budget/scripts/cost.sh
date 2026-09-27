#!/usr/bin/env bash
# cost.sh: token and dollar usage via ccusage.
#   cost.sh            today's usage
#   cost.sh session    per-session usage
#   cost.sh <args>     passed through to ccusage
set -uo pipefail
if command -v ccusage >/dev/null 2>&1; then run=(ccusage)
elif command -v npx >/dev/null 2>&1; then run=(npx -y ccusage@latest)
else echo "cost.sh: ccusage not available (run /flow-stack:setup)"; exit 1; fi
if [ $# -eq 0 ]; then "${run[@]}" daily --since "$(date +%Y%m%d)"; else "${run[@]}" "$@"; fi
