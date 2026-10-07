#!/usr/bin/env bash
# SessionStart · UserPromptSubmit · PostToolUse · SessionEnd: every flow session is a lead.
# It registers in $FLOW_HOME/leads/<session>.json (repo, worktree, branch, task, ticket, slice)
# so other leads can find it with skills/flow/scripts/leads.sh, and it receives their messages
# from <session>.inbox/ (one file per message) on its next prompt or tool call. A subagent
# never takes the lead's mail.
. "$(dirname "$0")/lib.sh"
trap 'exit 0' ERR
FLOW_INPUT="$(cat)"
IFS=$'\t' read -r event sid agent <<<"$(jq -r '[.hook_event_name // "", .session_id // "", .agent_id // "-"] | @tsv' <<<"$FLOW_INPUT")"
[ -n "$sid" ] || exit 0
dir="$FLOW_HOME/leads"; me="$dir/${sid//\//_}"
# Fast exit for the common tool call: a subagent's, or no mail and a fresh heartbeat.
if [ "$event" = PostToolUse ]; then
  [ "$agent" = - ] || exit 0
  [ -n "$(ls -A "$me.inbox" 2>/dev/null)" ] || [ -z "$(find "$me.json" -mmin -5 2>/dev/null)" ] || exit 0
fi
flow_init lead
flow_enabled lead || exit 0
[ -d "$FLOW_DIR" ] || exit 0
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

case "$event" in
  SessionEnd) rm -rf "$me.json" "$me.inbox" ;;
  PostToolUse)
    [ -n "$(find "$me.json" -mmin -5 2>/dev/null)" ] || beat
    m="$(deliver)"
    [ -z "$m" ] || jq -n --arg c "$m" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$c}}' ;;
  SessionStart|UserPromptSubmit)
    first=""; [ -f "$me.json" ] || first=1
    beat
    if [ -n "$first" ] || [ "$event" = SessionStart ]; then
      others="$(find "$dir" -name '*.json' ! -name "${me##*/}.json" -mtime -1 2>/dev/null | wc -l | tr -d ' ')"
      printf '[flow lead] You are lead %s (%s · %s%s). %s other lead(s) active. `%s list` shows who works on which repo, branch, worktree, task, ticket, and PR; `%s msg <id|branch|task|all> "<text>"` messages them.\n' \
        "${sid:0:8}" "$(basename "$FLOW_MAIN")" "$(git -C "$FLOW_ROOT" branch --show-current 2>/dev/null || echo detached)" "${FLOW_TASK:+ · task $FLOW_TASK}" "$others" "$tool" "$tool"
    fi
    deliver ;;
esac
exit 0
