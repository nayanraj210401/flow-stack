#!/usr/bin/env bash
# feature.map: features.sh lints the map, maps a diff to features, runs scenarios
# (marking verified/broken), finds stale features and unowned code, and scaffolds new ones.
. "$(dirname "$0")/lib.sh"; sandbox feature.map
toy_features >/dev/null
F="$S/feature-map/scripts/features.sh"
st() { "$F" list | awk -v i="$1" '$1 == i { v = substr($0, 30, 33); gsub(/ +/, " ", v); sub(/ $/, "", v); print v }'; } # status [verified date sha]

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
before="$(cat .flow/features/calc.add.md)"
sees "run calc.add → PASS" "feat:calc.add · PASS" "$F" run calc.add
[[ "$(st calc.add)" =~ ^verified\ [0-9-]{10}\ [0-9a-f]+$ ]] && ok "status + verified stamp written" || bad "not marked: $(st calc.add)"
[ "$(cat .flow/features/calc.add.md)" = "$before" ] && grep -q $'^calc.add\tverified\t' .flow/verified.tsv && ok "stamp in .flow/verified.tsv, feature file unchanged" || bad "feature file rewritten"
perl -pi -e 's/^scenario: .*/scenario: false/' .flow/features/export.csv.md
sees "failing scenario → FAIL" "feat:export.csv · FAIL" "$F" run export.csv
[ "$(st export.csv)" = "broken" ] && ok "marked broken" || bad "not broken: $(st export.csv)"
perl -pi -e 's/^scenario: .*/scenario: /' .flow/features/export.csv.md
sees "no scenario → says so" "NO SCENARIO" "$F" run export.csv
echo "-- stale"
git add -A && git commit -qm verified
printf '# change\n' >>src/calc.sh && git commit -qam "change calc"
sees "owned code changed since verified → STALE" "calc.add · STALE" "$F" stale --write
[ "$(st calc.add | cut -d' ' -f1)" = stale ] && ok "--write marks stale" || bad "not stale: $(st calc.add)"
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
