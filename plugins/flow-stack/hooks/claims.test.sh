#!/usr/bin/env bash
# claims.test.sh: two live Claude sessions on different flow tasks edit the same repo file from two
# worktrees. Runs the working tree's hooks in a throwaway toy repo with a throwaway home.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"; PLUGIN="$(cd "$H/.." && pwd)"
T="$PLUGIN/skills/flow/scripts/task.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
has() { grep -Fq -- "$2" <<<"$1"; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/claims.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
# fake sessions start inside $(...), so their pids go to a file the trap can read
trap 'kill $(cat "$SB/pids" 2>/dev/null) 2>/dev/null; rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID
# session <name>: a live fake Claude session in the registry; prints its pid
session() {
  sleep 600 </dev/null >/dev/null 2>&1 & local p=$!
  echo "$p" >>"$SB/pids"
  jq -n --argjson pid "$p" --arg n "$1" '{pid:$pid, name:$n, sessionId:$n, status:"busy"}' >"$CLAUDE_CONFIG_DIR/sessions/$p.json"
  echo "$p"
}
A="$(session pane-a)"; B="$(session pane-b)"

cd "$SB/repo"
# shellcheck source=/dev/null
. "$PLUGIN/evals/_lib/toy.sh"
toy_repo
export FLOW_SESSION_PID="$A"
toy_task demo "mul multiplies" "no division"
toy_slice demo S1 doing "bash tests/test_add.sh" "src/** tests/**"
git add -A && git commit -qm task
git worktree add -q -b feat-b ../wt-b
WB="$(cd ../wt-b && pwd -P)"
( cd "$WB" && FLOW_SESSION_PID="$B" "$T" new other feature >/dev/null )
printf '# Slices · other\n\n## S3 · x\nstatus: doing\ncheck: true\nfence: src/**\n' >.flow/tasks/other/SLICES.md

# edit <pid> <dir> <event> <file> [session-id]: run the claims hook as Claude Code would; OUT = stdout
edit() {
  OUT="$(jq -nc --arg e "$3" --arg c "$2" --arg f "$2/$4" --arg s "${5:-sess-$1}" \
    '{hook_event_name:$e, session_id:$s, cwd:$c, tool_name:"Edit", tool_input:{file_path:$f, old_string:"a", new_string:"b"}}' |
    FLOW_SESSION_PID="$1" "$H/claims.sh" 2>>"$SB/err.log")" || true
}
both() { edit "$1" "$2" PreToolUse "$3"; local pre="$OUT"; edit "$1" "$2" PostToolUse "$3"; OUT="$pre$OUT"; }

echo "-- the first edit claims the file; the same session edits on freely"
both "$B" "$WB" src/calc.sh
[ -z "$OUT" ] && ok "first edit: silent" || bad "first edit spoke: $OUT"
ls "$SB/repo/.flow/claims/"* >/dev/null 2>&1 && ok "claim recorded in the main checkout's .flow/claims" || bad "no claim file"
both "$B" "$WB" src/calc.sh
[ -z "$OUT" ] && ok "holder's own edits stay silent" || bad "holder warned: $OUT"

echo "-- soft (default): another session's edit is allowed, with one warning naming the holder"
edit "$A" "$SB/repo" PreToolUse src/calc.sh
[ -z "$OUT" ] && ok "soft: nothing denied" || bad "soft pre spoke: $OUT"
edit "$A" "$SB/repo" PostToolUse src/calc.sh
w="$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$OUT" 2>/dev/null)"
has "$w" "src/calc.sh" && has "$w" "pane-b" && has "$w" "other" && has "$w" "S3" && has "$w" "SendMessage" \
  && ok "warning names the file, holder, its task and slice, and SendMessage" || bad "warning: $OUT"
edit "$A" "$SB/repo" PostToolUse src/calc.sh
[ -z "$OUT" ] && ok "warned once per file" || bad "warned twice: $OUT"
both "$A" "$SB/repo" src/calc.sh
[ -z "$OUT" ] && ok "the holder keeps the claim; the warned session isn't re-warned" || bad "re-warned: $OUT"

echo "-- hard: the other session's edit is denied"
printf '{"claims":"hard"}\n' >.flow/config.json
edit "$A" "$SB/repo" PreToolUse src/calc.sh
[ "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$OUT")" = deny ] && has "$OUT" "pane-b" \
  && ok "hard: denied, naming the holder" || bad "hard: $OUT"
edit "$A" "$SB/repo" PreToolUse src/add.sh
[ -z "$OUT" ] && ok "hard: an unclaimed file is free" || bad "hard denied a free file: $OUT"

echo "-- the claim lapses: holder's slice done, stale, holder gone"
sed -i '' 's/^status: doing/status: done/' .flow/tasks/other/SLICES.md
edit "$A" "$SB/repo" PreToolUse src/calc.sh
[ -z "$OUT" ] && ok "holder's slice done: free" || bad "still held after slice done: $OUT"
sed -i '' 's/^status: done/status: doing/' .flow/tasks/other/SLICES.md
both "$B" "$WB" src/calc.sh   # B re-claims (it holds it already; refresh)
f="$(ls "$SB/repo/.flow/claims/"* | head -n1)"
awk -F'\t' 'BEGIN{OFS="\t"} {$6=$6-7200; print}' "$f" >"$f.t" && mv "$f.t" "$f"
edit "$A" "$SB/repo" PreToolUse src/calc.sh
[ -z "$OUT" ] && ok "no edit by the holder for 2h: free" || bad "stale claim held: $OUT"
both "$B" "$WB" src/calc.sh
kill "$B" 2>/dev/null; sleep 0.2
edit "$A" "$SB/repo" PreToolUse src/calc.sh
[ -z "$OUT" ] && ok "holder's session gone: free" || bad "dead holder held: $OUT"
both "$A" "$SB/repo" src/calc.sh
has "$(cat "$f")" "$A" && ok "the next editor takes the claim" || bad "claim not taken: $(cat "$f")"

echo "-- same task (a worker lane) never clashes; off switch; edits outside src"
C="$(session pane-c)"
edit "$C" "$SB/repo" PreToolUse src/calc.sh
[ -z "$OUT" ] || bad "a session with no task of its own was checked: $OUT"
printf '{"claims":"hard","hooks":{"claims":false}}\n' >.flow/config.json
B2="$(session pane-b2)"; printf 'other\n%s\n' "$B2" >"$(git rev-parse --git-common-dir)/worktrees/wt-b/flow-active"
both "$B2" "$WB" src/calc.sh
[ -z "$OUT" ] && ok "hooks.claims: false: nothing checked" || bad "off switch ignored: $OUT"
printf '{"claims":"hard"}\n' >.flow/config.json
edit "$A" "$SB/repo" PreToolUse .flow/tasks/demo/NOTES.md
[ -z "$OUT" ] && ok ".flow bookkeeping is never claimed" || bad ".flow claimed: $OUT"

if [ "$FAILS" -eq 0 ]; then echo "== claims · PASS"; exit 0; fi
echo "== claims · FAIL ($FAILS)"; exit 1
