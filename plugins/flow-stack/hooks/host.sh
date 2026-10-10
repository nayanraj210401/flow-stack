#!/usr/bin/env bash
# SessionStart · UserPromptSubmit · PostToolUse · SessionEnd: inside an agent host (herdr, Orca, cmux),
# show this session's own task in the host's sidebar as "task · slice done/total · gates", once per
# change, and clear it at session end. A session whose checkout's task another session owns shows none.
# Who works on what lives in Claude Code's session registry (ListAgents) and the task pointers
# (task.sh list); sessions message each other with SendMessage.
. "$(dirname "$0")/lib.sh"
trap 'exit 0' ERR
FLOW_INPUT="$(cat)"
IFS=$'\t' read -r event sid agent src <<<"$(jq -r '[.hook_event_name // "", .session_id // "", .agent_id // "-", .source // "-"] | @tsv' <<<"$FLOW_INPUT")"
[ -n "$sid" ] || exit 0
host=""
[ -z "${HERDR_ENV:-}${ORCA_PANE_KEY:-}${CMUX_WORKSPACE_ID:-}" ] || host="$(flow_host)"
case "$host" in herdr|orca|cmux) ;; *) exit 0 ;; esac
dir="$FLOW_HOME/hosts"; me="$dir/${sid//\//_}"
# unchanged: every phase file recorded with the last push (lines 4+ of $me) still exists, none newer.
unchanged() {
  local p n=0
  [ -f "$me" ] || return 1
  # strictly newer: macOS bash 3.2 compares whole seconds, so a same-second change must count
  while read -r p; do n=1; [ -e "$p" ] && [ "$me" -nt "$p" ] || return 1; done < <(tail -n +4 "$me")
  [ "$n" = 1 ]
}
# Fast exit for the common tool call: a subagent's, or no phase change since the last push.
[ "$event" != PostToolUse ] || { [ "$agent" = - ] && ! unchanged; } || exit 0
flow_init host
flow_enabled host || exit 0
[ -d "$FLOW_DIR" ] || exit 0
status="$(cd "$(dirname "$0")/../skills/flow/scripts" && pwd)/status.sh"

# Run a host CLI in the background, output discarded, cut off after ~1s (stock macOS has no timeout).
host_run() {
  ( "$@" & p=$!; ( sleep 1; kill "$p"; sleep 1; kill -9 "$p" ) & k=$!; wait "$p"; kill "$k" ) >/dev/null 2>&1 </dev/null &
}

# Per herdr pane, not per session, so a resumed or restarted session in the same pane knows what
# flow already did there: the agent name it set, and the last gate it toasted.
pane_rec="${HERDR_PANE_ID:-}"; pane_rec="$dir/pane-${pane_rec//[^A-Za-z0-9]/_}"

# herdr_name <task|"">: name this pane's herdr agent row after the task, or clear it. A name flow
# didn't set (the human's, another plugin's) is never touched, nor is any name when herdr can't be
# read. host_run's 1s cut-off stops this function, not a herdr call it already started.
herdr_name() {
  local j cur mine n
  mine="$(cat "$pane_rec.name" 2>/dev/null)"
  j="$("$HERDR_BIN_PATH" agent get "$HERDR_PANE_ID" 2>/dev/null)" || return 0
  cur="$(jq -er '.result.agent | .name // ""' <<<"$j")" || return 0
  [ -z "$cur" ] || [ "$cur" = "$mine" ] || return 0
  # herdr agent names: a lowercase letter, then lowercase letters, digits, - or _, at most 32
  n="$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9_-' '-' | sed 's/^[^a-z]*//' | cut -c1-32)"
  if [ -n "$n" ]; then
    [ "$n" = "$cur" ] || "$HERDR_BIN_PATH" agent rename "$HERDR_PANE_ID" "$n" && printf '%s' "$n" >"$pane_rec.name"
  elif [ -n "$cur" ]; then "$HERDR_BIN_PATH" agent rename "$HERDR_PANE_ID" --clear && rm -f "$pane_rec.name"; fi
}

# push: show the task in the host's sidebar once per change. Never prints. In herdr, also: open gates
# mark the row (⚑n) until decided, a new one toasts, and an unnamed agent row takes the task's name.
# $me holds the last pushed text, gate count, herdr seq, then the watched paths.
push() {
  local row tk="" sl="" dn="" tt="" gt=0 gq="" txt prev="" pg=0 sq=0 watch unread=() clear="" mark
  { read -r prev; read -r pg; read -r sq; } <"$me" 2>/dev/null || true
  if [ "${1:-}" = clear ] || [ -z "$FLOW_TASK" ]; then clear=1; txt="-"
  else
    row="$("$status" --full "$FLOW_ROOT" 2>/dev/null | jq -r '[.task, (.slice.id // "-"), .done, .total, (.gates | length), (.gates[-1].question // "")] | @tsv')" || return 0
    IFS=$'\t' read -r tk sl dn tt gt gq <<<"$row"
    [ -n "$tk" ] || return 0
    txt="$tk · $sl · $dn/$tt · $gt gate(s)"; txt="${txt//[$'\n\r']/ }"
  fi
  # the files whose change moves the phase; dirs catch a GATES.md or TDD that appears later, and the
  # pointer's dir and the tasks dir catch a task that starts (or an owner that changes) after a clear
  watch="$(for w in "$FLOW_ACTIVE" "$FLOW_TASK_DIR" "$FLOW_TASK_DIR/SLICES.md" "$FLOW_TASK_DIR/GATES.md" "$FLOW_STATE_DIR" "$FLOW_STATE_DIR/TDD"; do
    [ -n "$w" ] && [ "$w" != / ] && [ -e "$w" ] && echo "$w"; done; [ -n "$FLOW_TASK" ] || for w in "$(dirname "$FLOW_ACTIVE")" "$FLOW_DIR/tasks"; do [ -e "$w" ] && echo "$w"; done)"
  mkdir -p "$dir"
  if [ "$txt" = "$prev" ]; then printf '%s\n%s\n%s\n%s\n' "$txt" "$gt" "$sq" "$watch" >"$me"; return 0; fi
  # herdr drops a report whose --seq isn't newer than the last, so two pushes in one second still count
  sq=$(( $(date +%s)000 > ${sq:-0} ? $(date +%s)000 : ${sq:-0} + 1 ))
  printf '%s\n%s\n%s\n%s\n' "$txt" "$gt" "$sq" "$watch" >"$me.$$" && mv "$me.$$" "$me"
  [ "$gt" -le "${pg:-0}" ] || unread=(--unread)
  case "$host" in
    herdr)
      if [ -n "$clear" ]; then host_run "$HERDR_BIN_PATH" pane report-metadata "$HERDR_PANE_ID" --source user:flow-stack --clear-token flow_task --clear-token flow_slice --clear-token flow_gates --seq "$sq"
        host_run herdr_name ""
      else
        mark=(--clear-token flow_gates); [ "$gt" = 0 ] || mark=(--token "flow_gates=⚑$gt")
        host_run "$HERDR_BIN_PATH" pane report-metadata "$HERDR_PANE_ID" --source user:flow-stack \
          --token "flow_task=${tk:0:80}" --token "flow_slice=${sl:0:40} $dn/$tt" "${mark[@]}" --ttl-ms 86400000 --seq "$sq"
        # toast the newest open gate once per pane, whatever the count did meanwhile (one decided, one added)
        if [ "$gt" != 0 ] && [ "$gq" != "$(cat "$pane_rec.toast" 2>/dev/null)" ]; then
          printf '%s' "$gq" >"$pane_rec.toast"
          host_run "$HERDR_BIN_PATH" notification show "$tk: gate open" --body "${gq:0:200}" --sound request
        fi
        host_run herdr_name "$tk"
      fi ;;
    orca) host_run "${ORCA_CLI_COMMAND:-orca}" worktree set --worktree "id:${ORCA_WORKTREE_ID:-}" --comment "${txt#-}" ${unread[@]+"${unread[@]}"} ;;
    cmux) if [ -n "$clear" ]; then host_run cmux clear-status flow; else host_run cmux set-status flow "$txt"; fi ;;
  esac
}

case "$event" in
  SessionEnd) push clear 2>/dev/null || true; rm -f "$me" ;;
  SessionStart) [ "$src" != clear ] || rm -f "$me"; push 2>/dev/null || true ;;
  *) push 2>/dev/null || true ;;
esac
exit 0
