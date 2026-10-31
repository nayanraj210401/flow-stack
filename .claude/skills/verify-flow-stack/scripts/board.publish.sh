#!/usr/bin/env bash
# board.publish: collect.sh turns a repo's .flow/ state into board JSON with the real values,
# and render.sh embeds it in the page safely. Publishing (the Artifact tool) is model-only.
. "$(dirname "$0")/lib.sh"; sandbox board.publish
B="$S/board/scripts"
toy_features >/dev/null 2>&1
toy_task mul "Users can multiply </script><b>x</b> integers" "no division"
printf '# Slices · mul\n\n## S1 · add mul\nstatus: done\ncheck: true\n\n## S2 · docs\nstatus: doing\ncheck: true\n\n## S3 · edge cases\nstatus: todo\ncheck: true\n' >.flow/tasks/mul/SLICES.md
printf 'GATE · fail open or closed on overflow?\n' >.flow/tasks/mul/GATES.md
"$S/flow/scripts/task.sh" decide agent yes "chose shell arithmetic" "no deps" >/dev/null
"$S/flow/scripts/task.sh" decide human no "approved intent" "" >/dev/null
cp "$PLUGIN/templates/debt.md" .flow/debt.md
printf -- '- [ ] D1 · 2026-09-28 · no overflow check · where: src/calc.sh:1 · repay when: first bug report\n- [x] D2 · 2026-09-28 · old shortcut · repaid\n' >>.flow/debt.md
"$S/feature-map/scripts/features.sh" mark export.csv stale >/dev/null
# quality inputs with known scores: 6 sources (one 1000 lines, 3 TODOs) + 2 tests, 1011 code lines
for n in 1 2 3; do printf 'u%s() { :; }\n' "$n" >src/util$n.sh; done
awk 'BEGIN{for(i=1;i<=1000;i++) print (i<=3 ? "# TODO " i : ": " i)}' >src/big.sh
git add src tests && git commit -qm "more code"
ev() { printf '### 2026-09-28T0%s:00:00Z · %s · %s · exit=0\n- cmd: `true`\n\n' "$1" "$2" "$3" >>.flow/tasks/mul/EVIDENCE.md; }
ev 1 S1:before FAIL; ev 2 S1 FAIL; ev 3 S1 PASS; ev 4 S2 FAIL; ev 5 probe:S1 TEETH; ev 6 probe:S2 TOOTHLESS
printf '2026-09-28T00:00:00Z\tdeadbeef\tready\tpass\tx\n' >.flow/ready.tsv

J="$SB/board.json"
check "collect.sh exits 0" bash -c "'$B/collect.sh' --no-cost --no-prs '$PWD' >'$J'"
cp "$J" "$ART/" 2>/dev/null || true
q() { jq -r "$1" "$J" 2>/dev/null || true; }
[ "$(q '.repos | length')" = 1 ] && ok "one repo" || bad "repos: $(q '.repos | length')"
[ "$(q '.repos[0].current')" = true ] && ok "current repo flagged" || bad "current not flagged"
[ "$(q '.repos[0].tasks[0].slices | map(.status) | join(",")')" = "done,doing,todo" ] && ok "slices in order with status" || bad "slices: $(q '.repos[0].tasks[0].slices')"
[ "$(q '.repos[0].tasks[0].gates[0]')" = "fail open or closed on overflow?" ] && ok "gate text" || bad "gate: $(q '.repos[0].tasks[0].gates')"
[ "$(q '.repos[0].tasks[0].active')" = true ] && ok "active task" || bad "active flag"
[ "$(q '[.repos[0].features[] | .id + ":" + .status] | sort | join(" ")')" = "calc.add:unverified export.csv:stale" ] && ok "features with status" || bad "features: $(q '.repos[0].features')"
[ "$(q '.repos[0].decisions | map(.decision) | join("|")')" = "chose shell arithmetic" ] && ok "agent decisions only" || bad "decisions: $(q '.repos[0].decisions')"
[ "$(q '[.repos[0].debt[] | .id + ":" + (.open|tostring)] | join(" ")')" = "D1:true D2:false" ] && ok "debt open/closed" || bad "debt: $(q '.repos[0].debt')"
[ "$(q '.repos[0].debt[0].trigger')" = "first bug report" ] && ok "debt trigger" || bad "trigger: $(q '.repos[0].debt[0].trigger')"
[ "$(q '.repos[0].shipped | length')" -ge 1 ] && ok "shipped commits" || bad "no commits"
dims="$(q '[.repos[0].quality.dims[] | .id + "=" + (.score|tostring)] | join(" ")')"
[ "$dims" = "features=0 checks=50 teeth=50 debt=85 review=0 tests=67 size=83 markers=70" ] && ok "quality dimension scores" || bad "quality dims: $dims"
[ "$(q '.repos[0].quality.score')" = 51 ] && ok "quality overall = mean of dims" || bad "quality score: $(q '.repos[0].quality.score')"
[ "$(q '.repos[0].quality.dims | map(select(.detail == "")) | length')" = 0 ] && ok "every dimension has a detail" || bad "empty detail: $(q '.repos[0].quality.dims')"
mkdir "$SB/bare" && (cd "$SB/bare" && git init -q && printf 'x() { :; }\n' >a.sh && printf '. a.sh\n' >a_test.sh && git add -A && git -c user.email=e@x -c user.name=e commit -qm i)
bj="$("$B/collect.sh" --no-cost --no-prs "$SB/bare")"
nd="$(jq -r '[.repos[0].quality.dims[] | .id + "=" + (.score|tostring)] | join(" ")' <<<"$bj" || true)"
[ "$nd" = "features=null checks=null teeth=null debt=null review=null tests=100 size=100 markers=100" ] && ok "no .flow data → those dimensions null, not 0" || bad "bare dims: $nd"
[ "$(jq -r '.repos[0].quality.score' <<<"$bj")" = 100 ] && ok "overall skips null dims" || bad "bare overall: $(jq -c '.repos[0].quality.score' <<<"$bj")"
[ "$(q '.spend')" = null ] && [ "$(q '.repos[0].prs')" = null ] && ok "--no-cost / --no-prs honored" || bad "cost/prs collected"

H="$SB/board.html"
check "render.sh exits 0" "$B/render.sh" "$J" "$H"
grep -q '{{BOARD_JSON}}' "$H" && bad "placeholder left" || ok "placeholder filled"
[ "$(grep -o '</script>' "$H" | wc -l | tr -d ' ')" = "$(grep -o '</script>' "$PLUGIN/skills/board/templates/board.html" | wc -l | tr -d ' ')" ] && ok "a '</script>' in the data can't close the tag" || bad "unescaped </script> from data"
perl -0ne 'print $1 if m{<script id="board-data" type="application/json">(.*?)</script>}s' "$H" | jq -e '.repos[0].tasks[0].goal | test("</script>")' >/dev/null && ok "embedded JSON parses back intact" || bad "embedded JSON broken"
raw="$(grep -oE '\$\{(r|t|p|f|d|c|x|s)\.[a-zA-Z_.]+\}' "$PLUGIN/skills/board/templates/board.html" | grep -vxE '\$\{(s\.length|t\.lanes|t\.estimate_usd)\}' | sort -u | tr '\n' ' ' || true)"
[ -z "$raw" ] && ok "template: every text field goes through esc()" || bad "template interpolates raw data into HTML: $raw"
T="$PLUGIN/skills/board/templates/board.html"
grep -q "panel('quality', 'c12', \`Quality" "$T" && grep -q 'r\.quality' "$T" && ok "template: Quality panel per repo" || bad "template has no Quality panel"
grep -q '<th>Quality</th>' "$T" && ok "template: Quality column in All repos" || bad "no Quality column in All repos"
[ "$(q '.prefs.hide == [] and .prefs.order == [] and .prefs.warnings == []')" = true ] && ok "no # Board section → empty prefs" || bad "default prefs: $(q '.prefs')"

# prefs: a # Board section in the profile, applied the same by every lead
cat >>"$FLOW_STACK_HOME/profile.md" <<'EOF'
# Board
<!-- - hide: tasks -->
- hide: spend, decisions
- order: quality, tasks, nope
- colour: red
- theme: neon
- theme: dark
- tab: all
- wide: debt, x
- accent: red;}
- accent: #C2410C
- view: Open tasks · [.repos[].tasks[] | {slug, goal}] · table
- view: Task count · [.repos[].tasks[]] | length · count
- view: Leak · $ENV.HOME · list
- view: Bad </script> · .[ · list
- view: Sneaky · include "x"; . · list
- view: Dbg · 1 | debug · count
- view: Spin · repeat(1) · list
- view: Hash · [.repos[].tasks[].slug | "# \(.)"] · list
- view: Cmt · [.repos[].tasks[].slug] · list   # trailing comment
- view: Fail · "" | halt_error(1) · list
-   Theme: dark
# Taste
- hide: debt
EOF
check "collect.sh with # Board exits 0" bash -c "'$B/collect.sh' --no-cost --no-prs '$PWD' >'$J'"
[ "$(q '.prefs.hide | join(",")')" = "spend,decisions" ] && ok "prefs: hide (comments and other sections ignored)" || bad "hide: $(q '.prefs.hide')"
[ "$(q '.prefs.order | join(",")')" = "quality,tasks" ] && ok "prefs: order keeps known panels" || bad "order: $(q '.prefs.order')"
[ "$(q '.prefs.warnings | join("|")')" = "order: unknown panel nope|unknown key: colour|theme: neon is not auto, light, or dark|wide: unknown panel x|accent: red;} is not #rrggbb|view: Sneaky uses import/include|unknown key: Theme" ] && ok "prefs: unknown panel and key → warnings" || bad "warnings: $(q '.prefs.warnings')"
[ "$(q '.prefs | [.theme, .tab, (.wide | join(",")), .accent] | join(" ")')" = "dark all debt #C2410C" ] && ok "prefs: theme, tab, wide, accent (last valid value wins)" || bad "look prefs: $(q .prefs)"
[ "$(q '[.prefs.views[] | .title + ":" + .kind] | join("|")')" = "Open tasks:table|Task count:count|Leak:list|Bad </script>:list|Dbg:count|Spin:list|Hash:list|Cmt:list|Fail:list" ] && ok "prefs: views parsed (title, kind)" || bad "views: $(q '.prefs.views')"
[ "$(q '.prefs.views[0].rows[0].slug + " " + (.prefs.views[1].rows | tojson)')" = "mul [1]" ] && ok "view: jq rows over board.json" || bad "view rows: $(q '.prefs.views[:2]')"
[ "$(q '.prefs.views[2].rows | tojson')" = "[null]" ] && ok "view: can't read the environment" || bad "view leaked env: $(q '.prefs.views[2]')"
[ "$(q '[.prefs.views[4:][] | .title + "=" + (.rows | tojson)] | join(" ")')" = "Dbg=[1] Spin=[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1] Hash=[\"# mul\"] Cmt=[\"mul\"] Fail=null" ] && ok "view: stderr, endless streams, and '# ' inside a view are safe" || bad "views 4+: $(q '.prefs.views[4:]')"
[ "$(q '.prefs.views[-1].error')" != "timed out after 5 s" ] && ok "view: a failure without stderr isn't called a timeout" || bad "Fail view: $(q '.prefs.views[-1]')"
[ "$(q '.prefs.views[3] | has("error") and (has("rows") | not)')" = true ] && ok "view: bad jq → error, collect still exits 0" || bad "bad view: $(q '.prefs.views[3]')"
mkdir -p "$SB/other" && (cd "$SB/other" && git init -q)
lp="$(cd "$SB/other" && "$B/collect.sh" --no-cost --no-prs "$SB/repo" | jq -c .prefs)"
[ "$lp" = "$(q '.prefs | tojson')" ] && ok "prefs: another lead (other cwd) gets the same prefs" || bad "lead prefs differ: $lp"
sed -i.bak "s/^- tab: all/- tab: nowhere/" "$FLOW_STACK_HOME/profile.md"
tp="$("$B/collect.sh" --no-cost --no-prs "$PWD" | jq -c '[.prefs.tab, .prefs.warnings[-1]]')"
[ "$tp" = '[null,"tab: no repo named nowhere"]' ] && ok "prefs: unknown tab → warning, not applied" || bad "tab: $tp"
check "render.sh with prefs exits 0" "$B/render.sh" "$J" "$H"
grep -q "panel('tasks'" "$T" && grep -q 'data-p="${id}"' "$T" && grep -q 'D.prefs' "$T" && ok "template: panels tagged and prefs applied" || bad "template ignores prefs"
miss=""; for k in theme tab wide accent warnings views; do grep -q "P\.$k" "$T" || miss="$miss $k"; done
[ -z "$miss" ] && ok "template reads every pref" || bad "template ignores prefs:$miss"

# a task pointed at by a linked worktree is active too, and the board says where
toy_task beta "Beta tests exist" "no docs"
echo mul >.flow/ACTIVE
git worktree add -q "$SB/wt" -b lead/beta
WG="$(git -C "$SB/wt" rev-parse --absolute-git-dir)"; echo beta >"$WG/flow-active"
wj="$("$B/collect.sh" --no-cost --no-prs "$PWD")"
wq() { jq -r "$1" <<<"$wj" 2>/dev/null || true; }
[ "$(wq '[.repos[0].tasks[] | select(.active) | .slug] | sort | join(",")')" = "beta,mul" ] && ok "board: main's task and a worktree lead's task are both active" || bad "active tasks: $(wq '[.repos[0].tasks[] | .slug + ":" + (.active|tostring)] | join(" ")')"
[ "$(wq '.repos[0].tasks[] | select(.slug == "beta") | .owner')" = "$SB/wt" ] && ok "board: worktree lead's task names its worktree as owner" || bad "beta owner: $(wq '.repos[0].tasks[] | select(.slug == "beta") | .owner')"
[ "$(wq '.repos[0].tasks[] | select(.slug == "mul") | .owner')" = "$PWD" ] && ok "board: main's task owner is the main checkout" || bad "mul owner: $(wq '.repos[0].tasks[] | select(.slug == "mul") | .owner')"
printf '%s' "$wj" >"$ART/worktree-board.json"; "$B/render.sh" "$ART/worktree-board.json" "$ART/worktree-board.html" >/dev/null
grep -q 't\.owner === r\.path' "$B/../templates/board.html" && grep -q 'led from worktree' "$B/../templates/board.html" && ok "template shows each active task's owner" || bad "template ignores tasks[].owner"

fails "render.sh rejects non-board JSON" bash -c "echo '{}' >'$SB/x.json'; '$B/render.sh' '$SB/x.json' '$SB/x.html'"
finish
