#!/usr/bin/env bash
# feature.map: features.sh lints the map, maps a diff to features, runs scenarios
# (marking verified/broken), finds stale features and unowned code, and scaffolds new ones.
. "$(dirname "$0")/lib.sh"; sandbox feature.map
toy_features >/dev/null
F="$S/feature-map/scripts/features.sh"

sees "check passes" "feature map ok (2 features)" "$F" check
sees "list shows both" "export.csv" "$F" list
echo "-- impact"
echo '# tweak' >>src/calc.sh; printf 'x\n' >src/loose.sh
out="$("$F" impact)"; echo "$out" >"$ART/impact.txt"
has "$out" $'calc.add\tsrc/calc.sh' && ok "src/calc.sh → calc.add" || bad "impact: $out"
has "$out" $'unowned\tsrc/loose.sh' && ok "untracked src/loose.sh → unowned" || bad "no unowned"
has "$out" export.csv && bad "export.csv flagged without a change" || ok "export.csv not impacted"
[ "$("$F" impact --ids)" = calc.add ] && ok "--ids" || bad "--ids: $("$F" impact --ids)"
git checkout -q src/calc.sh; rm src/loose.sh
echo "-- run marks verified / broken"
sees "run calc.add → PASS" "feat:calc.add · PASS" "$F" run calc.add
grep -q '^status: verified' .flow/features/calc.add.md && grep -qE '^verified: [0-9-]{10} [0-9a-f]+' .flow/features/calc.add.md && ok "status + verified stamp written" || bad "not marked"
perl -pi -e 's/^scenario: .*/scenario: false/' .flow/features/export.csv.md
sees "failing scenario → FAIL" "feat:export.csv · FAIL" "$F" run export.csv
grep -q '^status: broken' .flow/features/export.csv.md && ok "marked broken" || bad "not broken"
perl -pi -e 's/^scenario: .*/scenario: /' .flow/features/export.csv.md
sees "no scenario → says so" "NO SCENARIO" "$F" run export.csv
echo "-- stale"
git add -A && git commit -qm verified
printf '# change\n' >>src/calc.sh && git commit -qam "change calc"
sees "owned code changed since verified → STALE" "calc.add · STALE" "$F" stale --write
grep -q '^status: stale' .flow/features/calc.add.md && ok "--write marks stale" || bad "not stale"
echo "-- coverage, index, new, subs"
printf 'y\n' >src/orphan.sh && git add src/orphan.sh
sees "coverage lists unowned code" "src/orphan.sh" "$F" coverage
check "index writes README" "$F" index
grep -q '\[calc.add\](calc.add.md)' .flow/features/README.md && ok "README table row" || bad "README missing row"
check "new scaffolds" "$F" new auth.login "Log in"
fails "check rejects an unfilled scaffold" "$F" check
sees "…naming the placeholder" "entries still the template placeholder" "$F" check
rm .flow/features/auth.login.md
sees "subs lists sub-feature IDs" "calc.add.sum · add 2 3 prints 5" "$F" subs calc.add
cp -R .flow/features "$ART/"
finish
