#!/usr/bin/env bash
# claims.stop: the Stop hook sends the agent back once when its last message claims
# success and no check passed after its last code edit (read from the transcript, with
# or without a task); notify.sh reaches the human.
. "$(dirname "$0")/lib.sh"; sandbox claims.stop
toy_task demo "mul multiplies" "no division"
TR="$SB/transcript.jsonl"
fresh() { : >"$TR"; }
edit() { jq -nc --arg f "$1" '{type:"assistant", message:{content:[{type:"tool_use", name:"Edit", input:{file_path:$f}}]}}' >>"$TR"; }
shell() { jq -nc --arg c "$1" '{type:"assistant", message:{content:[{type:"tool_use", name:"Bash", input:{command:$c}}]}}' >>"$TR"; }
N=0
ran() { # ran "<command>" "<output>": a Bash call and its result, paired by id
  N=$((N + 1))
  jq -nc --arg c "$1" --arg id "t$N" '{type:"assistant", message:{content:[{type:"tool_use", id:$id, name:"Bash", input:{command:$c}}]}}' >>"$TR"
  jq -nc --arg t "$2" --arg id "t$N" '{type:"user", message:{content:[{type:"tool_result", tool_use_id:$id, content:[{type:"text", text:$t}]}]}}' >>"$TR"
}
EV_RUN="plugins/flow-stack/skills/verify/scripts/evidence.sh C1"
say() { jq -nc --arg t "$1" '{type:"assistant", message:{content:[{type:"text", text:$t}]}}' >>"$TR"; }
stop() { jq -nc --arg cwd "$PWD" --arg tp "$TR" --argjson a "${1:-false}" '{cwd:$cwd, hook_event_name:"Stop", transcript_path:$tp, stop_hook_active:$a}'; }

fresh; edit "$PWD/src/calc.sh"; say "All done, the tests pass."
expect stop.sh "$(stop)" block "success claim, no evidence"
has "$OUT" "flow claims check" && ok "reason is the claims check" || bad "reason: $OUT"
expect stop.sh "$(stop true)" allow "second stop (stop_hook_active) is let through"
fresh; edit "$PWD/src/calc.sh"; say "Done. ~ assumed: did not run the mul test."
expect stop.sh "$(stop)" allow "claim tagged ~ assumed"
fresh; edit "$PWD/src/calc.sh"; say "I read the parser; here is its layout."
expect stop.sh "$(stop)" allow "no success claim"
fresh; edit "$PWD/src/calc.sh"; ran "$EV_RUN" "ok mul
flow-evidence: PASS"; say "Fixed, all checks pass."
expect stop.sh "$(stop)" allow "claim backed by a PASS after the last edit"
fresh; ran "$EV_RUN" "flow-evidence: PASS"; edit "$PWD/src/calc.sh"; say "Fixed."
expect stop.sh "$(stop)" block "edit after the last PASS"
fresh; edit "$PWD/src/calc.sh"; ran "$EV_RUN" "flow-evidence: FAIL sig=abc"; say "Fixed."
expect stop.sh "$(stop)" block "only a FAIL after the edit"
fresh; edit "$PWD/src/calc.sh"; ran "$EV_RUN" "flow-evidence: PASS
== scenario · FAIL (2 assertion(s))"; say "Fixed."
expect stop.sh "$(stop)" block "an inner PASS inside a failing run"
fresh; edit "$PWD/src/calc.sh"; ran "echo flow-evidence: PASS" "flow-evidence: PASS"; say "Fixed."
expect stop.sh "$(stop)" block "an echoed verdict isn't a check"
fresh; edit "$PWD/src/calc.sh"; printf '{"type":"assistant","message":{"content":[{"ty\n' >>"$TR"; say "Fixed."
expect stop.sh "$(stop)" block "a malformed transcript line doesn't switch the check off"
fresh; edit "$PWD/src/calc.sh"; ran "skills/review/scripts/ready.sh" "ready for review: a156dc5 stamped"; say "Ready to merge."
expect stop.sh "$(stop)" allow "ready stamp counts as a check"
fresh; edit "$PWD/src/calc.sh"; ran "$EV_RUN" "flow-evidence: PASS
Shell cwd was reset to /somewhere"; say "Fixed."
expect stop.sh "$(stop)" allow "a PASS followed by the harness's cwd-reset line"

fresh; edit "$PWD/src/calc.sh"; ran "plugins/flow-stack/skills/verify/scripts/evidence.sh smoke 'ls'" "flow-evidence: PASS"; say "Fixed."
expect stop.sh "$(stop)" block "in a task, a free-label run isn't the declared check"
fresh; edit "$PWD/src/calc.sh"; ran "skills/feature-map/scripts/features.sh run calc.add" "flow-evidence: PASS"; say "Fixed."
expect stop.sh "$(stop)" block "in a task, one hand-picked feature isn't the check"
fresh; edit "$PWD/src/calc.sh"; ran "skills/feature-map/scripts/features.sh run --impacted" "flow-evidence: PASS"; say "Fixed."
expect stop.sh "$(stop)" allow "in a task, impacted features count"
fresh; edit "$PWD/src/calc.sh"; ran 'E=plugins/flow-stack/skills/verify/scripts/evidence.sh; $E C1 2>&1 | tail -1' "flow-evidence: PASS"; say "Fixed."
expect stop.sh "$(stop)" allow "in a task, C1 run through a variable counts"

echo "-- what counts as a code edit"
fresh; edit "$PWD/README.md"; say "Done."
expect stop.sh "$(stop)" allow "doc-only edit"
fresh; edit "$PWD/.flow/tasks/demo/INTENT.md"; edit "/private/tmp/x/scratch.sh"; say "Done."
expect stop.sh "$(stop)" allow ".flow and temp edits"
fresh; shell "cat > src/calc.sh <<'EOF'
add() { :; }
EOF"; say "Fixed."
expect stop.sh "$(stop)" block "heredoc write via Bash"
fresh; shell "sed -i '' 's/a/b/' src/calc.sh"; say "Fixed."
expect stop.sh "$(stop)" block "sed -i via Bash"
fresh; shell "echo x>src/a.sh"; say "Fixed."
expect stop.sh "$(stop)" block "redirect without a space"
fresh; shell "sed -Ei '' 's/a/b/' src/calc.sh"; say "Fixed."
expect stop.sh "$(stop)" block "sed -Ei via Bash"
for c in "cp /tmp/new.sh src/calc.sh" "mv src/a.sh src/b.sh" "git apply fix.diff" "patch -p1 < fix.diff"; do
  fresh; shell "$c"; say "Fixed."
  expect stop.sh "$(stop)" block "writes via: $c"
done
mkdir -p "$SB/other/src"; printf 'other\t%s\n' "$SB/other" >.flow/tasks/demo/REPOS
fresh; edit "$SB/other/src/x.js"; say "Fixed."
expect stop.sh "$(stop)" block "an edit in the task's other repo"
rm -f .flow/tasks/demo/REPOS
fresh; shell "ls | tee /tmp/log.txt; git commit -qm 'a > b'"; say "Done."
expect stop.sh "$(stop)" allow "tee to /tmp and > inside a quoted message"
for c in "cp out.log /tmp/out.log" "npm version patch --no-git-tag-version" "git apply --check x.diff"; do
  fresh; ran "$EV_RUN" "flow-evidence: PASS"; shell "$c"; say "Done."
  expect stop.sh "$(stop)" allow "not a code write: $c"
done
fresh; ran "$EV_RUN" "flow-evidence: PASS"; shell "cat > \"\$TMPDIR/prbody.md\" <<'EOF'
body
EOF
gh pr edit 1 --body-file \"\$TMPDIR/prbody.md\""; say "Done."
expect stop.sh "$(stop)" allow "heredoc into a quoted \$TMPDIR file"
fresh; shell "D=.flow/tasks/x; cat > \$D/INTENT.md <<'EOF'
plan
EOF"; say "Done."
expect stop.sh "$(stop)" allow "a .flow path behind a variable"
fresh; shell "D=.flow/tasks/x
python3 - \"\$D\" <<'EOF'
print(\"lead of X\") if a > b else None
EOF"; say "Done."
expect stop.sh "$(stop)" allow "a heredoc body isn't shell"
fresh; shell "cat > src/a.sh <<'EOF'
x
EOF"; say "Done."
expect stop.sh "$(stop)" block "a heredoc into a code file"
fresh; shell "D=src; cat > \$D/a.sh"; say "Done."
expect stop.sh "$(stop)" block "a variable that points at code"
fresh; shell "bash <<EOF
echo x > src/a.py
EOF"; say "Done."
expect stop.sh "$(stop)" block "a heredoc a shell runs is shell"
fresh; shell "sh -s <<'X'
sed -i s/a/b/ src/a.py
X"; say "Done."
expect stop.sh "$(stop)" block "sh -s heredoc with sed -i"
fresh; shell "cat <<EOF | bash
echo x > src/a.py
EOF"; say "Done."
expect stop.sh "$(stop)" block "a heredoc piped into a shell"
fresh; shell "/bin/bash <<EOF
echo x > src/a.py
EOF"; say "Done."
expect stop.sh "$(stop)" block "a shell named by path runs its heredoc"
fresh; shell "git commit -qF - <<EOF
fix: bash > src/a.py was wrong
EOF"; say "Done."
expect stop.sh "$(stop)" allow "a commit message heredoc isn't shell"
fresh; shell "F=a.md; echo x > \$F; F=src/a.py; echo y > \$F"; say "Done."
expect stop.sh "$(stop)" block "a reassigned variable isn't expanded"
for c in "cd /tmp; cd - >/dev/null; sed -i '' s/a/b/ src/calc.sh" "cd /tmp && cd \"\$OLDPWD\" && echo x > src/a.sh" "echo x > \$TMPDIR/../repo/src/a.sh" "echo x > .flow/../src/a.sh" "cp a /tmp/../repo/src/b.sh"; do
  fresh; ran "$EV_RUN" "flow-evidence: PASS"; shell "$c"; say "Done."
  expect stop.sh "$(stop)" block "a write back into this repo still counts: $c"
done
fresh; ran "$EV_RUN" "flow-evidence: PASS"; shell "cd src && sed -i '' 's/a/b/' calc.sh"; say "Done."
expect stop.sh "$(stop)" block "an edit after cd inside this repo"
fresh; ran "$EV_RUN" "flow-evidence: PASS"; shell "cd $PWD/src && sed -i '' 's/a/b/' calc.sh"; say "Done."
expect stop.sh "$(stop)" block "an edit after cd to an absolute path inside this repo"
fresh; edit "$PWD/src/calc.sh"; say "Fixed."
expect stop.sh "$(stop)" block "in a task, the reason names the checks that count"
has "$OUT" "evidence.sh C<n>" && has "$OUT" "ready.sh" && ! has "$OUT" "smoke" && ok "in-task reason: C/S, features, ready.sh; no smoke" || bad "in-task reason: $OUT"
fresh; shell "git status >/dev/null 2>&1 && ls 2>&1 | head; echo x >> .flow/tasks/demo/notes.md"; say "Done."
expect stop.sh "$(stop)" allow "Bash with only null, fd, and .flow redirects"

echo "-- outside a task"
"$S/flow/scripts/task.sh" close >/dev/null 2>&1 || rm -f .flow/ACTIVE
fresh; edit "$PWD/src/calc.sh"; say "Fixed, it works now."
expect stop.sh "$(stop)" block "no active task: unverified claim still sent back"
has "$OUT" "smoke" && ok "outside a task, the reason offers smoke" || bad "no-task reason: $OUT"
fresh; edit "$PWD/src/calc.sh"; ran "$EV_RUN" "flow-evidence: PASS"; say "Fixed, it works now."
expect stop.sh "$(stop)" allow "no active task: claim after a PASS"
fresh; edit "$PWD/src/calc.sh"; ran "plugins/flow-stack/skills/verify/scripts/evidence.sh smoke 'bash tests/test_add.sh'" "flow-evidence: PASS"; say "Fixed."
expect stop.sh "$(stop)" allow "no active task: a free-label run counts"

jq '.hooks.claims=false' .flow/config.json >c && mv c .flow/config.json
fresh; edit "$PWD/src/calc.sh"; say "Fixed."
expect stop.sh "$(stop)" allow "claims off"

echo "-- notify.sh (ntfy to a local capture server)"
PORT=$((20000 + RANDOM % 20000)); GOT="$SB/ntfy.txt"
python3 - "$PORT" "$GOT" <<'PY' &
import sys, http.server
port, out = int(sys.argv[1]), sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        open(out, 'a').write(self.path + ' ' + self.rfile.read(n).decode() + '\n')
        self.send_response(200); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', port), H).serve_forever()
PY
SRV=$!; trap 'kill $SRV 2>/dev/null; wait $SRV 2>/dev/null || true; rm -rf "$SB"' EXIT
sleep 0.5
"$S/profile/scripts/init.sh" none >/dev/null
perl -pi -e 's/^notify: \S+/notify: ntfy:flowtest/' "$FLOW_STACK_HOME/profile.md"
printf '{"message":"Claude needs your permission"}' | NTFY_SERVER="http://127.0.0.1:$PORT" "$H/notify.sh"
NTFY_SERVER="http://127.0.0.1:$PORT" "$H/notify.sh" "direct message"
sleep 0.3
grep -q '^/flowtest Claude needs your permission$' "$GOT" 2>/dev/null && ok "Notification event → ntfy topic" || bad "ntfy got: $(cat "$GOT" 2>/dev/null)"
grep -q '^/flowtest direct message$' "$GOT" 2>/dev/null && ok "direct message → ntfy" || bad "no direct message"
perl -pi -e 's/^notify: \S+/notify: off/' "$FLOW_STACK_HOME/profile.md"
n="$(wc -l <"$GOT")"; NTFY_SERVER="http://127.0.0.1:$PORT" "$H/notify.sh" "should not arrive"; sleep 0.3
[ "$(wc -l <"$GOT")" = "$n" ] && ok "notify: off → nothing sent" || bad "sent while off"
cp "$GOT" "$ART/ntfy.txt"
finish
