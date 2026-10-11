#!/usr/bin/env bash
# command-start.test.sh: in --auto mode the guard must treat push/PR/publish as commands behind
# env prefixes, global options, if/then and `!`, and must not treat text that mentions them as one.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"; PLUGIN="$(cd "$H/.." && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/command-start.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR" "$SB/repo"
cd "$SB/repo"
# shellcheck source=/dev/null
. "$PLUGIN/evals/_lib/toy.sh"
toy_repo
jq -nc --arg cwd "$PWD" '{cwd:$cwd, session_id:"A", hook_event_name:"UserPromptSubmit", prompt:"go --auto"}' | "$H/anchor.sh" >/dev/null 2>&1

decide() { # decide <command>: the guard's decision in the --auto session
  local out
  out="$(jq -nc --arg cwd "$PWD" --arg c "$1" '{cwd:$cwd, session_id:"A", hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}}' |
    "$H/guard.sh" 2>/dev/null)" || true
  [ -n "$out" ] || { echo allow; return; }
  jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out"
}
want() { # want <allow|deny> <command>
  local d; d="$(decide "$2")"
  if [ "$d" = "$1" ]; then ok "$1: $2"; else bad "$2 → $d, want $1"; fi
}

echo "-- outward commands behind a prefix still wait"
for c in "git push origin feat" "FOO=1 git push origin feat" "FOO=1 BAR=2 gh pr create --title x" "git -C . push origin feat" \
         "git -c k=v push origin feat" "gh -R a/b pr create --title x" "gh --repo a/b pr merge 3" "npm --prefix x publish" \
         "FOO=1 npm publish" "if true; then git push origin feat; fi" "! git push origin feat" \
         "if true; then git push; fi" "git push;" "(git push)" "git push|cat" "npm publish; echo" "gh pr create;" "(gh pr create)" \
         "gh pr ready; true" "FOO='a b' gh pr create --title x" 'FOO="a b" git push origin feat'; do
  want deny "$c"
done

echo "-- text that only mentions them, and other subcommands, run"
for c in 'echo "git push"' "grep 'gh pr create' file" "echo FOO=1 git push" "git -C . status" "FOO=1 git status" "npm --prefix x test"; do
  want allow "$c"
done

[ "$FAILS" -eq 0 ] && { echo "command-start: PASS"; exit 0; }
echo "command-start: FAIL ($FAILS)"; exit 1
