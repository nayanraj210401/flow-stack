#!/usr/bin/env bash
# session.owner: a task belongs to the Claude session that started it. Its pointer records the
# owner's pid; while that session lives (Claude Code's sessions/<pid>.json row + the process), every
# other session in the checkout has no task: no anchor, Stop check, fence, band, or sidebar row.
# A dead owner's task is free again and the next session to work on it takes it.
. "$(dirname "$0")/lib.sh"; sandbox session.owner
T="$S/flow/scripts/task.sh"; ST="$S/flow/scripts/status.sh"
MAIN="$PWD"
reg="$CLAUDE_CONFIG_DIR/sessions"; mkdir -p "$reg"
# session <name>: a live fake Claude session (a sleeping process with a registry row); prints its pid
session() {
  sleep 600 >/dev/null 2>&1 & local p=$!
  # procStart as Claude Code writes it (UTC, English names), even under another locale here
  jq -nc --argjson p "$p" --arg n "$1" --arg c "$MAIN" --arg st "$(LC_ALL=C TZ=UTC ps -o lstart= -p "$p" | sed 's/ *$//')" \
    '{pid:$p, sessionId:("sid-" + $n), cwd:$c, name:$n, status:"idle", procStart:$st}' >"$reg/$p.json"
  echo "$p"
}
A="$(session pane-a)"; B="$(session pane-b)"
trap 'kill "$A" "$B" 2>/dev/null; rm -rf "$SB"' EXIT
as() { local p="$1"; shift; FLOW_SESSION_PID="$p" "$@"; }   # as <pid> <cmd...>: run as that session
asx() { export FLOW_SESSION_PID="$1"; }                       # for hook calls in this shell
ev() { jq -nc --arg e "$1" --arg c "$PWD" '{hook_event_name:$e, session_id:"x", cwd:$c, prompt:"go", source:"startup"}'; }

echo "-- S1: A starts a task; it is A's"
asx "$A"; toy_task demo "mul multiplies" "no division"
toy_slice demo S1 doing "bash tests/test_mul.sh" "src/**"
[ "$(sed -n 2p .flow/ACTIVE)" = "$A" ] && ok "the pointer records A as owner" || bad "ACTIVE: $(cat .flow/ACTIVE)"
[ "$(as "$A" "$T" active)" = demo ] && ok "A sees demo" || bad "A: '$(as "$A" "$T" active)'"
asx "$A"; hook anchor.sh "$(ev UserPromptSubmit)"
has "$OUT" "flow anchor · demo" && ok "A gets the anchor" || bad "A anchor: $OUT"

echo "-- S2: B in the same checkout has no task while A lives"
[ -z "$(as "$B" "$T" active)" ] && ok "B: no active task" || bad "B sees '$(as "$B" "$T" active)'"
asx "$B"; hook anchor.sh "$(ev UserPromptSubmit)"
[ -z "$OUT" ] && ok "B gets no anchor" || bad "B anchor: $OUT"
hook session-start.sh "$(ev SessionStart)"
has "$OUT" "demo" && has "$OUT" "pane-a" && ok "B is told demo belongs to pane-a" || bad "B start: $(tail -n3 <<<"$OUT")"
expect edit-guard.sh "$(edit "$MAIN/docs/x.md" Write)" allow "B: an edit outside demo's fence"
s="$(as "$B" "$ST")"
[ "$(jq -r '.task // ""' <<<"$s")" = "" ] && [ "$(jq -r '.foreign.task' <<<"$s")" = demo ] && [ "$(jq -r '.foreign.owner' <<<"$s")" = pane-a ] \
  && ok "B's band: no task, foreign demo owned by pane-a" || bad "B status: $s"
sees "B can't start a task here" "worktree" as "$B" "$T" new other
sees "B can't close A's task" "pane-a" as "$B" "$T" close
[ "$(head -n1 .flow/ACTIVE)" = demo ] && ok "A's pointer untouched" || bad "ACTIVE: $(cat .flow/ACTIVE)"
sees "B can't switch to it while A lives" "pane-a" as "$B" "$T" switch demo
check "B takes it over explicitly" as "$B" "$T" switch demo --take
[ "$(sed -n 2p .flow/ACTIVE)" = "$B" ] && ok "B owns demo now" || bad "ACTIVE: $(cat .flow/ACTIVE)"
check "A takes it back" as "$A" "$T" switch demo --take

[ -z "$(LANG=fr_FR.UTF-8 LC_ALL=fr_FR.UTF-8 FLOW_SESSION_PID="$B" "$T" active)" ] && ok "under a French locale, A still reads as live" || bad "locale broke liveness"

echo "-- S3: the human outside Claude sees every task"
[ "$(as "" "$T" active)" = demo ] && ok "no session: demo" || bad "human: '$(as "" "$T" active)'"

echo "-- S4: the pane lists tasks with their owners"
git worktree add -q "$SB/wb" -b feat-b
( cd "$SB/wb" && as "$B" "$T" new beta >/dev/null )
s="$(cd "$SB/wb" && as "$B" "$ST" --full)"
jq -e '.tasks | map(select(.task == "demo" and .owner == "pane-a" and .live == true)) | length == 1' <<<"$s" >/dev/null \
  && ok "B's pane shows demo · pane-a" || bad "B tasks: $(jq -c .tasks <<<"$s")"
jq -e '.tasks | map(select(.task == "beta")) | length == 0' <<<"$s" >/dev/null && ok "not its own task" || bad "own listed: $(jq -c .tasks <<<"$s")"
l="$(as "" "$T" list)"
has "$l" "pane-a" && has "$l" "pane-b" && ok "task.sh list names each owner" || bad "list: $l"

echo "-- S5: a dead owner frees the task; the next session to work on it takes it"
kill "$A"; wait "$A" 2>/dev/null || true
[ "$(as "$B" "$T" active)" = demo ] && ok "B sees demo once A is gone" || bad "B: '$(as "$B" "$T" active)'"
as "$B" "$T" decide agent yes "carry on" "A exited" >/dev/null
[ "$(sed -n 2p .flow/ACTIVE)" = "$B" ] && ok "B's first write claims it" || bad "ACTIVE: $(cat .flow/ACTIVE)"

echo "-- S6: an unowned (pre-ownership) pointer is anyone's"
printf 'demo\n' >.flow/ACTIVE
C="$(session pane-c)"
[ "$(as "$C" "$T" active)" = demo ] && ok "C sees a pointer with no owner" || bad "C: '$(as "$C" "$T" active)'"
s="$(cd "$SB/wb" && as "$B" "$ST" --full)"
jq -e '.tasks[] | select(.task == "demo") | .where == "main" and .live == false and .owner == ""' <<<"$s" >/dev/null \
  && ok "the pane lists an unowned task as main · no live owner" || bad "unowned row: $(jq -c .tasks <<<"$s")"
git worktree add -q "$SB/wc" -b feat-c
sees "a slug held without a live owner is still refused" "main checkout" bash -c "cd '$SB/wc' && FLOW_SESSION_PID=$C '$T' switch demo"
check "--take moves a task with no live owner here" bash -c "cd '$SB/wc' && FLOW_SESSION_PID=$C '$T' switch demo --take"
[ ! -s .flow/ACTIVE ] && [ "$(cd "$SB/wc" && as "$C" "$T" active)" = demo ] && ok "main's pointer gone, wc leads demo" || bad "after take: main '$(cat .flow/ACTIVE 2>/dev/null)', wc '$(cd "$SB/wc" && as "$C" "$T" active)'"
( cd "$SB/wc" && as "$C" "$T" close >/dev/null ); printf 'demo\n' >.flow/ACTIVE

echo "-- S6b: a crashed session's row whose pid now runs something else is not a live owner"
Z="$(session ghost)"; jq '.procStart = "Thu Jan  1 00:00:00 2015"' "$reg/$Z.json" >"$reg/z" && mv "$reg/z" "$reg/$Z.json"
printf 'demo\n%s\n' "$Z" >.flow/ACTIVE
[ "$(as "$B" "$T" active)" = demo ] && ok "B sees demo: the pid's start time doesn't match the row" || bad "B: '$(as "$B" "$T" active)'"
kill "$Z" 2>/dev/null; printf 'demo\n' >.flow/ACTIVE
kill "$C" 2>/dev/null

echo "-- S7: the owner moves its task into a worktree (branch off for the PR)"
flow_point_as() { printf '%s\n%s\n' "$1" "$2" >.flow/ACTIVE; }
flow_point_as demo "$B"
git worktree add -q "$SB/wpr" -b pr-branch
A="$(session pane-a2)"
[ -z "$(cd "$SB/wpr" && as "$A" "$T" active)" ] && ok "another session in the new worktree doesn't inherit B's task" || bad "A in wpr sees a task"
check "B moves demo into the worktree" bash -c "cd '$SB/wpr' && FLOW_SESSION_PID=$B '$T' switch demo"
[ ! -s .flow/ACTIVE ] && ok "main's pointer moved away" || bad "main ACTIVE: $(cat .flow/ACTIVE 2>/dev/null)"
[ "$(cd "$SB/wpr" && as "$B" "$T" active)" = demo ] && ok "the worktree leads demo for B" || bad "wpr: '$(cd "$SB/wpr" && as "$B" "$T" active)'"

echo "-- S9: session start cleans what crashed sessions leave behind"
mkdir -p "$FLOW_STACK_HOME/leads/x.inbox" "$FLOW_STACK_HOME/hosts"; echo '{}' >"$FLOW_STACK_HOME/leads/x.json"
echo old >"$FLOW_STACK_HOME/hosts/dead"; touch -t 202001010000 "$FLOW_STACK_HOME/hosts/dead"; echo new >"$FLOW_STACK_HOME/hosts/live"
hook session-start.sh "$(ev SessionStart)"
[ ! -e "$FLOW_STACK_HOME/leads" ] && ok "the old leads registry is removed" || bad "leads/ left: $(ls "$FLOW_STACK_HOME/leads")"
[ ! -e "$FLOW_STACK_HOME/hosts/dead" ] && [ -e "$FLOW_STACK_HOME/hosts/live" ] && ok "push records older than 3 days pruned, fresh ones kept" || bad "hosts: $(ls "$FLOW_STACK_HOME/hosts")"

echo "-- S8: a worker lane keeps its lead's task whatever its pid"
git worktree add -q "$SB/wl" -b lane-1
( cd "$SB/wl" && as "" "$T" join beta >/dev/null )
W="$(session worker)"
[ "$(cd "$SB/wl" && as "$W" "$T" active)" = beta ] && ok "a pane worker sees its lane's task" || bad "lane: '$(cd "$SB/wl" && as "$W" "$T" active)'"
kill "$W" 2>/dev/null
finish
