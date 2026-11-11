#!/usr/bin/env bash
# agent.hosts: inside an agent host (herdr, Orca, cmux), the lead's hook pushes its flow phase to the
# host's sidebar once per change and clears it when the task ends; notify.sh leaves the desktop ping
# to the host; setup's inventory sees hosts without moving the fingerprint for anyone else; and
# delegate's dispatch.sh runs a slice's worker as a herdr pane, then cleans up only what it made.
# Hosts are stubs on PATH that log their argv; sockets are real unix sockets in the sandbox.
# Usage: agent.hosts.sh [push] [herdr] [orca] [cmux] [notify] [setup] [dispatch]  (none = all)
. "$(dirname "$0")/lib.sh"; sandbox agent.hosts
set +e  # every assertion reports through ok/bad; a failing grep must not end the run
T="$S/flow/scripts/task.sh"; D="$S/delegate/scripts/dispatch.sh"; INV="$S/setup/scripts/inventory.sh"
SECTIONS=("$@")
on() { [ ${#SECTIONS[@]} -eq 0 ] && return 0; local s; for s in "${SECTIONS[@]}"; do for a in "$@"; do [ "$s" = "$a" ] && return 0; done; done; return 1; }

BIN="$SB/bin"; LOG="$SB/host.log"; mkdir -p "$BIN"; : >"$LOG"
JQ_DIR="$(dirname "$(command -v jq)")"
export PATH="$BIN:$JQ_DIR:/usr/bin:/bin:/usr/sbin:/sbin"
sock() { python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$1"; }
stub() { # stub <name> [body]: a CLI that logs "<name> <argv>" and then runs body
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s $*" >>"%s"\n%s\n' "$1" "$LOG" "${2:-}" >"$BIN/$1"; chmod +x "$BIN/$1"
}
calls() { grep -c "^$1 " "$LOG" 2>/dev/null || true; }
waitfor() { # waitfor <needle>: the log gets a line containing needle within 3s (pushes run in the background)
  local i; for i in $(seq 1 30); do grep -Fq -- "$1" "$LOG" && return 0; sleep 0.1; done; return 1
}
quiet() { sleep 1.5; } # long enough for a background push to have landed if one were sent
ev() { # ev <event> <session> [extra-json]
  local x="${3:-}"; [ -n "$x" ] || x='{}'
  jq -nc --arg e "$1" --arg s "$2" --arg c "$PWD" --argjson x "$x" \
    '{hook_event_name:$e, session_id:$s, cwd:$c, prompt:"go", tool_name:"Bash", tool_input:{command:"ls"}} + $x'
}
no_host() { unset HERDR_ENV HERDR_PANE_ID HERDR_SOCKET_PATH HERDR_BIN_PATH ORCA_PANE_KEY ORCA_WORKTREE_ID ORCA_CLI_COMMAND ORCA_AGENT_HOOK_PORT CMUX_WORKSPACE_ID CMUX_SOCKET_PATH CONDUCTOR_WORKSPACE_PATH; }
herdr_env() { export HERDR_ENV=1 HERDR_PANE_ID="${1:-w1:p1}" HERDR_SOCKET_PATH="$SB/herdr.sock" HERDR_BIN_PATH="$BIN/herdr"; }
no_host

toy_task demo "mul multiplies" "no division"
toy_slice demo S1 doing "bash tests/test_mul.sh" "src/**"
git add -A && git commit -qm task
stub herdr 'echo "{\"result\":{}}"'
sock "$SB/herdr.sock"

if on push herdr; then
  echo "-- herdr: phase pushed once per change"
  herdr_env
  hook host.sh "$(ev UserPromptSubmit sess-a)"
  waitfor "pane report-metadata w1:p1" && ok "prompt pushes to this pane" || bad "no push: $(cat "$LOG")"
  line="$(grep 'report-metadata' "$LOG" | tail -n1)"
  for n in "--source user:flow-stack" "flow_task=demo" "flow_slice=S1" "--clear-token flow_gates" "--ttl-ms" "--seq"; do
    has "$line" "$n" && ok "push has $n" || bad "push lacks $n: $line"
  done
  has "$OUT" "report-metadata" && bad "push leaked into hook stdout" || ok "hook stdout carries no push"
  n0="$(calls herdr)"
  hook host.sh "$(ev PostToolUse sess-a)"; quiet
  [ "$(calls herdr)" = "$n0" ] && ok "tool call with nothing changed: no push" || bad "re-pushed without a change"
  printf 'GATE · ship it?\nwhy: test\n' >>.flow/tasks/demo/GATES.md
  hook host.sh "$(ev PostToolUse sess-a '{"agent_id":"sub-1"}')"; quiet
  [ "$(calls herdr)" = "$n0" ] && ok "subagent tool call never pushes" || bad "subagent pushed"
  hook host.sh "$(ev PostToolUse sess-a)"
  waitfor "flow_gates=⚑1" && ok "new gate → pushed with 1 gate" || bad "gate change not pushed: $(tail -n2 "$LOG")"

  echo "-- herdr: a second pane on its own task shows its own task"
  git worktree add -q -b feat-b ../wt-b
  ( cd ../wt-b && "$T" new other feature >/dev/null )
  wtroot="$(cd ../wt-b && pwd -P)"
  printf '# Slices · other\n\n## S3 · x\nstatus: doing\ncheck: true\nfence: src/**\n' >"$(cd ../wt-b && "$T" dir)/SLICES.md"
  herdr_env w1:p2
  hook host.sh "$(jq -nc --arg c "$wtroot" '{hook_event_name:"UserPromptSubmit", session_id:"sess-b", cwd:$c, prompt:"go"}')"
  waitfor "report-metadata w1:p2" && has "$(grep 'report-metadata w1:p2' "$LOG" | tail -n1)" "flow_task=other" \
    && ok "worktree lead pushes its own task to its own pane" || bad "pane 2: $(grep 'report-metadata w1:p2' "$LOG" | tail -n1)"

  echo "-- herdr: a pane in the same checkout as another live session's task shows none"
  sleep 600 >/dev/null 2>&1 & owner=$!; mkdir -p "$CLAUDE_CONFIG_DIR/sessions"
  echo "{\"pid\":$owner,\"name\":\"pane-1\"}" >"$CLAUDE_CONFIG_DIR/sessions/$owner.json"
  cp .flow/ACTIVE "$SB/active.own"; printf 'demo\n%s\n' "$owner" >.flow/ACTIVE
  herdr_env w1:p3; export FLOW_SESSION_PID=99999
  hook host.sh "$(ev UserPromptSubmit sess-c3)"; quiet
  grep 'report-metadata w1:p3' "$LOG" | grep -q 'flow_task=' && bad "pane 3 shows pane 1's task: $(grep 'report-metadata w1:p3' "$LOG")" || ok "a non-owner pane gets no task row"
  unset FLOW_SESSION_PID; kill "$owner"; cp "$SB/active.own" .flow/ACTIVE
  herdr_env w1:p1

  echo "-- herdr: cleared when the task ends, once"
  cp .flow/ACTIVE "$SB/active.bak"; : >.flow/ACTIVE
  hook host.sh "$(ev UserPromptSubmit sess-a)"
  waitfor "--clear-token flow_task" && ok "no active task → label cleared" || bad "not cleared: $(tail -n2 "$LOG")"
  c1="$(grep -c 'clear-token' "$LOG")"
  hook host.sh "$(ev UserPromptSubmit sess-a)"; quiet
  [ "$(grep -c 'clear-token' "$LOG")" = "$c1" ] && ok "cleared only once" || bad "cleared again"
  cp "$SB/active.bak" .flow/ACTIVE
  hook host.sh "$(ev UserPromptSubmit sess-a)"; waitfor "flow_task=demo" || true
  hook host.sh "$(ev SessionEnd sess-a)"
  waitfor "--clear-token flow_task" && ok "session end clears" || bad "session end did not clear"
  [ -e "$FLOW_STACK_HOME/hosts/sess-a" ] && bad "session end left hosts/sess-a" || ok "session end removes the push record"

  echo "-- herdr: stale env, dead host, hung CLI"
  rm -f "$SB/herdr.sock"; n0="$(calls herdr)"
  printf '\n## S2 · y\nstatus: todo\ncheck: true\nfence: src/**\n' >>.flow/tasks/demo/SLICES.md
  hook host.sh "$(ev UserPromptSubmit sess-c)"; quiet
  [ "$(calls herdr)" = "$n0" ] && ok "host env without its socket: no call" || bad "called herdr with no socket"
  sock "$SB/herdr.sock"
  stub herdr 'echo start >>"'"$SB"'/hang.log"; sleep 5; echo end >>"'"$SB"'/hang.log"'
  printf '\n## S4 · z\nstatus: todo\ncheck: true\nfence: src/**\n' >>.flow/tasks/demo/SLICES.md
  t0="$(date +%s)"; hook host.sh "$(ev UserPromptSubmit sess-c)"; t1="$(date +%s)"
  [ $((t1 - t0)) -le 2 ] && ok "hung host CLI does not hold the hook ($((t1 - t0))s)" || bad "hook waited $((t1 - t0))s"
  sleep 3
  grep -q start "$SB/hang.log" 2>/dev/null && ! grep -q end "$SB/hang.log" && ok "hung host CLI is cut off" || bad "hung CLI ran to the end or never started"
  stub herdr 'echo "{\"result\":{}}"'
  no_host
fi

if on push orca; then
  echo "-- orca: comment on this worktree, unread on a new gate"
  : >"$LOG"; stub orca
  # Orca counts only while its agent-hook port answers: a listener stands in for it
  python3 -c 'import socket,sys,time; s=socket.socket(); s.bind(("127.0.0.1",0)); s.listen(); open(sys.argv[1],"w").write(str(s.getsockname()[1])); time.sleep(60)' "$SB/orca.port" &
  ORCA_LISTENER=$!; sleep 0.3
  export ORCA_PANE_KEY=k1 ORCA_WORKTREE_ID=wt9 ORCA_CLI_COMMAND="$BIN/orca" ORCA_AGENT_HOOK_PORT="$(cat "$SB/orca.port")"
  hook host.sh "$(ev UserPromptSubmit sess-o)"
  waitfor "worktree set --worktree id:wt9 --comment" && has "$(tail -n1 "$LOG")" "demo" \
    && ok "orca comment names the task" || bad "orca: $(cat "$LOG")"
  printf 'GATE · second?\nwhy: test\n' >>.flow/tasks/demo/GATES.md
  hook host.sh "$(ev PostToolUse sess-o)"
  waitfor "--unread" && ok "a new gate marks the worktree unread" || bad "no --unread: $(tail -n1 "$LOG")"
  no_host; n0="$(calls orca)"; export ORCA_CLI_COMMAND="$BIN/orca"
  printf '\n## S5 · q\nstatus: todo\ncheck: true\nfence: src/**\n' >>.flow/tasks/demo/SLICES.md
  hook host.sh "$(ev UserPromptSubmit sess-o)"; quiet
  [ "$(calls orca)" = "$n0" ] && ok "no ORCA_PANE_KEY: orca never called" || bad "orca called outside Orca"
  kill "$ORCA_LISTENER" 2>/dev/null
  no_host
fi

if on push cmux; then
  echo "-- cmux: set-status, only with its socket"
  : >"$LOG"; stub cmux; sock "$SB/cmux.sock"
  export CMUX_WORKSPACE_ID=ws1 CMUX_SOCKET_PATH="$SB/cmux.sock"
  hook host.sh "$(ev UserPromptSubmit sess-x)"
  waitfor "set-status flow" && has "$(tail -n1 "$LOG")" "demo" && ok "cmux status names the task" || bad "cmux: $(cat "$LOG")"
  rm -f "$SB/cmux.sock"; n0="$(calls cmux)"
  printf '\n## S6 · r\nstatus: todo\ncheck: true\nfence: src/**\n' >>.flow/tasks/demo/SLICES.md
  hook host.sh "$(ev UserPromptSubmit sess-x)"; quiet
  [ "$(calls cmux)" = "$n0" ] && ok "no cmux socket: no call" || bad "cmux called without socket"
  no_host
fi

if on notify; then
  echo "-- notify: the host owns the desktop ping; ntfy stays"
  : >"$LOG"; stub osascript; stub curl
  printf -- '---\nnotify: osascript\n---\n# Who\n' >"$FLOW_STACK_HOME/profile.md"
  hook notify.sh '{"message":"Claude needs you"}'
  [ "$(calls osascript)" = 1 ] && ok "outside a host: osascript fires" || bad "outside a host: osascript calls $(calls osascript)"
  sock "$SB/herdr.sock" 2>/dev/null || true; herdr_env
  hook notify.sh '{"message":"Claude needs you"}'
  [ "$(calls osascript)" = 1 ] && ok "inside herdr: osascript skipped" || bad "inside herdr: osascript fired"
  printf -- '---\nnotify: ntfy:flowtest\n---\n# Who\n' >"$FLOW_STACK_HOME/profile.md"
  hook notify.sh '{"message":"Claude needs you"}'
  [ "$(calls curl)" = 1 ] && ok "inside herdr: ntfy still fires" || bad "inside herdr: ntfy calls $(calls curl)"
  printf -- '---\nnotify: osascript\n---\n# Who\n' >"$FLOW_STACK_HOME/profile.md"
  mkdir -p "$FLOW_STACK_HOME"; printf '{"hooks":{"host":false}}' >"$FLOW_STACK_HOME/config.json"
  hook notify.sh '{"message":"Claude needs you"}'
  [ "$(calls osascript)" = 2 ] && ok "hooks.host false: osascript fires again" || bad "hooks.host false ignored"
  rm -f "$FLOW_STACK_HOME/config.json"; no_host
fi

if on setup; then
  echo "-- setup: hosts in the inventory; fingerprint moves only with a host"
  : >"$LOG"; rm -f "$BIN/herdr" "$BIN/orca" "$BIN/cmux"
  export HOME="$SB/userhome"; mkdir -p "$HOME/.config/herdr"
  { git -C "$REPO" show main:plugins/flow-stack/skills/setup/scripts/inventory.sh 2>/dev/null || git -C "$REPO" show origin/main:plugins/flow-stack/skills/setup/scripts/inventory.sh; } >"$SB/inventory.main.sh"
  fp_main="$(bash "$SB/inventory.main.sh" --fingerprint)"
  fp_new="$(bash "$INV" --fingerprint)"
  [ "$fp_main" = "$fp_new" ] && ok "no host: fingerprint same as main" || bad "no host: fingerprint moved ($fp_main → $fp_new)"
  [ "$(bash "$INV" | jq -c '.hosts // {} | length')" = 0 ] && ok "no host: hosts empty" || bad "hosts: $(bash "$INV" | jq -c .hosts)"
  stub herdr 'case "$1" in --version|-V) echo "herdr 0.9.1";; esac'
  [ "$(bash "$INV" | jq -r '.hosts.herdr.version')" = 0.9.1 ] && ok "herdr version detected" || bad "herdr: $(bash "$INV" | jq -c .hosts)"
  [ "$(bash "$INV" | jq -r '.hosts.herdr.claude_integration')" = false ] && ok "herdr integration off" || bad "integration: $(bash "$INV" | jq -c .hosts.herdr)"
  [ "$(bash "$INV" --fingerprint)" != "$fp_main" ] && ok "herdr present: fingerprint moves" || bad "fingerprint unchanged with herdr"
  jq -n '{hooks:{SessionStart:[{matcher:"startup",hooks:[{type:"command",command:"~/.claude/hooks/herdr-agent-state.sh"}]}]}}' >"$CLAUDE_CONFIG_DIR/settings.json"
  [ "$(bash "$INV" | jq -r '.hosts.herdr.claude_integration')" = true ] && ok "herdr integration on" || bad "integration: $(bash "$INV" | jq -c .hosts.herdr)"
  printf '[ui.sidebar.agents]\nrows = ["$flow_task $flow_slice"]\n' >"$HOME/.config/herdr/config.toml"
  [ "$(bash "$INV" | jq -r '.hosts.herdr.sidebar_flow_rows')" = true ] && ok "flow rows in herdr sidebar seen" || bad "rows: $(bash "$INV" | jq -c .hosts.herdr)"
  stub herdr-projects
  [ "$(bash "$INV" | jq -r '.hosts.herdr.projects')" = true ] && ok "herdr-projects seen" || bad "projects: $(bash "$INV" | jq -c .hosts.herdr)"
  stub orca; stub cmux
  [ "$(bash "$INV" | jq -r '.hosts.orca.cli')" = true ] && ok "orca CLI seen" || bad "orca: $(bash "$INV" | jq -c .hosts)"
  [ "$(bash "$INV" | jq -r '.hosts.cmux.cli')" = true ] && ok "cmux CLI seen" || bad "cmux: $(bash "$INV" | jq -c .hosts)"
  rm -f "$BIN/herdr-projects" "$BIN/orca" "$BIN/cmux" "$CLAUDE_CONFIG_DIR/settings.json"
fi

if on dispatch; then
  echo "-- dispatch: a slice's worker in a herdr pane, cleaned up after"
  : >"$LOG"; sock "$SB/herdr.sock" 2>/dev/null || true
  # worktree create makes a real worktree, then answers with herdr's documented result shape
  stub herdr 'case "$1 $2" in
  "worktree create") br=""; while [ $# -gt 0 ]; do [ "$1" = --branch ] && br="$2"; shift; done
    p="'"$SB"'/wt-${br//\//_}"; git worktree add -q -b "$br" "$p" >/dev/null 2>&1
    jq -nc --arg p "$p" --arg b "$br" '"'"'{result:{workspace:{workspace_id:"w2"},tab:{tab_id:"w2:t1"},root_pane:{pane_id:"w2:p1"},worktree:{path:$p,branch:$b}}}'"'"';;
  "agent start") echo "{\"result\":{\"agent\":{\"name\":\"flow-s1\",\"pane_id\":\"w2:p1\"}}}";;
  *) echo "{\"result\":{}}";;
esac'
  printf -- '---\nnotify: off\n---\n# Toolchain\n- delegate: agent · default\n' >"$FLOW_STACK_HOME/profile.md"
  herdr_env
  sees "delegate: agent → use the Agent tool" "Agent tool" "$D" start demo S1
  [ "$(calls herdr)" = 0 ] && ok "delegate: agent never calls herdr" || bad "herdr called for delegate: agent"
  printf -- '---\nnotify: off\n---\n# Toolchain\n- delegate: herdr-panes · watch workers\n' >"$FLOW_STACK_HOME/profile.md"
  out="$("$D" start demo S1 2>&1)" || bad "dispatch start failed: $out"
  grep -q "worktree create .*--branch .*--no-focus\|worktree create .*--no-focus .*--branch" "$LOG" && ok "creates a worktree without stealing focus" || bad "worktree create: $(grep worktree "$LOG")"
  grep -q "agent start .*--kind claude.*--pane w2:p1" "$LOG" && ok "starts claude in the new pane" || bad "agent start: $(grep 'agent start' "$LOG")"
  pl="$(grep 'agent prompt' "$LOG" | tail -n1)"
  has "$pl" "task.sh join demo" && has "$pl" "S1" && has "$pl" "flow-stack:loop" && ok "worker brief: join, slice, loop" || bad "prompt: $pl"
  hostf="$(ls .flow/tasks/demo/lanes/*/HOST 2>/dev/null | head -n1)"
  [ -n "$hostf" ] && grep -q w2 "$hostf" && ok "records what it created (lanes/<lane>/HOST)" || bad "no HOST record"
  lane="$(basename "$(dirname "$hostf")")"
  wtp="$(sed -n 's/^path=//p' "$hostf")"   # the worker's worktree, not the push section's wt-b
  [ -f "$(git -C "$wtp" rev-parse --absolute-git-dir)/flow-thread" ] && ok "worker worktree marked as a thread" || bad "no flow-thread marker"
  # a thread runs like --auto: push waits for the human
  hook guard.sh "$(jq -nc --arg c "$wtp" '{cwd:$c, session_id:"w", hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:"git push origin HEAD"}}')"
  [ "$(decision)" = deny ] && ok "thread: git push is queued, not run" || bad "thread push → $(decision) ($OUT)"
  hook guard.sh "$(jq -nc --arg c "$PWD" '{cwd:$c, session_id:"l", hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:"git push origin HEAD"}}')"
  [ "$(decision)" != deny ] && ok "lead: git push behaves as before" || bad "lead push now denied"
  echo dirty >"$wtp/dirty.txt"
  "$D" cleanup "$lane" >/dev/null 2>&1 || true
  grep -q "worktree remove" "$LOG" && bad "removed a worktree with uncommitted changes" || ok "dirty worktree kept"
  rm -f "$wtp/dirty.txt"
  "$D" cleanup "$lane" >/dev/null 2>&1 || true
  grep -q "worktree remove --workspace w2" "$LOG" && ok "clean worktree removed by its recorded workspace" || bad "cleanup: $(grep remove "$LOG")"
  "$D" cleanup no-such-lane >/dev/null 2>&1 || true
  [ "$(grep -c 'worktree remove' "$LOG")" = 1 ] && ok "never removes what it didn't create" || bad "removed an unrecorded lane"
  no_host
fi

finish
