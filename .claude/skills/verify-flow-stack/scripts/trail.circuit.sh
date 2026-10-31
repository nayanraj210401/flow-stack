#!/usr/bin/env bash
# trail.circuit: PostToolUse appends a redacted row per tool call, and the circuit
# breaker blocks the 3rd identical failure and the 6th edit of one file; trace-stats reads the trail.
. "$(dirname "$0")/lib.sh"; sandbox trail.circuit
post() { # post <tool> <tool_input> [tool_response]
  local r="${3:-}"; [ -n "$r" ] || r='{}'
  jq -nc --arg cwd "$PWD" --arg t "$1" --argjson i "$2" --argjson r "$r" \
    '{cwd:$cwd, session_id:"s1", hook_event_name:"PostToolUse", tool_name:$t, tool_input:$i, tool_response:$r}'
}
fail_run() { post Bash '{"command":"bash tests/test_mul.sh"}' '{"stdout":"FAIL mul\nflow-evidence: FAIL sig=abc123"}'; }

echo "-- no .flow → nothing written"
hook post-tool.sh "$(post Bash '{"command":"ls"}')"
[ ! -e .flow ] && ok "no .flow created" || bad ".flow appeared"

echo "-- trail rows, redacted"
mkdir -p .flow
hook post-tool.sh "$(post Bash '{"command":"curl -H \"Authorization: Bearer abcdefghijklmnop123\" x.test && export OPENAI_API_KEY=sk-live1234567890abcdef"}')"
row="$(tail -n1 .flow/trail.jsonl)"
jq -e '.tool=="Bash" and .sid=="s1" and (.ts|length>0)' <<<"$row" >/dev/null && ok "row has ts, sid, tool" || bad "row: $row"
has "$row" "abcdefghijklmnop123" && bad "bearer token leaked" || ok "bearer token redacted"
has "$row" "sk-live1234567890abcdef" && bad "api key leaked" || ok "api key redacted"

toy_task demo "mul multiplies" "no division"
T=.flow/tasks/demo
hook post-tool.sh "$(post Edit "$(jq -nc --arg f "$PWD/src/calc.sh" '{file_path:$f}')")"
jq -e 'select(.tool=="Edit")' "$T/trail.jsonl" >/dev/null && ok "active task → task trail" || bad "no task trail row"

echo "-- circuit: same failure 3×"
hook post-tool.sh "$(fail_run)"; [ "$(decision)" = allow ] && ok "1st failure passes" || bad "blocked at 1"
hook post-tool.sh "$(fail_run)"; [ "$(decision)" = allow ] && ok "2nd failure passes" || bad "blocked at 2"
expect post-tool.sh "$(fail_run)" block "3rd identical failure"
has "$OUT" "attack-the-premise" && ok "points at attack-the-premise" || bad "reason: $OUT"
hook post-tool.sh "$(fail_run)"; hook post-tool.sh "$(post Bash '{"command":"t"}' '{"stdout":"flow-evidence: PASS"}')"
hook post-tool.sh "$(fail_run)"; hook post-tool.sh "$(fail_run)"
[ "$(decision)" = allow ] && ok "PASS resets the count" || bad "not reset by PASS"

echo "-- circuit: 6 edits to one file"
for i in 1 2 3 4 5; do hook post-tool.sh "$(post Edit "$(jq -nc --arg f "$PWD/src/calc.sh" '{file_path:$f}')")"; done   # PASS above cleared the counter
[ "$(decision)" = allow ] && ok "5th edit passes" || bad "blocked early"
expect post-tool.sh "$(post Edit "$(jq -nc --arg f "$PWD/src/calc.sh" '{file_path:$f}')")" block "6th edit of src/calc.sh"
expect post-tool.sh "$(post Edit "$(jq -nc --arg f "$PWD/$T/SLICES.md" '{file_path:$f}')")" allow ".flow/ edits don't count"

echo "-- toggle: circuit off"
jq '.hooks.circuit=false' .flow/config.json >c && mv c .flow/config.json
for i in 1 2 3; do hook post-tool.sh "$(fail_run)"; done
[ "$(decision)" = allow ] && ok "circuit off → never blocks" || bad "blocked with circuit off"

echo "-- trace-stats reads the trail"
"$S/trace/scripts/trace-stats.sh" >"$ART/trace-stats.txt" 2>&1
grep -q '^# facts · demo' "$ART/trace-stats.txt" && grep -qE 'tool calls: [0-9]+' "$ART/trace-stats.txt" && ok "trace-stats facts" || bad "trace-stats: $(head -5 "$ART/trace-stats.txt")"
grep -q 'src/calc.sh' "$ART/trace-stats.txt" && ok "edited files listed" || bad "no edited files"
cp "$T/trail.jsonl" "$ART/"
finish
