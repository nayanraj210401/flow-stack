#!/usr/bin/env bash
# SessionStart · UserPromptSubmit · PostToolUse · SessionEnd: every flow session is a lead.
# It registers in $FLOW_HOME/leads/<session>.json (repo, worktree, branch, task, ticket, slice)
# so other leads can find it with skills/flow/scripts/leads.sh, and it receives their messages
# from <session>.inbox/ (one file per message) on its next prompt or tool call. A subagent
# never takes the lead's mail.
. "$(dirname "$0")/lib.sh"
trap 'exit 0' ERR
FLOW_INPUT="$(cat)"
IFS=$'\t' read -r event sid agent src <<<"$(jq -r '[.hook_event_name // "", .session_id // "", .agent_id // "-", .source // "-"] | @tsv' <<<"$FLOW_INPUT")"
[ -n "$sid" ] || exit 0
dir="$FLOW_HOME/leads"; me="$dir/${sid//\//_}"
# unchanged: every phase file recorded with the last push (lines 4+ of $me.host) still exists, none newer.
unchanged() {
  local p n=0
  [ -f "$me.host" ] || return 1
  # strictly newer: macOS bash 3.2 compares whole seconds, so a same-second change must count
  while read -r p; do n=1; [ -e "$p" ] && [ "$me.host" -nt "$p" ] || return 1; done < <(tail -n +4 "$me.host")
  [ "$n" = 1 ]
}
# Fast exit for the common tool call: a subagent's, or no mail and a fresh heartbeat (and, inside
# an agent host, no phase change since the last push).
[ "$event" = PostToolUse ] && [ "$agent" != - ] && exit 0
host=""; [ -z "${HERDR_ENV:-}${ORCA_PANE_KEY:-}${CMUX_WORKSPACE_ID:-}" ] || host="$(flow_host)"
case "$host" in herdr|orca|cmux) ;; *) host="" ;; esac
if [ "$event" = PostToolUse ]; then
  [ -n "$(ls -A "$me.inbox" 2>/dev/null)" ] || [ -z "$(find "$me.json" -mmin -5 2>/dev/null)" ] || { [ -n "$host" ] && ! unchanged; } || exit 0
fi
flow_init lead
flow_enabled lead || exit 0
[ -d "$FLOW_DIR" ] || exit 0
flow_enabled host || host=""
tool="$(cd "$(dirname "$0")/../skills/flow/scripts" && pwd)/leads.sh"

beat() {
  local goal="" slice="" ticket=""
  mkdir -p "$dir"
  if [ -n "$FLOW_TASK_DIR" ]; then
    goal="$(awk '/<!--/{c=1} c{if(/-->/)c=0; next} /^## Goal/{on=1;next} on && /^## /{exit} on && NF{print; exit}' "$FLOW_TASK_DIR/INTENT.md" 2>/dev/null || true)"
    slice="$(awk '/^## /{h=$2} /^status: doing/{print h; exit}' "$FLOW_TASK_DIR/SLICES.md" 2>/dev/null || true)"
    ticket="$(head -n1 "$FLOW_TASK_DIR/TICKET" 2>/dev/null || true)"
  fi
  jq -n --arg sid "$sid" --arg repo "$FLOW_MAIN" --arg root "$FLOW_ROOT" \
    --arg branch "$(git -C "$FLOW_ROOT" branch --show-current 2>/dev/null || true)" \
    --arg task "$FLOW_TASK" --arg goal "$goal" --arg slice "$slice" --arg ticket "$ticket" \
    --arg updated "$(date -u +%FT%TZ)" --argjson ts "$(date +%s)" \
    '{sid:$sid, id:$sid[0:8], repo:$repo, root:$root, branch:$branch, task:$task, goal:$goal, slice:$slice, ticket:$ticket, updated:$updated, ts:$ts}' \
    >"$me.json.$$" && mv "$me.json.$$" "$me.json"
  find "$dir" -mindepth 1 -maxdepth 1 -mtime +3 -exec rm -rf {} + 2>/dev/null || true
}

deliver() { # print and consume this lead's messages; the rename claims each one, so two deliveries never repeat one
  local m
  for m in "$me.inbox"/*.json; do
    [ -f "$m" ] && mv "$m" "$m.$$" 2>/dev/null || continue
    jq -r --arg t "$tool" '"[flow msg · from lead \(.from) (\(.label))] \(.text)\n  reply: \($t) msg \(.from) \"<text>\""' "$m.$$" || true
    rm -f "$m.$$"
  done
}

# Run a host CLI in the background, output discarded, cut off after ~1s (stock macOS has no timeout).
host_run() {
  ( "$@" & p=$!; ( sleep 1; kill "$p"; sleep 1; kill -9 "$p" ) & k=$!; wait "$p"; kill "$k" ) >/dev/null 2>&1 </dev/null &
}

# push: show "task · slice done/total · gates" in the host's sidebar once per change. Never prints.
# $me.host holds the last pushed text, gate count and herdr seq ("-" = cleared). On a tool call it is skipped
# while that record is newer than the files that move the phase; the text compare covers the rest.
push() {
  local row tk="" sl="" dn="" tt="" gt=0 txt prev="" pg=0 sq=0 watch unread=() clear=""
  [ "${1:-}" = clear ] || [ "$event" != PostToolUse ] || ! unchanged || return 0
  { read -r prev; read -r pg; read -r sq; } <"$me.host" 2>/dev/null || true
  if [ "${1:-}" = clear ] || [ -z "$FLOW_TASK" ]; then clear=1; txt="-"
  else
    row="$("$(dirname "$tool")/status.sh" --full "$FLOW_ROOT" 2>/dev/null | jq -r '[.task, (.slice.id // "-"), .done, .total, (.gates | length)] | @tsv')" || return 0
    IFS=$'\t' read -r tk sl dn tt gt <<<"$row"
    [ -n "$tk" ] || return 0
    txt="$tk · $sl · $dn/$tt · $gt gate(s)"; txt="${txt//[$'\n\r']/ }"
  fi
  # the files whose change moves the phase; dirs catch a GATES.md or TDD that appears later, and the
  # pointer's dir catches a task that starts after a clear
  watch="$(for w in "$FLOW_ACTIVE" "$FLOW_TASK_DIR" "$FLOW_TASK_DIR/SLICES.md" "$FLOW_TASK_DIR/GATES.md" "$FLOW_STATE_DIR" "$FLOW_STATE_DIR/TDD"; do
    [ -n "$w" ] && [ "$w" != / ] && [ -e "$w" ] && echo "$w"; done; [ -n "$FLOW_TASK" ] || dirname "$FLOW_ACTIVE")"
  if [ "$txt" = "$prev" ]; then printf '%s\n%s\n%s\n%s\n' "$txt" "$gt" "$sq" "$watch" >"$me.host"; return 0; fi
  # herdr drops a report whose --seq isn't newer than the last, so two pushes in one second still count
  sq=$(( $(date +%s)000 > ${sq:-0} ? $(date +%s)000 : ${sq:-0} + 1 ))
  mkdir -p "$dir"; printf '%s\n%s\n%s\n%s\n' "$txt" "$gt" "$sq" "$watch" >"$me.host.$$" && mv "$me.host.$$" "$me.host"
  [ "$gt" -le "${pg:-0}" ] || unread=(--unread)
  case "$host" in
    herdr)
      if [ -n "$clear" ]; then host_run "$HERDR_BIN_PATH" pane report-metadata "$HERDR_PANE_ID" --source user:flow-stack --clear-token flow_task --clear-token flow_slice --clear-token flow_gates --seq "$sq"
      else host_run "$HERDR_BIN_PATH" pane report-metadata "$HERDR_PANE_ID" --source user:flow-stack \
        --token "flow_task=${tk:0:80}" --token "flow_slice=${sl:0:40} $dn/$tt" --token "flow_gates=$gt" --ttl-ms 86400000 --seq "$sq"; fi ;;
    orca) host_run "${ORCA_CLI_COMMAND:-orca}" worktree set --worktree "id:${ORCA_WORKTREE_ID:-}" --comment "${txt#-}" ${unread[@]+"${unread[@]}"} ;;
    cmux) if [ -n "$clear" ]; then host_run cmux clear-status flow; else host_run cmux set-status flow "$txt"; fi ;;
  esac
}

case "$event" in
  SessionEnd) [ -z "$host" ] || { push clear; rm -f "$me.host"; }; rm -rf "$me.json" "$me.inbox" ;;
  PostToolUse)
    [ -n "$(find "$me.json" -mmin -5 2>/dev/null)" ] || beat
    m="$(deliver)"
    [ -z "$m" ] || jq -n --arg c "$m" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$c}}'
    [ -z "$host" ] || push 2>/dev/null || true ;;
  SessionStart|UserPromptSubmit)
    first=""; [ -f "$me.json" ] || first=1
    [ "$src" != clear ] || rm -f "$me.host"
    beat
    if [ -n "$first" ] || [ "$event" = SessionStart ]; then
      others="$(find "$dir" -name '*.json' ! -name "${me##*/}.json" -mtime -1 2>/dev/null | wc -l | tr -d ' ')"
      printf '[flow lead] You are lead %s (%s · %s%s). %s other lead(s) active. `%s list` shows who works on which repo, branch, worktree, task, ticket, and PR; `%s msg <id|branch|task|all> "<text>"` messages them.\n' \
        "${sid:0:8}" "$(basename "$FLOW_MAIN")" "$(git -C "$FLOW_ROOT" branch --show-current 2>/dev/null || echo detached)" "${FLOW_TASK:+ · task $FLOW_TASK}" "$others" "$tool" "$tool"
    fi
    deliver
    [ -z "$host" ] || push 2>/dev/null || true ;;
esac
exit 0
