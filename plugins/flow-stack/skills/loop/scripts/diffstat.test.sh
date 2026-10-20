#!/usr/bin/env bash
# diffstat.test.sh: untracked files are counted like tracked ones: text lines including an
# unterminated last line, binary files as 0.
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/diffstat.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
cd "$SB" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
printf 'a\nb\nc' >nonl.txt
printf 'x\ny\n' >ok.txt; : >empty.txt
printf '\n\n\n\n\n\0\n\n' >bin.dat
out="$(bash "$D/diffstat.sh")"
grep -q '^added=5 ' <<<"$out" && ok "added=5 (3 + 2, binary 0)" || bad "wrong total: $out"
grep -q '+3 .*nonl.txt' <<<"$out" && ok "unterminated last line counted" || bad "nonl.txt: $out"
grep -q '+0 .*bin.dat' <<<"$out" && ok "binary counts 0" || bad "bin.dat: $out"
grep -q "empty.txt" <<<"$out" && ok "empty file still listed" || bad "empty.txt dropped: $out"
[ "$FAILS" = 0 ]
