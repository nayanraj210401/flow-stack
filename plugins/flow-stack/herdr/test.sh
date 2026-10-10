#!/usr/bin/env bash
# test.sh [data] [host] [plugin]  (none = all): the herdr plugin and the flow-stack pieces it reads,
# in a throwaway toy repo with a throwaway FLOW_STACK_HOME and Claude config dir, herdr stubbed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
T="$PLUGIN/skills/flow/scripts/task.sh"; ST="$PLUGIN/skills/flow/scripts/status.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
has() { grep -Fq -- "$2" <<<"$1"; }
SECTIONS=("$@")
on() { [ ${#SECTIONS[@]} -eq 0 ] && return 0; local s; for s in "${SECTIONS[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/herdr-board.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
OWNERS=()
cleanup() { [ ${#OWNERS[@]} -eq 0 ] || kill "${OWNERS[@]}" 2>/dev/null; rm -rf "$SB"; }
trap cleanup EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
unset HERDR_ENV HERDR_PANE_ID HERDR_SOCKET_PATH HERDR_BIN_PATH ORCA_PANE_KEY CMUX_WORKSPACE_ID
export FLOW_SESSION_PID=""  # outside Claude: the human's view, every task visible
cd "$SB/repo"
# shellcheck source=/dev/null
. "$PLUGIN/evals/_lib/toy.sh"
toy_repo
toy_task demo "mul multiplies" "no division"
toy_slice demo S1 doing "bash tests/test_mul.sh" "src/**"
git add -A && git commit -qm task

# session <name> <session-id>: a live fake Claude session in the registry; prints its pid
session() {
  sleep 600 >/dev/null 2>&1 & local p=$!
  OWNERS+=("$p")
  jq -n --argjson pid "$p" --arg n "$1" --arg s "$2" '{pid:$pid, name:$n, sessionId:$s, status:"idle"}' >"$CLAUDE_CONFIG_DIR/sessions/$p.json"
  echo "$p"
}

if on data; then
  echo "-- data: status.sh names the live owner of the checkout's task"
  pid="$(session flow-demo-1 sess-1)"
  printf 'demo\n%s\n' "$pid" >.flow/ACTIVE
  out="$("$ST" --full "$PWD")"
  [ "$(jq -r .owner <<<"$out")" = "$pid" ] && ok "owner is the live session's pid" || bad "owner: $(jq -c '{task,owner}' <<<"$out")"
  printf 'demo\n%s\n' 999999 >.flow/ACTIVE
  [ "$("$ST" --full "$PWD" | jq -r .owner)" = "" ] && ok "a dead owner reads as none" || bad "dead owner shown"

  echo "-- data: a gate is decided with a choice and a note"
  cat >.flow/tasks/demo/GATES.md <<'EOF'
GATE · push the branch?
  options: A) push now  B) hold   (recommend: A, because CI is green)
  evidence: EVIDENCE.md C1

GATE · open the PR as draft?
  options: A) draft  B) ready
EOF
  q="push the branch?"
  o="$("$T" gate 1 approve "$q" "B) hold" "wait for the review" 2>&1)"
  line="$(grep '^  decided: ' .flow/tasks/demo/GATES.md | head -n1)"
  has "$line" "decided: human approve" && has "$line" "choice: B) hold" && has "$line" "note: wait for the review" \
    && ok "decided line carries choice and note" || bad "decided: $line ($o)"
  has "$(tail -n1 .flow/tasks/demo/DECISIONS.tsv)" "B) hold" && ok "DECISIONS.tsv logs the choice" || bad "decisions: $(tail -n1 .flow/tasks/demo/DECISIONS.tsv)"
  [ "$("$ST" --full "$PWD" | jq '.gates | length')" = 1 ] && ok "the decided gate leaves the open list" || bad "gates: $("$ST" --full "$PWD" | jq -c .gates)"
  "$T" gate 2 reject "open the PR as draft?" >/dev/null 2>&1 && has "$(grep -c '^  decided: human reject' .flow/tasks/demo/GATES.md)" 1 \
    && ok "choice and note stay optional" || bad "plain reject failed"
  bad_note="$(printf 'x\033[31mred\nnext')"
  printf 'GATE · third?\n  options: A) yes\n' >>.flow/tasks/demo/GATES.md
  "$T" gate 3 approve "third?" "A) yes" "$bad_note" >/dev/null 2>&1
  l3="$(grep '^  decided: ' .flow/tasks/demo/GATES.md | tail -n1)"
  ! grep -q $'\033' .flow/tasks/demo/GATES.md && [ "$(grep -c '^GATE · ' .flow/tasks/demo/GATES.md)" = 3 ] && has "$l3" "note: x[31mred next" \
    && ok "a note's control characters and newlines are stripped" || bad "note leaked: $l3"
  rm -f .flow/tasks/demo/GATES.md
fi

if on host; then
  BIN="$SB/bin"; LOG="$SB/host.log"; mkdir -p "$BIN"; : >"$LOG"; : >"$SB/name"
  # herdr stub: logs each call; `agent get` answers with the name in $SB/name, `agent rename` sets it
  cat >"$BIN/herdr" <<EOF
#!/usr/bin/env bash
printf '%s\n' "herdr \$*" >>"$LOG"
case "\$1 \$2" in
  "agent get") jq -nc --arg n "\$(cat "$SB/name")" '{result:{agent:(if \$n == "" then {} else {name:\$n} end)}}' ;;
  "agent rename") if [ "\$4" = --clear ]; then : >"$SB/name"; else printf '%s' "\$4" >"$SB/name"; fi ;;
esac
EOF
  chmod +x "$BIN/herdr"
  python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$SB/herdr.sock"
  export HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HERDR_SOCKET_PATH="$SB/herdr.sock" HERDR_BIN_PATH="$BIN/herdr"
  printf 'demo\n\n' >.flow/ACTIVE
  ev() { jq -nc --arg e "$1" --arg c "$PWD" '{hook_event_name:$e, session_id:"sess-h", cwd:$c, prompt:"go"}'; }
  push() { printf '%s' "$(ev "$1")" | "$PLUGIN/hooks/host.sh" >/dev/null 2>&1; }
  waitfor() { local i; for i in $(seq 1 30); do grep -Fq -- "$1" "$LOG" && return 0; sleep 0.1; done; return 1; }
  quiet() { sleep 1.5; }

  echo "-- host: an unnamed agent row takes the task's name"
  push UserPromptSubmit
  waitfor "agent rename w1:p1 demo" && ok "renamed to the task" || bad "no rename: $(cat "$LOG")"
  waitfor "report-metadata" && has "$(grep report-metadata "$LOG" | tail -n1)" "--clear-token flow_gates" \
    && ok "no open gate: no gate mark" || bad "gate mark with no gate: $(grep report-metadata "$LOG" | tail -n1)"
  grep -q 'notification show' "$LOG" && bad "toast with no gate" || ok "no gate, no toast"

  echo "-- host: a new gate toasts once and marks the row"
  printf 'GATE · ship it?\n  options: A) yes  B) no\n' >.flow/tasks/demo/GATES.md
  push UserPromptSubmit
  waitfor "notification show" && has "$(grep 'notification show' "$LOG")" "ship it?" && has "$(grep 'notification show' "$LOG")" "--sound request" \
    && ok "toast names the gate, with the request sound" || bad "toast: $(grep notification "$LOG")"
  has "$(grep report-metadata "$LOG" | tail -n1)" "flow_gates=⚑1" && ok "row marked ⚑1" || bad "mark: $(grep report-metadata "$LOG" | tail -n1)"
  touch .flow/tasks/demo/SLICES.md; push UserPromptSubmit; quiet
  [ "$(grep -c 'notification show' "$LOG")" = 1 ] && ok "same gate: no second toast" || bad "toasted again"

  echo "-- host: a name someone else set is kept"
  printf 'my-own' >"$SB/name"
  printf '## S2 · y\nstatus: todo\ncheck: true\nfence: src/**\n' >>.flow/tasks/demo/SLICES.md
  push UserPromptSubmit; quiet
  [ "$(cat "$SB/name")" = my-own ] && ok "the human's name survives a push" || bad "overwrote the human's name: $(cat "$SB/name")"

  echo "-- host: session end clears only the name flow set"
  push SessionEnd; quiet
  [ "$(cat "$SB/name")" = my-own ] && ok "the human's name survives the session end" || bad "cleared the human's name"
  : >"$SB/name"; push UserPromptSubmit; waitfor "agent rename w1:p1 demo" || true; quiet
  push SessionEnd
  waitfor "agent rename w1:p1 --clear" && ok "flow's own name is cleared at session end" || bad "name left: $(cat "$SB/name")"

  echo "-- host: a resumed session in the same pane neither re-toasts nor loses flow's name"
  : >"$SB/name"; : >"$LOG"; rm -f "$FLOW_STACK_HOME"/hosts/pane-*
  printf 'GATE · ship it?\n  options: A) yes  B) no\n' >.flow/tasks/demo/GATES.md
  push UserPromptSubmit; waitfor "notification show" || true; waitfor "agent rename w1:p1 demo" || true; quiet
  ev() { jq -nc --arg e "$1" --arg c "$PWD" '{hook_event_name:$e, session_id:"sess-h2", cwd:$c, prompt:"go", source:"resume"}'; }
  push SessionStart; quiet
  [ "$(grep -c 'notification show' "$LOG")" = 1 ] && ok "no second toast for the same gate after a resume" || bad "re-toasted on resume"
  printf '\nGATE · tag it?\n' >>.flow/tasks/demo/GATES.md
  push UserPromptSubmit; quiet
  has "$(grep 'notification show' "$LOG" | tail -n1)" "tag it?" && ok "a new gate toasts after the resume" || bad "new gate not toasted: $(grep notification "$LOG")"
  push SessionEnd
  waitfor "agent rename w1:p1 --clear" && ok "the resumed session clears flow's name" || bad "name left after resume: $(cat "$SB/name")"

  echo "-- host: herdr unreadable → the name is left alone"
  printf 'my-own' >"$SB/name"
  mv "$BIN/herdr" "$BIN/herdr.ok"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "herdr $*" >>"%s"\ncase "$1 $2" in "agent get") exit 1 ;; "agent rename") printf "%%s" "$3" >"%s" ;; esac\n' "$LOG" "$SB/name" >"$BIN/herdr"; chmod +x "$BIN/herdr"
  printf '## S3 · z\nstatus: todo\ncheck: true\nfence: src/**\n' >>.flow/tasks/demo/SLICES.md
  push UserPromptSubmit; quiet
  [ "$(cat "$SB/name")" = my-own ] && ok "a failed agent get renames nothing" || bad "renamed on a failed read: $(cat "$SB/name")"
  mv "$BIN/herdr.ok" "$BIN/herdr"
  unset HERDR_ENV HERDR_PANE_ID HERDR_SOCKET_PATH HERDR_BIN_PATH
  rm -f .flow/tasks/demo/GATES.md
fi

if on plugin; then
  echo "-- plugin: unit and UI tests, types"
  [ -d "$HERE/node_modules" ] || (cd "$HERE" && bun install >/dev/null 2>&1)
  (cd "$HERE" && bun test >"$SB/bun.log" 2>&1) && ok "bun test: $(grep -Eo '[0-9]+ pass' "$SB/bun.log")" || bad "bun test: $(tail -n 15 "$SB/bun.log")"
  (cd "$HERE" && ./node_modules/.bin/tsc --noEmit -p . >"$SB/tsc.log" 2>&1) && ok "types check" || bad "tsc: $(head -n 10 "$SB/tsc.log")"

  echo "-- plugin: the board reads the real status.sh, and a decision reaches GATES.md and the pane"
  BIN="$SB/pbin"; LOG="$SB/plugin.log"; mkdir -p "$BIN"; : >"$LOG"
  pid="$(session flow-demo-1 sess-p1)"; other="$(session flow-demo-2 sess-p2)"
  # a crashed session's row with the same id stays in the registry; it must not win
  jq -n '{pid:999999, name:"stale", sessionId:"sess-p1"}' >"$CLAUDE_CONFIG_DIR/sessions/999999.json"
  printf 'demo\n%s\n' "$pid" >.flow/ACTIVE
  printf 'GATE · push the branch?\n  options: A) push now  B) hold   (recommend: A, because green)\n' >.flow/tasks/demo/GATES.md
  cat >"$BIN/herdr" <<EOF
#!/usr/bin/env bash
printf '%s\n' "herdr \$*" >>"$LOG"
[ "\$1 \$2" = "agent get" ] && jq -nc --arg s "\$(cat "$SB/state" 2>/dev/null || echo idle)" '{result:{agent:{agent_status:\$s}}}'
[ "\$1 \$2" = "agent list" ] && jq -nc --arg c "$PWD" '{result:{agents:[
  {pane_id:"w1:p1", agent:"claude", agent_status:"idle", cwd:\$c, focused:true, agent_session:{value:"sess-p1"}},
  {pane_id:"w1:p2", agent:"claude", agent_status:"working", cwd:\$c, focused:false, agent_session:{value:"sess-p2"}}]}}'
exit 0
EOF
  chmod +x "$BIN/herdr"
  out="$(cd "$HERE" && HERDR_BIN_PATH="$BIN/herdr" bun -e '
    import { load, decide } from "./src/herdr"
    const rows = load()
    const own = rows.find(r => r.pane === "w1:p1"), other = rows.find(r => r.pane === "w1:p2")
    console.log(JSON.stringify({ own: own?.task?.task, gates: own?.task?.gates?.length, other: other?.task, session: own?.session }))
    console.log(decide(own, 1, "push the branch?", "approve", "A) push now", "ship it"))' 2>&1)"
  has "$out" '"own":"demo"' && has "$out" '"gates":1' && has "$out" '"other":null' && has "$out" '"session":"flow-demo-1"' \
    && ok "the owner's pane shows the task and its gate; the other pane none" || bad "load: $out"
  has "$(grep '^  decided: ' .flow/tasks/demo/GATES.md)" "choice: A) push now · note: ship it" && ok "the decision is in GATES.md" || bad "gates: $(cat .flow/tasks/demo/GATES.md) / $out"
  p="$(grep 'agent prompt' "$LOG")"
  has "$p" "agent prompt w1:p1 The human approved gate 1" && ! has "$p" "push the branch" \
    && ok "the owner's pane is told, without the gate's repo text" || bad "prompt: $p"

  echo "-- plugin: a blocked pane is not typed into (it may be at a permission prompt)"
  printf '\nGATE · tag it?\n' >>.flow/tasks/demo/GATES.md
  echo blocked >"$SB/state"; : >"$LOG"
  out="$(cd "$HERE" && HERDR_BIN_PATH="$BIN/herdr" bun -e '
    import { load, decide } from "./src/herdr"
    const own = load().find(r => r.pane === "w1:p1")
    console.log(decide(own, 2, "tag it?", "reject", "", ""))' 2>&1)"
  grep -q 'agent prompt' "$LOG" && bad "typed into a blocked pane: $(grep 'agent prompt' "$LOG")" || ok "no prompt sent to a blocked pane"
  has "$out" "not told" && ok "the answer says the pane wasn't told" || bad "result: $out"
  grep -q '^  decided: human reject' .flow/tasks/demo/GATES.md && ok "the decision is still recorded" || bad "not recorded"
  rm -f "$SB/state"
  rm -f .flow/tasks/demo/GATES.md
fi

if [ "$FAILS" -eq 0 ]; then echo "== herdr · PASS"; exit 0; fi
echo "== herdr · FAIL ($FAILS)"; exit 1
