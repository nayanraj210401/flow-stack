#!/usr/bin/env bash
set -e
. "$(dirname "$0")/../_lib/toy.sh"
toy_repo
mkdir -p lib
cat > lib/format.sh <<'SH'
# Money formatting used by receipts.
fmt_money() { # fmt_money <cents> [currency]  -> "$12.34" / "€12.34"
  local c="$1" cur="${2:-USD}" sym='$'
  [ "$cur" = EUR ] && sym='€'
  printf '%s%d.%02d\n' "$sym" $(( c / 100 )) $(( c % 100 ))
}
SH
cat > src/receipt.sh <<'SH'
. lib/format.sh
receipt_total() { echo "Total: $(fmt_money "$1" "$2")"; }
SH
git add -A && git commit -qm "receipts"
