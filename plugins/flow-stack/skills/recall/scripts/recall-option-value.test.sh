#!/usr/bin/env bash
# recall-option-value.test.sh: an option given without a value must print a usage error
# naming the option and exit 2, not die with "$2: unbound variable".
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

for opt in --days --repo --skip; do
  out="$(bash "$D/recall.sh" sessions "$opt" 2>&1)"; rc=$?
  [ "$rc" = 2 ] && ok "$opt: exit 2" || bad "$opt: exit $rc, want 2"
  grep -q -- "$opt needs a value" <<<"$out" && ok "$opt: names the option" || bad "$opt: got: $out"
  grep -q "unbound variable" <<<"$out" && bad "$opt: raw bash error" || ok "$opt: no raw bash error"
done
[ "$FAILS" = 0 ]
