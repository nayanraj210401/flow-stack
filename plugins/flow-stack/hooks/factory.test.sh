#!/usr/bin/env bash
# factory.test.sh: `--auto ship` and `--gha` in a repo without a committed verify driver and feature map warn
# (default) or drop to plain --auto (factory_ready: enforce). make-routines refuses self-heal and auto-merge there.
# Pair mode replays with the same decisions as the base commit's hooks.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
R="$H/../skills/make-routines/scripts/routines.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/factory.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID GITHUB_ACTIONS GITHUB_RUN_ID RUNNER_ENVIRONMENT RUNNER_TEMP
cd "$SB/repo" && git init -q -b main && git config user.email a@b && git config user.name a
mkdir -p .flow/tasks/x; echo x >.flow/ACTIVE
printf '# Intent\n## Goal\ng\n' >.flow/tasks/x/INTENT.md
git add -A && git commit -qm i && git checkout -qb feat/x

prompt() { jq -nc --arg c "$PWD" --arg p "$1" '{hook_event_name:"UserPromptSubmit",session_id:"s",cwd:$c,prompt:$p}' | "${2:-$H}/anchor.sh"; }
decide() { # decide <command> [hooks dir]
  local out; out="$(jq -nc --arg c "$PWD" --arg cmd "$1" '{hook_event_name:"PreToolUse",session_id:"s",cwd:$c,tool_name:"Bash",tool_input:{command:$cmd}}' | "${2:-$H}/guard.sh")"
  [ -n "$out" ] || { echo allow; return; }
  jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out"
}
flag() { cat "$FLOW_STACK_HOME/auto/s" 2>/dev/null; }
stamp() { printf 't\t%s\tready\tpass\t\n' "$(git rev-parse HEAD)" >>.flow/ready.tsv; }
profile() { printf -- '---\nprofile_version: 1\nfactory_ready: %s\n---\n' "$1" >"$FLOW_STACK_HOME/profile.md"; }

echo "-- not ready, warn (no profile key): the message, and shipping still works"
out="$(prompt 'ship it --auto ship')"
grep -q 'factory not ready' <<<"$out" && grep -q 'make-verifier' <<<"$out" && grep -q 'feature-map' <<<"$out" \
  && ok "warns and names both fixes" || bad "no warning: $out"
[ "$(flag)" = ship ] && ok "flag stays ship" || bad "flag '$(flag)'"
stamp; [ "$(decide 'git push origin feat/x')" = allow ] && ok "stamped push allowed" || bad "push not allowed"
prompt '--no-auto' >/dev/null

echo "-- not ready, enforce: plain --auto"
profile enforce
out="$(prompt 'ship it --auto ship')"
grep -q 'factory not ready' <<<"$out" && grep -q 'plain --auto' <<<"$out" && ok "says it downgraded" || bad "no downgrade message: $out"
[ -f "$FLOW_STACK_HOME/auto/s" ] && [ -z "$(flag)" ] && ok "flag is plain auto" || bad "flag '$(flag)'"
[ "$(decide 'git push origin feat/x')" = deny ] && ok "stamped push waits" || bad "push not denied"
prompt '--no-auto' >/dev/null

echo "-- on disk but not committed is not ready"
mkdir -p .claude/skills/verify-toy .flow/features
echo '# verify' >.claude/skills/verify-toy/SKILL.md
printf -- '---\nid: toy\nscenario: bash verify.sh\n---\n' >.flow/features/toy.md
out="$(prompt '--auto ship')"; grep -q 'factory not ready' <<<"$out" && ok "uncommitted driver + map: not ready" || bad "counted as ready: $out"
prompt '--no-auto' >/dev/null

echo "-- make-routines refuses self-heal and auto-merge in a non-ready repo"
for n in self-heal auto-merge; do
  if err="$("$R" add "$n" 2>&1)"; then bad "$n added"; else
    grep -q 'verify driver' <<<"$err" && grep -q 'feature map' <<<"$err" && ok "$n refused, missing items listed" || bad "$n: $err"
  fi
  [ ! -f ".github/routines/$n.md" ] && ok "$n: nothing written" || bad "$n: wrote a routine"
done

echo "-- committed driver, map without a scenario: still not ready"
printf -- '---\nid: toy\nscenario:\n---\n' >.flow/features/toy.md
git add -f .claude .flow/features && git commit -qm drv
out="$(prompt '--auto ship')"; grep -q 'feature map' <<<"$out" && ! grep -q 'verify driver' <<<"$out" \
  && ok "only the map is missing" || bad "$out"
prompt '--no-auto' >/dev/null

echo "-- committed driver + feature map with a scenario: nothing changes"
printf -- '---\nid: toy\nscenario: bash verify.sh\n---\n' >.flow/features/toy.md
git add -f .flow/features && git commit -qm map
out="$(prompt '--auto ship')"
grep -q 'factory' <<<"$out" && bad "warned in a ready repo: $out" || ok "no factory message"
[ "$(flag)" = ship ] && ok "flag is ship (enforce profile)" || bad "flag '$(flag)'"
stamp; [ "$(decide 'git push origin feat/x')" = allow ] && ok "stamped push allowed" || bad "push not allowed"
prompt '--no-auto' >/dev/null
"$R" add self-heal >/dev/null 2>&1 && [ -f .github/routines/self-heal.md ] && ok "self-heal added" || bad "self-heal refused in a ready repo"

echo "-- pair mode replays the base commit's hooks decision for decision"
base="$(git -C "$H" merge-base HEAD origin/main 2>/dev/null || true)"
if [ -z "$base" ]; then echo "  ~ skipped: no origin/main to compare with"; else
  mkdir -p "$SB/old" && git -C "$H/../../.." archive "$base" plugins/flow-stack | tar -x -C "$SB/old"
  O="$SB/old/plugins/flow-stack/hooks"
  for repo in ready not-ready; do
    if [ "$repo" = not-ready ]; then git checkout -q main; fi
    for p in enforce warn; do
      profile "$p"
      for c in 'git push origin feat/x' 'gh pr create --title x --body-file b.md' 'gh pr merge --squash' 'git reset --hard' 'git status' 'npm publish'; do
        a="$(decide "$c" "$O")"; b="$(decide "$c")"
        [ "$a" = "$b" ] && ok "$repo/$p: $c → $b" || bad "$repo/$p: $c → $b, base said $a"
      done
      a="$(prompt 'fix the bug' "$O")"; b="$(prompt 'fix the bug')"
      [ "$a" = "$b" ] && ok "$repo/$p: anchor output identical" || bad "$repo/$p: anchor differs"
    done
  done
fi

[ "$FAILS" -eq 0 ] && echo "== factory · PASS" || { echo "== factory · FAIL ($FAILS)"; exit 1; }
