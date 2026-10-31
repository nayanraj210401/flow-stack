#!/usr/bin/env bash
# factory.test.sh: factory.sh maps fixture Project cards to columns, dry-run prints the moves, apply makes
# them and a re-run moves nothing; collect.sh adds board.factory only when the profile names a project,
# and the page renders the factory panel from it. gh is a stub over fixture GraphQL JSON; nothing real is touched.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
SB="$(mktemp -d "${TMPDIR:-/tmp}/factory.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
fail=0; ck() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }

mkdir -p "$SB/bin" "$SB/home"
# stub gh: graphql returns the fixture; item-edit sets that card's Status in the fixture and logs the call
cat >"$SB/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >>"$FIX.log"
[ -n "${GH_FAIL:-}" ] && { echo "HTTP 401" >&2; exit 1; }
case "$1 $2" in
  "api graphql") cat "$FIX" ;;
  "project item-edit") shift 2; while [ $# -gt 0 ]; do case "$1" in --id) id="$2" ;; --single-select-option-id) o="$2" ;; esac; shift 2; done
    jq --arg id "$id" --arg o "$o" '(.data.repositoryOwner.projectV2) as $p | ([$p.field.options[] | select(.id == $o)][0].name) as $n
      | .data.repositoryOwner.projectV2.items.nodes |= map(if .id == $id then .fieldValueByName = {name: $n} else . end)' "$FIX" >"$FIX.new" && mv "$FIX.new" "$FIX" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$SB/bin/gh"
export PATH="$SB/bin:$PATH" FIX="$SB/project.json" FLOW_STACK_HOME="$SB/home"

L='"labels":{"nodes":[%s]},"timelineItems":{"nodes":[%s]}'
lab() { local o=""; for n in "$@"; do o="$o${o:+,}{\"name\":\"$n\"}"; done; printf '%s' "$o"; }
ev() { local o=""; for n in "$@"; do o="$o${o:+,}{\"createdAt\":\"2026-10-02T00:00:00Z\",\"label\":{\"name\":\"$n\"}}"; done; printf '%s' "$o"; }
card() { # card <item-id> <status|-> <content-json>
  local s='null'; [ "$2" = - ] || s="{\"name\":\"$2\"}"; printf '{"id":"%s","fieldValueByName":%s,"content":%s}' "$1" "$s" "$3"; }
iss() { # iss <n> <state> <reason> <body> <labels-csv> <relabels-csv>
  printf '{"__typename":"Issue","number":%s,"title":"issue %s","url":"https://github.com/o/r/issues/%s","state":"%s","stateReason":%s,"createdAt":"2026-10-01T00:00:00Z","body":"%s","repository":{"nameWithOwner":"o/r"},'"$L"'}' \
    "$1" "$1" "$1" "$2" "$3" "$4" "$(IFS=,; lab $5)" "$(IFS=,; ev $6)"; }
pr() { # pr <n> <state> <draft> <mergedAt|null> <labels-csv> <relabels-csv> <flow/ready conclusion|-> <closing issue labels-csv|->
  local cl='[]' ck='[]'
  [ "$8" = - ] || cl="[{\"number\":10,\"createdAt\":\"2026-10-01T00:00:00Z\",\"labels\":{\"nodes\":[$(IFS=,; lab $8)]}}]"
  [ "$7" = - ] || ck="[{\"name\":\"flow/ready\",\"conclusion\":\"$7\"},{\"name\":\"test\",\"conclusion\":\"SUCCESS\"}]"
  printf '{"__typename":"PullRequest","number":%s,"title":"pr %s","url":"https://github.com/o/r/pull/%s","state":"%s","isDraft":%s,"createdAt":"2026-10-02T00:00:00Z","mergedAt":%s,"repository":{"nameWithOwner":"o/r"},'"$L"',"closingIssuesReferences":{"nodes":%s},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":%s}}}}]}}' \
    "$1" "$1" "$1" "$2" "$3" "$4" "$(IFS=,; lab $5)" "$(IFS=,; ev $6)" "$cl" "$ck"; }
opts=""; for c in Triage "Spec review" Building Rework Ready Merged Blocked; do opts="$opts${opts:+,}{\"id\":\"opt-$c\",\"name\":\"$c\"}"; done
cards=(
  "$(card I1 - "$(iss 1 OPEN null "" "" "")")"
  "$(card I2 "Spec review" "$(iss 2 OPEN null "" "" "")")"
  "$(card I3 "Spec review" "$(iss 3 OPEN null "" needs-human needs-human)")"
  "$(card P4 - "$(pr 4 OPEN true null "" "" - -)")"
  "$(card P5 Building "$(pr 5 OPEN true null rework,self-heal rework - -)")"
  "$(card P6 Building "$(pr 6 OPEN true null self-heal "" SUCCESS -)")"
  "$(card P7 Ready "$(pr 7 MERGED false '"2026-10-02T12:00:00Z"' risk:high rework SUCCESS risk:low)")"
  "$(card I8 Building "$(iss 8 CLOSED '"COMPLETED"' "" "" "")")"
  "$(card I9 Triage "$(iss 9 OPEN null "regressed by #7" type:bug "")")"
  "$(card I11 Triage "$(iss 11 CLOSED '"NOT_PLANNED"' "" "" "")")"
  "$(card D12 Triage '{"__typename":"DraftIssue"}')"
)
printf '{"data":{"repositoryOwner":{"projectV2":{"id":"PVT_1","url":"https://github.com/users/o/projects/3","title":"Factory","field":{"id":"F_status","options":[%s]},"items":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[%s]}}}}}\n' \
  "$opts" "$(IFS=,; echo "${cards[*]}")" >"$FIX"
jq -e . "$FIX" >/dev/null || { echo "  ✗ fixture is not JSON"; exit 1; }
cp "$FIX" "$SB/project.orig.json"

ck "no project configured: exit 3, nothing printed" '"$H/factory.sh" dry-run >"$SB/o" 2>/dev/null; [ $? = 3 ] && [ ! -s "$SB/o" ]'
printf -- '---\nrigor: lean\nfactory:\n  project: o/3   # the factory board\n---\n' >"$SB/home/profile.md"
ck "project read from the profile" '[ "$("$H/factory.sh" project)" = o/3 ]'

"$H/factory.sh" dry-run >"$SB/dry" 2>&1
want='would move o/r#1: no status → Triage
would move o/r#3: Spec review → Blocked
would move o/r#4: no status → Building
would move o/r#5: Building → Rework
would move o/r#6: Building → Ready
would move o/r#7: Ready → Merged
would move o/r#8: Building → Merged'
ck "dry-run prints exactly the moves each state implies" '[ "$(cat "$SB/dry")" = "$want" ] || { diff <(echo "$want") "$SB/dry" | sed "s/^/      /"; false; }'
ck "dry-run changes nothing" 'cmp -s "$FIX" "$SB/project.orig.json" && ! grep -q item-edit "$FIX.log"'
ck "human column kept: open issue in Spec review, closed-not-planned, draft issue" '! grep -qE "#(2|9|11):" "$SB/dry"'

"$H/factory.sh" apply >"$SB/apply" 2>&1
ck "apply moves the same cards via gh project item-edit" '[ "$(sed "s/^moved/would move/" "$SB/apply")" = "$want" ] && [ "$(grep -c "project item-edit" "$FIX.log")" = 7 ] && grep -qF -- "--id P5 --project-id PVT_1 --field-id F_status --single-select-option-id opt-Rework" "$FIX.log"'
ck "idempotent: a second run moves nothing" '[ "$("$H/factory.sh" dry-run)" = "no moves" ] && [ "$("$H/factory.sh" apply)" = "no moves" ]'

cp "$SB/project.orig.json" "$FIX"
"$H/factory.sh" json >"$SB/f.json" 2>"$SB/f.err"
ck "json: columns in project order, cards in their implied column" 'jq -e "[.columns[] | {(.name): [.cards[].ref]}] | add == {Triage: [\"o/r#1\",\"o/r#9\",\"o/r#11\"], \"Spec review\": [\"o/r#2\"], Building: [\"o/r#4\"], Rework: [\"o/r#5\"], Ready: [\"o/r#6\"], Merged: [\"o/r#7\",\"o/r#8\"], Blocked: [\"o/r#3\"]}" "$SB/f.json" >/dev/null'
ck "json: cycle time, rework rate, escaped bugs, risk misses" 'jq -e ".cycle == {merged: 1, intake_h: 24, build_h: 12} and .rework == {prs: 4, reworked: 2} and .escaped.bugs == 1 and .escaped.refs[0].ref == \"o/r#9\" and .risk == {scored: 1, misses: 1}" "$SB/f.json" >/dev/null'
ck "a gh failure is an error, not an empty board" 'GH_FAIL=1 "$H/factory.sh" json >/dev/null 2>&1; [ $? != 0 ]'

# collect.sh: factory key only when configured; render: the panel and Blocked in Needs you
git init -q "$SB/repo" && git -C "$SB/repo" commit -q --allow-empty -m init
(cd "$SB/repo" && "$H/collect.sh" --no-cost --no-attention "$SB/repo") >"$SB/on.json" 2>/dev/null
ck "collect: configured project → board.factory" 'jq -e ".factory.url == \"https://github.com/users/o/projects/3\" and (.factory.columns | length) == 7" "$SB/on.json" >/dev/null'
(cd "$SB/repo" && "$H/collect.sh" --no-cost --no-attention --no-prs "$SB/repo") >"$SB/np.json" 2>/dev/null
ck "collect --no-prs: factory says not collected" 'jq -e ".factory.error | test(\"no-prs\")" "$SB/np.json" >/dev/null'
printf -- '---\nrigor: lean\n---\n' >"$SB/home/profile.md"
(cd "$SB/repo" && "$H/collect.sh" --no-cost --no-attention "$SB/repo") >"$SB/off.json" 2>/dev/null
ck "collect: no factory config → no factory key, gh not called for it" 'jq -e "has(\"factory\") | not" "$SB/off.json" >/dev/null && [ "$(grep -c graphql "$FIX.log")" = 7 ]'

command -v node >/dev/null || { echo "  ~ node missing: factory render checks skipped"; [ $fail = 0 ] && echo PASS; exit $fail; }
cat >"$SB/run.js" <<'JS'
const fs = require('fs'), html = fs.readFileSync(process.argv[2], 'utf8');
const data = html.match(/<script id="board-data"[^>]*>([\s\S]*?)<\/script>/)[1].replace(/<\\\//g, '</');
const code = html.slice(html.lastIndexOf('<script>') + 8, html.lastIndexOf('</script>'));
const mk = () => new Proxy({innerHTML: '', textContent: '', hidden: false, dataset: {}, style: {setProperty() {}}},
  {get: (o, k) => k in o ? o[k] : k === 'querySelectorAll' ? () => [] : () => mk(), set: (o, k, v) => (o[k] = v, true)});
const els = {'board-data': {textContent: data}}, g = id => els[id] || (els[id] = mk());
new Function('document', code)({getElementById: g, querySelectorAll: () => [], createElementNS: () => mk(), documentElement: mk()});
console.log(JSON.stringify({needs: g('needs').innerHTML, views: g('views').innerHTML}));
JS
"$H/render.sh" "$SB/on.json" "$SB/on.html" >/dev/null && node "$SB/run.js" "$SB/on.html" >"$SB/on.out" 2>"$SB/on.err" || { echo "  ✗ factory board failed to render: $(head -3 "$SB/on.err")"; fail=1; }
ck "panel: columns with counts, metrics, card links" 'grep -qF "data-p=\\\"factory\\\"" "$SB/on.out" && grep -qF "Spec review" "$SB/on.out" && grep -qF "2 of 4" "$SB/on.out" && grep -qF "https://github.com/o/r/pull/6" "$SB/on.out" && grep -qF "1 of 1" "$SB/on.out"'
ck "Needs you lists the Blocked card" 'node -e "const o=JSON.parse(require(\"fs\").readFileSync(process.argv[1]));process.exit(/o\/r#3/.test(o.needs)?0:1)" "$SB/on.out"'
"$H/render.sh" "$SB/off.json" "$SB/off.html" >/dev/null && node "$SB/run.js" "$SB/off.html" >"$SB/off.out"
ck "no factory config: no factory markup" '! grep -qiF "factory" "$SB/off.out"'
[ $fail = 0 ] && echo PASS || exit 1
