#!/usr/bin/env bash
# diffstat.test.sh: untracked files are counted like tracked ones: text lines including an
# unterminated last line, binary files as 0.
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
PASSES=0
ok()  { PASSES=$((PASSES + 1)); }
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
mkdir -p src/sub; echo a >src/top.sh; echo b >src/sub/deep.sh
out="$(bash "$D/diffstat.sh" 'src/*.sh')"
grep -q '^added=2 ' <<<"$out" && ok "src/*.sh crosses / like the fence hook" || bad "fence glob: $out"
out="$(bash "$D/diffstat.sh" 'src/**/*.sh')"
grep -q '^added=2 ' <<<"$out" && ok "src/**/*.sh matches zero dirs" || bad "** glob: $out"
printf "a\nb\n" >src/é.sh
out="$(bash "$D/diffstat.sh" "src/*.sh")"
grep -q "^added=4 " <<<"$out" && ok "non-ASCII name matches the fence" || bad "non-ASCII fence: $out"
git add src/top.sh && git -c user.name=t -c user.email=t@t commit -q -m top
git mv src/top.sh src/moved.sh && printf "z\n" >>src/moved.sh
out="$(bash "$D/diffstat.sh" "src/*.sh")"
grep -q "moved.sh" <<<"$out" && ok "renamed file matches the fence" || bad "rename fence: $out"
grep -q " deleted_files=1" <<<"$out" && ok "rename counts the old path as deleted" || bad "rename deleted_files: $out"
grep -q "top.sh" <<<"$out" && ok "rename lists the removed old path" || bad "rename old path: $out"
X="$(mktemp -d "${TMPDIR:-/tmp}/diffstat-tools.XXXXXX")"; trap 'rm -rf "$SB" "$X"' EXIT
mkdir -p "$X/skills/loop/scripts" && cp "$D/diffstat.sh" "$X/skills/loop/scripts/" && cp -R "$D/../../../hooks" "$X/hooks"
out="$(cd "$SB/src" && bash "../../$(basename "$X")/skills/loop/scripts/diffstat.sh" "src/*.sh" 2>&1)"
grep -q "moved.sh" <<<"$out" && ok "runs by a relative path from another dir" || bad "relative path run: $out"
[ "$FAILS" -eq 0 ] && echo "diffstat: $PASSES passed" || { echo "diffstat: $FAILS failed"; exit 1; }
