#!/usr/bin/env bash
# PostToolUse: append a redacted audit row to the trail, and run the circuit
# breaker that stops fix-loops (same failing check signature 3 times, or
# heavy churn on one file without a passing check).
. "$(dirname "$0")/lib.sh"
flow_init post-tool
[ -d "$FLOW_DIR" ] || exit 0

tool="$(flow_field .tool_name)"

# ---- trail ----
if flow_enabled trail; then
  trail="${FLOW_STATE_DIR:-$FLOW_DIR}/trail.jsonl"
  target="$(jq -r '
    .tool_input as $i |
    ($i.command // $i.file_path // $i.notebook_path // $i.pattern // $i.url // $i.query // $i.description // $i.skill // "")
    | tostring | .[0:300]' <<<"$FLOW_INPUT" | redact | tr '\n' ' ')"
  err="$(jq -r '(.tool_response | objects | (.is_error // (.error != null) // false)) // false' <<<"$FLOW_INPUT" 2>/dev/null || echo false)"
  jq -cn \
    --arg ts "$(date -u +%FT%TZ)" \
    --arg sid "$(flow_field .session_id)" \
    --arg agent "$(flow_field .agent_type)" \
    --arg tool "$tool" \
    --arg target "$target" \
    --argjson err "${err:-false}" \
    '{ts:$ts, sid:$sid, tool:$tool, target:$target, err:$err} + (if $agent != "" then {agent:$agent} else {} end)' \
    >>"$trail"
fi

# ---- circuit ----
[ -n "$FLOW_TASK_DIR" ] && flow_enabled circuit || exit 0
state="$FLOW_STATE_DIR/.circuit"
mkdir -p "$state"

feedback() {
  jq -n --arg r "$1" '{decision:"block", reason:$r}'
  exit 0
}

case "$tool" in
  Bash)
    out="$(jq -r '(.tool_response | if type == "object" then (.stdout // "") + "\n" + (.stderr // "") else tostring end)' <<<"$FLOW_INPUT")"
    line="$(grep -Eo 'flow-evidence: (PASS|FAIL)( sig=[0-9a-f]+)?' <<<"$out" | tail -n1 || true)"
    case "$line" in
      *PASS*)
        rm -f "$state"/fail-* "$state"/edits
        ;;
      *FAIL*)
        sig="${line##*sig=}"
        n=$(( $(cat "$state/fail-$sig" 2>/dev/null || echo 0) + 1 ))
        echo "$n" >"$state/fail-$sig"
        if [ "$n" -ge 3 ]; then
          rm -f "$state/fail-$sig"
          feedback "flow circuit breaker: the same check failure (sig $sig) has now happened $n times. Stop patching. Apply principle-attack-the-premise (flow-stack:principles): write the assumption all your fixes shared, design one observation that could disprove it, run it, then run the flow-stack:challenge skill (a fresh advocate designs from the goal alone, so it can't share your assumption), and raise a GATE to the human with what you learned. Log this in DECISIONS.tsv."
        fi
        ;;
    esac
    ;;
  Edit|Write|MultiEdit)
    file="$(flow_rel "$(flow_field .tool_input.file_path)")"
    case "$file" in .flow/*|/*|"") exit 0 ;; esac
    echo "$file" >>"$state/edits"
    n="$(grep -Fxc -- "$file" "$state/edits" || true)"
    if [ "$n" -eq 6 ]; then
      feedback "flow circuit breaker: '$file' has been edited $n times since the last passing check. If you are circling, stop and diagnose (flow-stack:diagnose) before the next edit. If this is planned incremental work, run the slice check now to reset the counter."
    fi
    ;;
esac
exit 0
