#!/usr/bin/env bash
# render.test.sh: render.sh fills the template even when the board data contains the placeholder text,
# and the page script renders the attention tile, task sessions and warnings (run under a stub DOM in node).
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
SB="$(mktemp -d "${TMPDIR:-/tmp}/render.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
fail=0; ck() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }
printf '{"repos":[{"name":"fill {{BOARD_JSON}} placeholder </script>"}]}\n' >"$SB/b.json"
want='<script id="board-data" type="application/json">{"repos":[{"name":"fill {{BOARD_JSON}} placeholder <\/script>"}]}</script>'
ck "data containing {{BOARD_JSON}} renders verbatim, </ escaped" '"$H/render.sh" "$SB/b.json" "$SB/out.html" >/dev/null 2>&1 && grep -qF "$want" "$SB/out.html"'

command -v node >/dev/null || { echo "  ~ node missing: attention render checks skipped"; [ $fail = 0 ] && echo PASS; exit $fail; }
cat >"$SB/run.js" <<'JS'
const fs = require('fs'), html = fs.readFileSync(process.argv[2], 'utf8');
const data = html.match(/<script id="board-data"[^>]*>([\s\S]*?)<\/script>/)[1].replace(/<\\\//g, '</');
const code = html.slice(html.lastIndexOf('<script>') + 8, html.lastIndexOf('</script>'));
const mk = () => new Proxy({innerHTML: '', textContent: '', hidden: false, dataset: {}, style: {setProperty() {}}},
  {get: (o, k) => k in o ? o[k] : k === 'querySelectorAll' ? () => [] : () => mk(), set: (o, k, v) => (o[k] = v, true)});
const els = {'board-data': {textContent: data}}, g = id => els[id] || (els[id] = mk());
let rects = 0;
new Function('document', code)({getElementById: g, querySelectorAll: () => [], createElementNS: (ns, n) => (n === 'rect' && rects++, mk()), documentElement: mk()});
console.log(JSON.stringify({tile: g('attention-tile').innerHTML, needs: g('needs').innerHTML, views: g('views').innerHTML, rects}));
JS
cat >"$SB/new.json" <<'JSON'
{"generated":"2026-05-01T10:00:00Z","repos":[{"name":"r","path":"/r","current":true,"tasks":[{"slug":"t","goal":"G","slices":[],"sessions":[
 {"sid":"abcdef1234567890","title":"Fix <b>x</b>","first":"2026-05-01T08:00:00Z","last":"2026-05-01T09:00:00Z","calls":12,"min":31.5,"blocked_min":4.2},
 {"sid":"99887766aabb","title":"","first":"2026-05-01T07:00:00Z","last":"2026-05-01T07:30:00Z","calls":3,"min":0,"blocked_min":0}]}]}],
 "attention":{"cap_secs":300,"days":14,"budget_min":120,"today":{"date":"2026-05-01"},"by_day":[
 {"date":"2026-04-30","min":50,"blocked_min":1,"prompts":3,"answers":1,"questions":0,"permissions":0},
 {"date":"2026-05-01","min":130.5,"blocked_min":12.5,"prompts":9,"answers":4,"questions":2,"permissions":3}],
 "warnings":[{"level":"crit","text":"🔴 over budget: <i>Fix</i>","sids":["a"]},{"level":"warn","text":"🟡 3 sessions at once","sids":[]}]}}
JSON
printf '{"generated":"2026-05-01T10:00:00Z","repos":[{"name":"r","path":"/r","tasks":[{"slug":"t","goal":"G","slices":[]}]}]}\n' >"$SB/old.json"
# --no-attention: sessions without min / blocked_min, attention null
printf '{"generated":"2026-05-01T10:00:00Z","attention":null,"repos":[{"name":"r","path":"/r","tasks":[{"slug":"t","goal":"G","slices":[],"sessions":[{"sid":"s1","title":"A","first":"2026-05-01T08:00:00Z","last":"2026-05-01T09:00:00Z","calls":2},{"sid":"s2","title":"B","first":"2026-05-01T08:00:00Z","last":"2026-05-01T09:00:00Z","calls":1}]}]}]}\n' >"$SB/na.json"
for v in new old na; do
  "$H/render.sh" "$SB/$v.json" "$SB/$v.html" >/dev/null && node "$SB/run.js" "$SB/$v.html" >"$SB/$v.out" 2>"$SB/$v.err" || { echo "  ✗ $v fixture failed to render or run: $(head -3 "$SB/$v.err")"; fail=1; }
done
ck "tile shows today's minutes, budget, blocked minutes, counts" 'grep -qF "<div class=\\\"big\\\">130.5<small> min of 120" "$SB/new.out" && grep -qF "12.5 min" "$SB/new.out" && grep -q "permissions" "$SB/new.out"'
ck "one bar per day" 'node -e "process.exit(JSON.parse(require(\"fs\").readFileSync(process.argv[1])).rects===2?0:1)" "$SB/new.out"'
ck "no attention: sessions listed, no minutes shown" 'grep -qF "2 sessions" "$SB/na.out" && ! grep -qF "min of you" "$SB/na.out" && ! grep -qF "<th class=\\\"num\\\">Min" "$SB/na.out" && grep -qF "not collected" "$SB/na.out"'
ck "warning text in tile and Needs you, escaped, crit pill" 'grep -qF "🔴 over budget" "$SB/new.out" && grep -qF "🟡 3 sessions" "$SB/new.out" && ! grep -qF "<i>Fix" "$SB/new.out" && grep -q "p-crit" "$SB/new.out"'
ck "task card lists sessions, sid8 when untitled" 'grep -qF "2 sessions" "$SB/new.out" && grep -qF "99887766" "$SB/new.out" && ! grep -qF "<b>x" "$SB/new.out"'
ck "old board: no attention markup, no sessions, no JS error" '[ -s "$SB/old.out" ] && ! grep -qF "sessions" "$SB/old.out" && node -e "const o=JSON.parse(require(\"fs\").readFileSync(process.argv[1]));process.exit(o.tile===\"\"&&!/attention/.test(o.needs)?0:1)" "$SB/old.out"'
[ $fail = 0 ] && echo PASS || exit 1
