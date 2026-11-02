#!/usr/bin/env bash
# session.context: SessionStart primer (profile, repo entry, map/features, active task,
# handoff after compaction), the per-prompt anchor, and the PreCompact snapshot.
. "$(dirname "$0")/lib.sh"; sandbox session.context
ss() { jq -nc --arg cwd "$PWD" --arg s "${1:-startup}" '{cwd:$cwd, hook_event_name:"SessionStart", source:$s}'; }
up() { jq -nc --arg cwd "$PWD" '{cwd:$cwd, hook_event_name:"UserPromptSubmit", prompt:"next"}'; }

echo "-- bare repo, no profile"
hook session-start.sh "$(ss)"; echo "$OUT" >"$ART/session-start.bare.txt"
has "$OUT" "# flow-stack" && ok "primer" || bad "no primer"
has "$OUT" "No flow-stack profile yet" && ok "suggests setup" || bad "no setup hint"
has "$OUT" "## Active task" && bad "phantom active task" || ok "no task section without a task"

echo "-- profile + repo entry + map + features"
"$S/profile/scripts/init.sh" solo-hacker >/dev/null
printf '\n' >>"$FLOW_STACK_HOME/profile.md"
perl -0pi -e "s|## example-repo\n- path: ~/Project/example-repo|## toy\n- path: $PWD|" "$FLOW_STACK_HOME/profile.md"
mkdir -p .flow/features && echo '# Map' >.flow/map.md
toy_features >/dev/null 2>&1
hook session-start.sh "$(ss)"; echo "$OUT" >"$ART/session-start.full.txt"
has "$OUT" "## Profile ($FLOW_STACK_HOME/profile.md)" && ok "profile excerpt" || bad "no profile"
has "$OUT" "### Rules (hard constraints)" && ok "rules injected" || bad "no rules"
has "$OUT" "### This repo" && has "$OUT" "## toy" && ok "this repo's entry only" || bad "no repo entry"
has "$OUT" "Repo map: .flow/map.md" && ok "map pointer" || bad "no map pointer"
has "$OUT" "Feature map: .flow/features/ (2 features)" && ok "feature count" || bad "no feature line"

echo "-- router handoff in Toolchain"
perl -0pi -e 's/(# Toolchain\n(<!--.*?-->\n)?)/$1- router: pstack:poteto-mode · test\n/s' "$FLOW_STACK_HOME/profile.md"
hook session-start.sh "$(ss)"
has "$OUT" 'Workflow router: `pstack:poteto-mode`' && ok "router respected" || bad "router ignored"

echo "-- daily brief nudge"
has "$OUT" "No daily brief yet today" && bad "nudged with digest: off" || ok "digest off → no nudge"
perl -pi -e 's/^digest:\s*\w+/digest: page/' "$FLOW_STACK_HOME/profile.md"
hook session-start.sh "$(ss)"
has "$OUT" "No daily brief yet today (digest: page)" && ok "digest page → nudge" || bad "no nudge"
mkdir -p "$FLOW_STACK_HOME/digest" && date +%F >"$FLOW_STACK_HOME/digest/last"
hook session-start.sh "$(ss)"
has "$OUT" "No daily brief yet today" && bad "nudged after today's wrap" || ok "wrap ran today → quiet"

echo "-- active task, anchor, pre-compact, handoff on compact"
toy_task demo "Users can multiply two integers" "no division"
toy_slice demo S1 doing "bash tests/test_mul.sh" "src/calc.sh"
hook session-start.sh "$(ss)"
has "$OUT" "## Active task: demo" && has "$OUT" "Goal: Users can multiply two integers" && ok "task + goal" || bad "no task anchor"
has "$OUT" "Current slice: S1 · mul" && ok "current slice" || bad "no slice"
has "$OUT" "untouched" && bad "fresh task flagged stale" || ok "fresh task not flagged"
find .flow/tasks/demo -type f -exec touch -t 202001010000 {} +
hook session-start.sh "$(ss)"
has "$OUT" "untouched for more than 3 days" && has "$OUT" "task.sh close" && ok "stale task flagged, with the way out" || bad "stale task not flagged: $OUT"
echo '{}' >>.flow/tasks/demo/trail.jsonl
hook session-start.sh "$(ss)"
has "$OUT" "untouched for more than 3 days" && ok "trail writes don't make a task fresh" || bad "trail write reset staleness"
touch .flow/tasks/demo/INTENT.md
hook anchor.sh "$(up)"; echo "$OUT" >"$ART/anchor.txt"
has "$OUT" "[flow anchor · demo] goal: Users can multiply two integers" && ok "anchor goal" || bad "anchor: $OUT"
has "$OUT" "[flow anchor] not doing: no division" && ok "anchor non-goal" || bad "no non-goal"
hook pre-compact.sh "$(jq -nc --arg cwd "$PWD" '{cwd:$cwd, hook_event_name:"PreCompact"}')"
A=.flow/tasks/demo/HANDOFF.auto.md
[ -f "$A" ] && grep -q '^## Resume' "$A" && grep -q '^- doing · S1' "$A" && ok "HANDOFF.auto.md snapshot" || bad "no/partial auto handoff"
cp "$A" "$ART/" 2>/dev/null || true
hook session-start.sh "$(ss compact)"
has "$OUT" "### Handoff (HANDOFF.auto.md)" && ok "handoff re-injected after compact" || bad "no handoff on compact"
hook session-start.sh "$(ss startup)"
has "$OUT" "### Handoff" && bad "handoff injected on plain startup" || ok "no handoff on plain startup"

echo "-- toggles"
jq '.hooks["session-start"]=false | .hooks.anchor=false' .flow/config.json >c && mv c .flow/config.json
hook session-start.sh "$(ss)"; [ -z "$OUT" ] && ok "session-start off → silent" || bad "still printed"
hook anchor.sh "$(up)"; [ -z "$OUT" ] && ok "anchor off → silent" || bad "anchor printed"
finish
