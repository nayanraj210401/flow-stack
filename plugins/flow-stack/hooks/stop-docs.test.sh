#!/usr/bin/env bash
# stop-docs.test.sh: the claims check counts shell writes as code edits only when the Edit tool would.
# Docs (.md/.txt) written by mv, cp or sed -i don't need fresh evidence; code written that way still does.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/stop-docs.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"; trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude"
mkdir -p "$FLOW_STACK_HOME" "$SB/repo" && cd "$SB/repo" && git init -q

# transcript: one Bash call, then a reply claiming success
run() { # run <command> → block|allow
  local t="$SB/t.jsonl"
  jq -nc --arg c "$1" '{type:"assistant",message:{content:[{type:"tool_use",id:"t1",name:"Bash",input:{command:$c}}]}}' >"$t"
  jq -nc '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"t1",content:"ok"}]}}' >>"$t"
  jq -nc '{type:"assistant",message:{content:[{type:"text",text:"PR #12 is ready to merge."}]}}' >>"$t"
  local out; out="$(jq -nc --arg t "$t" --arg c "$PWD" '{hook_event_name:"Stop",session_id:"s",cwd:$c,transcript_path:$t}' | "$H/stop.sh")"
  jq -e '.decision == "block"' <<<"$out" >/dev/null 2>&1 && echo block || echo allow
}
is() { local got; got="$(run "$2")"; [ "$got" = "$1" ] && ok "$1: $2" || bad "$2 → $got, want $1"; }

is allow 'cat notes.md.new > /dev/null; mv notes.md.new notes.md'
is allow 'cp draft.txt README.txt'
is allow "sed -i '' 's/a/b/' docs/SKILL.md"
is allow "perl -pi -e 's/a/b/' CHANGELOG.md"
is block 'mv build.sh.new build.sh'
is block 'mv build.sh notes.md'
is block 'mv src/app.sh src/lib.sh docs/x.md'
is allow 'mv a.md b.md'
is block "sed -i '' 's/a/b/' \"src/app.sh\" notes.md"
is allow 'cp "src/app.sh" notes.md'
is block "sed -i '' 's/a/b/' \"Makefile\" notes.md"
is block "sed -i '' 's/a/b/' 'bin/run' notes.md"
is block 'mv "build.sh" notes.md'
is allow 'mv ".flow/ready.tsv.new" ".flow/ready.tsv"'
is allow 'mv "notes.md.new" "notes.md"'
is block 'mv "src/tmp/app.sh" notes.md'
is block "perl -i -pe 's/a/b/' \"src/scratchpad.ts\""
is allow "sed -i '' 's/a/b/' \"notes.md\""
is block "sed -i '' 's/a/b/' src/app.sh"
is block "sed -i '' 's/a/b/' README.md src/app.sh"

[ "$FAILS" -eq 0 ] && echo "== stop-docs · PASS" || { echo "== stop-docs · FAIL ($FAILS)"; exit 1; }
