#!/usr/bin/env bash
# Stop: the claims check. If the final message claims success but no passing
# evidence exists since the last code edit, send the agent back once to either
# verify or mark the claim as assumed. Then notify if configured.
. "$(dirname "$0")/lib.sh"
flow_init stop

notify_done() {
  [ "$(profile_fm notify_on 2>/dev/null)" = all ] || return 0
  "$(dirname "$0")/notify.sh" "Claude finished${FLOW_TASK:+ · $FLOW_TASK}" </dev/null >/dev/null 2>&1 || true
}

if [ "$(flow_field .stop_hook_active)" = true ] || [ -z "$FLOW_TASK_DIR" ] || ! flow_enabled claims; then
  notify_done; exit 0
fi

transcript="$(flow_field .transcript_path)"
last_msg=""
if [ -f "$transcript" ]; then
  last_msg="$(tail -n 200 "$transcript" | jq -rs '
    map(select(.type == "assistant")) | last | .message.content // []
    | map(select(.type == "text") | .text) | join("\n")' 2>/dev/null || true)"
fi

claims='\b(done|fixed|works|working now|all (tests|checks) pass(ing)?|passes|complete[d]?|ready to (merge|ship|review))\b'
if [ -n "$last_msg" ] && grep -Eiq "$claims" <<<"$last_msg" && ! grep -q '~ assumed' <<<"$last_msg"; then
  last_edit="$(jq -r 'select(.tool == "Edit" or .tool == "Write" or .tool == "MultiEdit") | .ts' "$FLOW_STATE_DIR/trail.jsonl" 2>/dev/null | tail -n1 || true)"
  last_pass="$(grep -E '^### .* · PASS · ' "$FLOW_STATE_DIR/EVIDENCE.md" 2>/dev/null | tail -n1 | awk '{print $2}' || true)"
  if [ -n "$last_edit" ] && { [ -z "$last_pass" ] || [[ "$last_pass" < "$last_edit" ]]; }; then
    jq -n --arg r "flow claims check: your reply claims success, but there is no passing evidence in .flow/tasks/$FLOW_TASK/EVIDENCE.md since the last code edit ($last_edit). Either run the check through verify's scripts/evidence.sh and cite the entry, or rewrite the claim as '~ assumed: <what was not verified>'." \
      '{decision:"block", reason:$r}'
    exit 0
  fi
fi

notify_done
exit 0
