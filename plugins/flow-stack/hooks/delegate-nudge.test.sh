#!/usr/bin/env bash
# delegate-nudge.test.sh: the nudge counts turns over the whole transcript, counts sdk/person
# prompts, stays quiet for subagents, and re-nudges after 3 turns.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
SB="$(mktemp -d "${TMPDIR:-/tmp}/delegate-nudge.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" HOME="$SB/hm"; mkdir -p "$HOME" "$FLOW_STACK_HOME"; cd "$SB"
TR="$SB/t.jsonl"; fail=0
hu() { jq -nc --arg k "${1:-human}" '{type:"user", message:{role:"user",content:"p"}, origin:{kind:$k}}' >>"$TR"; }
as() { jq -nc '{type:"assistant", message:{content:[{type:"text",text:"ok"}]}}' >>"$TR"; }
rd() { jq -nc '{type:"assistant", message:{content:[{type:"tool_use", name:"Read", input:{file_path:"a"}}]}}' >>"$TR"; }
run() {
  jq -nc --arg s "$1" --arg tp "$TR" --arg a "${2:-}" --arg cwd "$SB" \
    '{session_id:$s, transcript_path:$tp, cwd:$cwd, hook_event_name:"PostToolUse"} + (if $a == "" then {} else {agent_id:$a} end)' |
    bash "$H/delegate-nudge.sh" 2>/dev/null
}
want() { # want <nudge|quiet> <label> <output>
  if [ "$1" = nudge ]; then
    jq -e .hookSpecificOutput.additionalContext <<<"$3" >/dev/null 2>&1 || { echo "  ✗ $2"; fail=1; }
  else
    [ -z "$3" ] || { echo "  ✗ $2: $3"; fail=1; }
  fi
}
: >"$TR"; for i in 1 2 3; do hu; as; done; rd; rd; rd; rd
want quiet "turn 3 stays quiet" "$(run a)"
: >"$TR"; for i in 1 2 3 4 5 6 7 8; do hu; as; done; rd; rd; rd; rd
want quiet "subagent stays quiet" "$(run b agent1)"
want nudge "turn 8 nudges" "$(run b)"
want quiet "no immediate repeat" "$(run b)"
hu; as; hu; as; hu; as; rd; rd; rd; rd
want nudge "re-nudge 3 turns later" "$(run b)"
: >"$TR"; for i in 1 2 3 4 5 6 7 8; do hu sdk; as; done
for i in $(seq 1 3100); do as; done; rd; rd; rd; rd
want nudge "sdk turns count and scroll-out cannot silence it" "$(run c)"
[ "$fail" = 0 ] && { echo "  ✓ delegate-nudge turns, guard, re-nudge, scroll-out"; echo PASS; } || exit 1
