#!/usr/bin/env bash
# flow.pane: the /flow-pane data and actions. status.sh --full lists the slices (each with its
# last verdict), the open gates in GATES.md, and the repo's other tasks; task.sh gate <n> approve|reject
# marks a gate decided and logs it, so the pane drops it.
. "$(dirname "$0")/lib.sh"; sandbox flow.pane
ST="$S/flow/scripts/status.sh"; T="$S/flow/scripts/task.sh"; EV="$S/verify/scripts/evidence.sh"
full() { "$ST" --full "$PWD" | jq -r "$1"; }

toy_task mul "Users can multiply two integers" "no division"
toy_slice mul S1 doing "bash tests/test_mul.sh" "src/**"
printf '\n## S2 · docs\nstatus: done\ncheck: true\nfence: README.md\n' >>.flow/tasks/mul/SLICES.md
toy_mul_check
git add -A && git commit -qm task
"$EV" S1 >/dev/null 2>&1 || true
G=.flow/tasks/mul/GATES.md
cat >"$G" <<'EOF'
# Gates

GATE · push branch mul and open a draft PR
  options: A) push  B) hold   (recommend: A, because it is reviewed)
  evidence: ready.sh stamped

GATE · drop the negatives slice?
  options: A) drop  B) keep
  decided: human approve 2026-10-07T10:00:00Z

GATE · merge PR #3
  A) merge (recommended: reviewed)   B) wait
EOF
printf '%s\n' "$(sed 's/merge PR #3/merge PR #3\x1b[2J/' "$G")" >"$G"

echo "-- slices"
[ "$(full '[.slices[] | .id + ":" + .status + ":" + .verdict] | join(",")')" = "S1:doing:FAIL,S2:done:" ] && ok "slices with status and last verdict" || bad "slices: $(full .slices)"
[ "$(full '.slices[0].title')" = mul ] && ok "slice title" || bad "title: $(full '.slices[0].title')"

echo "-- gates"
[ "$(full '[.gates[] | .n] | join(",")' 2>/dev/null)" = "1,3" ] && ok "open gates 1 and 3; decided gate 2 hidden" || bad "gates: $(full .gates)"
[ "$(full '.gates[0].question')" = "push branch mul and open a draft PR" ] && ok "gate question" || bad "q: $(full '.gates[0].question')"
has "$(full '.gates[0].detail')" "recommend: A" && ok "gate detail keeps options" || bad "detail: $(full '.gates[0].detail')"
grep -q "$(printf '\033')" <<<"$(full '.gates[1].question')" && bad "ESC reached a gate question" || ok "gate text has no control characters"

echo "-- deciding a gate"
has "$(full '.gates[1].detail')" "A) merge" && ok "option lines without a key are kept" || bad "detail: $(full '.gates[1].detail')"
fails "a question that doesn't match gate n is refused" "$T" gate 1 approve "merge PR #3"
ln -s "$SB/victim" "$G.tmp"; echo keep >"$SB/victim"
sees "approve gate 1" "gate 1 approved" "$T" gate 1 approve "push branch mul and open a draft PR"
[ "$(cat "$SB/victim")" = keep ] && [ ! -L "$G" ] && ok "a planted GATES.md.tmp symlink is not followed" || bad "victim: $(cat "$SB/victim"); GATES.md symlink: $([ -L "$G" ] && echo yes)"
grep -A3 'GATE · push branch mul' "$G" | grep -q '^  decided: human approve 20' && ok "GATES.md: decided line under gate 1" || bad "GATES.md: $(cat "$G")"
tail -n1 .flow/tasks/mul/DECISIONS.tsv | grep -q $'\thuman\tapprove: push branch mul and open a draft PR\t' && ok "DECISIONS.tsv row" || bad "decisions: $(tail -n1 .flow/tasks/mul/DECISIONS.tsv)"
[ "$(full '[.gates[] | .n] | join(",")')" = "3" ] && ok "approved gate leaves the list" || bad "after approve: $(full .gates)"
q3="$(full '.gates[0].question')"
sees "reject gate 3" "gate 3 rejected" "$T" gate 3 reject "$q3"
fails "a decided gate can't be decided again" "$T" gate 1 reject "push branch mul and open a draft PR"
printf '\nGATE · a\302\233b\n  options: A) x\n' >>"$G"; chmod 644 "$G"
q4="$(full '.gates[-1].question')"
sees "a gate with a C1 control code is decidable from the pane's text" "gate 4 approved" "$T" gate 4 approve "$q4"
[ "$(stat -f %Lp "$G" 2>/dev/null || stat -c %a "$G")" = 644 ] && ok "GATES.md keeps mode 644" || bad "mode: $(ls -l "$G")"
fails "no gate 9" "$T" gate 9 approve
fails "only approve or reject" "$T" gate 3 maybe
[ "$(full '.gates | length')" = 0 ] && ok "no open gates" || bad "gates left: $(full .gates)"

echo "-- the board drops decided gates"
"$S/board/scripts/collect.sh" >"$SB/board.json" 2>/dev/null || true
[ "$(jq -r '[.. | objects | select(has("gates")) | .gates[]] | length' "$SB/board.json" 2>/dev/null)" = 0 ] && ok "board: no open gates left" || bad "board gates: $(jq -c '[.. | objects | select(has("gates")) | .gates] ' "$SB/board.json" 2>/dev/null | head -c 300)"

echo "-- Claude can't decide a gate for the human"
expect guard.sh "$(bashcmd "$T gate 1 approve x")" deny "Bash: task.sh gate"

echo "-- the repo's other tasks, with their owners"
git worktree add -q "$SB/wl" -b feat/login
( cd "$SB/wl" && "$T" new login >/dev/null )
[ "$(full '[.tasks[] | .task + "|" + .where + "|" + (.live | tostring)] | join(",")')" = "login|wl|false" ] && ok "other task listed, not ours" || bad "tasks: $(full .tasks)"

echo "-- the band's short form is unchanged"
[ "$("$ST" "$PWD" | jq 'has("slices") or has("gates") or has("tasks")')" = false ] && ok "status.sh without --full stays small" || bad "short form grew"
finish
