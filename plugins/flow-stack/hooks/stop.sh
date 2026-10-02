#!/usr/bin/env bash
# Stop: the claims check, with or without a task. If the final message claims success
# but no check passed (a tool result ending in `flow-evidence: PASS` or a ready stamp) after the
# last code edit in this transcript, send the agent back once to either verify or mark
# the claim as assumed. Shell writes count as edits; docs, .flow/ and temp files don't.
# Then notify if configured.
. "$(dirname "$0")/lib.sh"
flow_init stop

notify_done() {
  [ "$(profile_fm notify_on 2>/dev/null)" = all ] || return 0
  "$(dirname "$0")/notify.sh" "Claude finished${FLOW_TASK:+ · $FLOW_TASK}" </dev/null >/dev/null 2>&1 || true
}

transcript="$(flow_field .transcript_path)"
if [ "$(flow_field .stop_hook_active)" = true ] || [ ! -f "$transcript" ] || ! flow_enabled claims; then
  notify_done; exit 0
fi

# One letter per event, in order: E = a code edit (in this repo or the task's other repos),
# P = a passing check. A P must come from a Bash call that ran evidence.sh, features.sh, or
# ready.sh; inside a task, only a C<n>/S<n> check, all or impacted features, or ready.sh.
# An unparseable line is skipped.
roots="$({ echo "$FLOW_ROOT"; cut -f2 "$FLOW_TASK_DIR/REPOS" 2>/dev/null; } | jq -Rs 'split("\n") | map(select(length > 0) | . + "/")')"
check_re='(evidence|features|ready)\.sh'
[ -n "$FLOW_TASK_DIR" ] && check_re='evidence\.sh.*[[:space:]][CS][0-9]+([^0-9A-Za-z]|$)|features\.sh[[:space:]]+run[[:space:]]+--(all|impacted)|ready\.sh'
events="$(tail -n 3000 "$transcript" | jq -nrR --argjson roots "$roots" --arg check_re "$check_re" '
  def txt: if type == "string" then . elif type == "array" then map(.text? // "") | join("\n") else "" end;
  def scratch: . as $p | ($roots | any(. as $r | $p | startswith($r)) | not) or test("\\.(md|txt)$|/\\.flow/");
  def shell_write: gsub("\"[^\"]*\"|'"'"'[^'"'"']*'"'"'"; "")
    | gsub("[0-9]*>>?[[:space:]]*(/dev/null|&[0-9]-?)"; "")
    | gsub("(>>?|\\btee( -a)?)[[:space:]]*[^[:space:];|&]*(\\.flow/|/tmp/|scratchpad|\\.md|\\.txt)[^[:space:];|&]*"; "")
    | test("\\bsed -[a-zA-Z]*i|\\bperl -[a-z]*i|\\btee\\b|>>?[[:space:]]*[^[:space:]=>&]"
      + "|(^|[;&|][[:space:]]*)(cp|mv)( -[A-Za-z]+)*( [^-;&|[:space:]][^;&|[:space:]]*)+"
      + " (?![^;&|[:space:]]*(/tmp/|scratchpad|\\.flow/))[^-;&|[:space:]][^;&|[:space:]]*[[:space:]]*($|[;&|])"
      + "|(^|[;&|][[:space:]]*)patch[[:space:]]"
      + "|git apply[[:space:]]+(?!--(check|stat|numstat|summary))");
  def verdict: txt | split("\n") | map(select(test("\\S"))) | (last // "")
    | test("^flow-evidence: PASS|^ready for review: [0-9a-f]+ stamped");
  reduce (inputs | fromjson? | .message.content? // [] | if type == "array" then .[] else empty end) as $c
    ({checks: {}, s: ""};
     if $c.type == "tool_use" and ($c.name | test("^(Edit|Write|MultiEdit|NotebookEdit)$"))
        and (($c.input.file_path // $c.input.notebook_path // "") | scratch | not) then .s += "E"
     elif $c.type == "tool_use" and $c.name == "Bash" then
       (if ($c.input.command // "" | test($check_re)) then .checks[$c.id // ""] = true else . end)
       | if ($c.input.command // "" | shell_write) then .s += "E" else . end
     elif $c.type == "tool_result" and .checks[$c.tool_use_id // ""] and $c.is_error != true and ($c.content | verdict) then .s += "P"
     else . end) | .s' 2>/dev/null || true)"
last_msg="$(tail -n 200 "$transcript" | jq -nrR '
  [inputs | fromjson? | select(.type == "assistant")] | last | .message.content // []
  | map(select(.type == "text") | .text) | join("\n")' 2>/dev/null || true)"

claims='\b(done|fixed|works|working now|all (tests|checks) pass(ing)?|passes|complete[d]?|ready to (merge|ship|review))\b'
if [[ "$events" =~ E[^P]*$ ]] && grep -Eiq "$claims" <<<"$last_msg" && ! grep -q '~ assumed' <<<"$last_msg"; then
  jq -n --arg r "flow claims check: your reply claims success, but no check passed after your last code edit. Run the check through verify's scripts/evidence.sh (\`evidence.sh C<n>\` in a task, \`evidence.sh smoke '<cmd>'\` otherwise) as the last command in the call, so its flow-evidence line ends the output, and cite it, or rewrite the claim as '~ assumed: <what was not verified>'." \
    '{decision:"block", reason:$r}'
  exit 0
fi

notify_done
exit 0
