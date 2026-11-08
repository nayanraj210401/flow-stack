#!/usr/bin/env bash
# task.lifecycle: task.sh creates, lists, switches, logs decisions/estimates for, and closes tasks.
. "$(dirname "$0")/lib.sh"; sandbox task.lifecycle
TASK="$S/flow/scripts/task.sh"

check "new demo (bug playbook)" "$TASK" new demo bug
for f in INTENT.md SLICES.md DECISIONS.tsv EVIDENCE.md PLAYBOOK; do
  [ -f ".flow/tasks/demo/$f" ] && ok "created $f" || bad "missing $f"
done
[ "$(cat .flow/tasks/demo/PLAYBOOK)" = bug ] && ok "PLAYBOOK=bug" || bad "PLAYBOOK=$(cat .flow/tasks/demo/PLAYBOOK)"
grep -q '{{slug}}' .flow/tasks/demo/INTENT.md && bad "template not filled" || ok "INTENT template filled"
[ "$("$TASK" active)" = demo ] && ok "demo is active" || bad "active=$("$TASK" active)"
grep -qxF '.flow/tasks/' .gitignore && ok ".gitignore gets .flow/tasks/" || bad ".gitignore not updated"
jq empty .flow/config.json && ok ".flow/config.json created" || bad "no config.json"
fails "new demo again (exists)" "$TASK" new demo
fails "new Bad_Slug (not kebab)" "$TASK" new Bad_Slug

check "new second with goal and check" "$TASK" new second --goal 'Users can divide; 1/0 says "no"' --check 'bash tests/test_div.sh && echo `ok`'
sed -n '/^## Goal/,/^## /p' .flow/tasks/second/INTENT.md | grep -qxF 'Users can divide; 1/0 says "no"' && ok "--goal written under ## Goal" || bad "goal: $(sed -n '/^## Goal/,/^## /p' .flow/tasks/second/INTENT.md)"
grep -qxF -- '- [ ] C1 · the goal holds · `bash tests/test_div.sh && echo `ok``' .flow/tasks/second/INTENT.md && ok "--check written as C1" || bad "C1: $(grep 'C1 ·' .flow/tasks/second/INTENT.md)"
[ "$(cat .flow/tasks/second/PLAYBOOK)" = feature ] && ok "flags aren't taken as the playbook" || bad "PLAYBOOK=$(cat .flow/tasks/second/PLAYBOOK)"
sees "list marks the active task" "* second" "$TASK" list
check "switch demo" "$TASK" switch demo
[ "$("$TASK" active)" = demo ] && ok "demo active after switch" || bad "active=$("$TASK" active)"
fails "switch to a missing task" "$TASK" switch nope

check "decide logs a row" "$TASK" decide human no "use sqlite" "fewer moving parts" "bench.txt"
grep -q $'\thuman\tuse sqlite\tfewer moving parts\tbench.txt\tno$' .flow/tasks/demo/DECISIONS.tsv && ok "DECISIONS.tsv row shape" || bad "row: $(tail -n1 .flow/tasks/demo/DECISIONS.tsv)"
check "estimate saved" "$TASK" estimate 1.5 30 10
grep -q 'usd=1.5 ctx_pct=30 human_min=10' .flow/tasks/demo/ESTIMATE && ok "ESTIMATE content" || bad "ESTIMATE: $(cat .flow/tasks/demo/ESTIMATE)"

check "close" "$TASK" close
[ -z "$("$TASK" active)" ] && ok "no active task" || bad "still active"
fails "dir with no active task" "$TASK" dir
[ -d .flow/tasks/demo ] && ok "folder kept after close" || bad "folder gone"
"$TASK" list >"$ART/list.txt" 2>&1
finish
