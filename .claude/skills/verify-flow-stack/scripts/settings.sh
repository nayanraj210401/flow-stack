#!/usr/bin/env bash
# settings: ~/.flow-stack/settings.json toggles default hooks (repo .flow/config.json wins), and
# suites.sh runs only the test sub-suites a change touches, from verify and from ready.sh.
. "$(dirname "$0")/lib.sh"; sandbox settings
ST="$S/settings/scripts/settings.sh"
SU="$S/verify/scripts/suites.sh"
push='git push --force origin main'

echo "-- hook toggles through settings.json, as Claude Code runs the hooks"
hook guard.sh "$(bashcmd "$push")"; d0="$(decision)"
[ "$d0" != allow ] && ok "default: force push to main → $d0" || bad "guard allowed a force push by default"
"$ST" hook guard off >/dev/null
expect guard.sh "$(bashcmd "$push")" allow "settings.json hooks.guard false"
sees "show names settings.json as the deciding file" "settings.json" "$ST" show
"$ST" hook guard default >/dev/null
hook guard.sh "$(bashcmd "$push")"; [ "$(decision)" = "$d0" ] && ok "hook guard default → $d0 again" || bad "default did not restore the guard: $(decision)"

echo "-- the repo's .flow/config.json beats settings.json"
mkdir -p .flow; echo '{"hooks":{"guard":false}}' >.flow/config.json
"$ST" hook guard on >/dev/null
expect guard.sh "$(bashcmd "$push")" allow "repo guard false beats settings.json guard true"
sees "a shadowed global write says the repo wins" "wins here" "$ST" hook guard on
rm -f .flow/config.json "$FLOW_STACK_HOME/settings.json"

echo "-- the claims (evidence) Stop hook"
TR="$SB/t.jsonl"
jq -nc --arg f "$PWD/src/calc.sh" '{type:"assistant", message:{content:[{type:"tool_use", id:"e1", name:"Edit", input:{file_path:$f}}]}}' >"$TR"
jq -nc '{type:"assistant", message:{content:[{type:"text", text:"All done, the tests pass."}]}}' >>"$TR"
stop() { jq -nc --arg cwd "$PWD" --arg tp "$TR" '{cwd:$cwd, hook_event_name:"Stop", transcript_path:$tp, stop_hook_active:false}'; }
expect stop.sh "$(stop)" block "unverified done, claims on"
fails "'evidence' is not a hook name" "$ST" hook evidence off
sees "the refusal points at claims" "'claims'" "$ST" hook evidence off
"$ST" hook claims off >/dev/null
expect stop.sh "$(stop)" allow "settings.json hooks.claims false"
rm -f "$FLOW_STACK_HOME/settings.json"

echo "-- impacted test suites"
mkdir -p src/auth src/billing; echo a >src/auth/a.sh; echo b >src/billing/b.sh
jq -n --arg m "$SB/ran" '{commands:{test:("echo full >>"+$m)}, tests:{suites:[
  {id:"auth", paths:["src/auth/**"], run:("echo auth >>"+$m)},
  {id:"billing", paths:["src/billing/**"], run:("echo billing >>"+$m+"; exit 1")}]}}' >.flow/config.json
git add -A && git commit -qm suites
ran() { sort -u "$SB/ran" 2>/dev/null | tr '\n' ' '; }
echo x >>src/auth/a.sh; rm -f "$SB/ran"
sees "suites.sh run records test:auth through evidence.sh" "flow-evidence: PASS" "$SU" run
[ "$(ran)" = "auth " ] && ok "auth change → only the auth suite" || bad "ran: $(ran)"
echo x >>src/calc.sh; rm -f "$SB/ran"; "$SU" run >/dev/null 2>&1
[ "$(ran)" = "full " ] && ok "unclaimed src/calc.sh → full suite" || bad "ran: $(ran)"
"$ST" tests unmatched skip >/dev/null; rm -f "$SB/ran"; "$SU" run >/dev/null 2>&1
[ "$(ran)" = "auth " ] && ok "settings.json tests.unmatched skip → auth only" || bad "ran: $(ran)"
"$ST" tests scope full >/dev/null; rm -f "$SB/ran"; "$SU" run >/dev/null 2>&1
[ "$(ran)" = "full " ] && ok "settings.json tests.scope full → full suite" || bad "ran: $(ran)"
rm -f "$FLOW_STACK_HOME/settings.json"; git checkout -q -- .

echo "-- ready.sh runs the impacted suites"
b0="$(git rev-parse HEAD)"; git checkout -qb feat
echo x >>src/billing/b.sh; git commit -qam billing
rm -f "$SB/ran"
sees "a failing impacted suite blocks the stamp" "impacted test suites fail" "$S/review/scripts/ready.sh" --base "$b0"
[ "$(ran)" = "billing " ] && ok "ready.sh ran only billing (vs the base)" || bad "ready ran: $(ran)"
finish
