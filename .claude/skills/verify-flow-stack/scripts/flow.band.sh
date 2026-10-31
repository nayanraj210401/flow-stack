#!/usr/bin/env bash
# flow.band: status.sh (the flow band's data) reads a real task the way the band shows it:
# nothing without a task; the doing slice, progress, and the last evidence header (not a
# "### " line inside its output); stale after an edit; the TDD slice and phase; a lane's own state.
. "$(dirname "$0")/lib.sh"; sandbox flow.band
ST="$S/flow/scripts/status.sh"; T="$S/flow/scripts/task.sh"; EV="$S/verify/scripts/evidence.sh"
field() { "$ST" "${2:-$PWD}" | jq -r "$1"; }

echo "-- no task"
[ "$("$ST" "$PWD")" = '{}' ] && ok "no active task → {}" || bad "no task: $("$ST" "$PWD")"

echo "-- slice, progress, evidence"
toy_task mul "Users can multiply two integers" "no division"
toy_slice mul S1 doing "bash tests/test_mul.sh" "src/**"
printf '\n## S2 · mul · negatives\nstatus: todo\ncheck: true\nfence: src/**\n' >>.flow/tasks/mul/SLICES.md
git add -A && git commit -qm task
[ "$(field .task)" = mul ] && ok "task" || bad "task: $(field .task)"
[ "$(field '.slice.id + "|" + .slice.title')" = "S1|mul" ] && ok "doing slice S1" || bad "slice: $(field .slice)"
[ "$(field '"\(.done)/\(.total)"')" = 0/2 ] && ok "0/2 slices" || bad "progress: $(field '"\(.done)/\(.total)"')"
"$EV" smoke "echo '### Heading from test output'; exit 1" >/dev/null 2>&1 || true
[ "$(field '.evidence.label + " " + .evidence.verdict')" = "smoke FAIL" ] && ok "last evidence header, not output's ### line" || bad "evidence: $(field .evidence)"
[[ "$(field .evidence.ts)" =~ ^20[0-9-]+T ]] && ok "evidence ts is ISO" || bad "ts: $(field .evidence.ts)"
[ "$(field .stale)" = false ] && ok "fresh before any edit" || bad "stale before edit"

echo "-- stale after an edit"
sleep 1
hook post-tool.sh "$(jq -nc --arg cwd "$PWD" --arg f "$PWD/src/calc.sh" '{cwd:$cwd,hook_event_name:"PostToolUse",tool_name:"Edit",tool_input:{file_path:$f},tool_response:{}}')"
[ "$(field .stale)" = true ] && ok "edit after evidence → stale" || bad "not stale after edit"

echo "-- TDD lock names the slice"
"$T" tdd S2 red >/dev/null 2>&1 || "$T" tdd S2 red --force "scenario" >/dev/null 2>&1 || true
[ "$(field '.slice.id + " " + .tdd')" = "S2 red" ] && ok "tdd slice S2 · red (title with ·: $(field .slice.title))" || bad "tdd: $(field '.slice.id + " " + .tdd')"
[ "$(field .slice.title)" = "mul · negatives" ] && ok "title keeps its ·" || bad "title: $(field .slice.title)"
"$T" tdd off "scenario" >/dev/null 2>&1 || rm -f .flow/tasks/mul/TDD

echo "-- control characters from repo files never reach the terminal"
sed -i '' "s/^## S1 · mul\$/## S1 · mul$(printf '\033]52;c;aGk=\007')x/" .flow/tasks/mul/SLICES.md
out="$("$ST" "$PWD")"
grep -q "$(printf '\033')" <<<"$(jq -r '.slice.title' <<<"$out")" && bad "ESC reached the slice title" || ok "ESC stripped from the slice title"
[ "$(jq -r .slice.title <<<"$out")" = "mul]52;c;aGk=x" ] && ok "printable text kept" || bad "title: $(jq -r .slice.title <<<"$out" | od -c | head -2)"
echo "-- a lane shows its own evidence"
git worktree add -q "$SB/wt" -b worker/s1
slug="$(head -n1 .flow/ACTIVE)"; ( cd "$SB/wt" && "$S/flow/scripts/task.sh" join "$slug" >/dev/null )
( cd "$SB/wt" && "$EV" lane "echo ok" >/dev/null 2>&1 )
[ "$(field '.evidence.label + " " + .evidence.verdict' "$SB/wt")" = "lane PASS" ] && ok "lane: its own evidence" || bad "lane evidence: $(field .evidence "$SB/wt")"
[ "$(field '.evidence.label' "$PWD")" = "smoke" ] && ok "main: unchanged by the lane" || bad "main evidence: $(field .evidence)"
[ "$(field .where "$SB/wt")" = lane ] && [ "$(field .where "$PWD")" = main ] && ok "where: lane / main" || bad "where: $(field .where "$SB/wt") / $(field .where "$PWD")"
echo "-- two lead worktrees: each its own task, gate buttons decide only that task's gates"
toy_task alpha "Alpha docs exist" "no code"; toy_task beta "Beta tests exist" "no docs"
for t in alpha beta; do printf 'GATE · ship %s?\n  detail\n' $t >.flow/tasks/$t/GATES.md; done
git worktree add -q "$SB/wa" -b lead/a; git worktree add -q "$SB/wb" -b lead/b
for w in a:alpha b:beta; do echo "${w#*:}" >"$(git -C "$SB/w${w%:*}" rev-parse --absolute-git-dir)/flow-active"; done
for w in a:alpha b:beta; do
  [ "$(field '.task + " " + .where' "$SB/w${w%:*}")" = "${w#*:} lead" ] && ok "w${w%:*}: ${w#*:} lead" || bad "w${w%:*}: $(field '.task + " " + .where' "$SB/w${w%:*}")"
done
( cd "$SB/wa" && "$T" gate 1 approve "ship alpha?" >/dev/null 2>&1 )
grep -q 'decided: human approve' .flow/tasks/alpha/GATES.md && ! grep -q decided .flow/tasks/beta/GATES.md && ok "gate in wa decided alpha only" || bad "gate: alpha=$(grep -c decided .flow/tasks/alpha/GATES.md) beta=$(grep -c decided .flow/tasks/beta/GATES.md)"
grep -q 'approve: ship alpha' .flow/tasks/alpha/DECISIONS.tsv && ! grep -q 'ship alpha' .flow/tasks/beta/DECISIONS.tsv && ok "decision logged to alpha only" || bad "DECISIONS.tsv"
finish
