#!/usr/bin/env bash
# draft-flag.test.sh: the ready gate exempts a real draft flag, not "-d" inside a quoted title/body (#60), nor --draft=false (#122),
# including a draft wrapped in sh -c '…'.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
PASSES=0
ok()  { PASSES=$((PASSES + 1)); }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/draft-flag.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID
cd "$SB/repo" && git init -q && git config user.email a@b && git config user.name a
mkdir -p .flow/tasks/x; echo x >.flow/ACTIVE
printf '# Intent\n## Goal\ng\n' >.flow/tasks/x/INTENT.md
git add -A && git commit -qm i

decide() {
  local out
  out="$(jq -nc --arg c "$PWD" --arg cmd "$1" '{hook_event_name:"PreToolUse",session_id:"s",cwd:$c,tool_name:"Bash",tool_input:{command:$cmd}}' | "$H/guard.sh")"
  [ -n "$out" ] || { echo allow; return; }
  jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out"
}
expect() { local got; got="$(decide "$2")"; [ "$got" = "$1" ] && ok "$1: $2" || bad "$2 → $got, want $1"; }

expect deny  'gh pr create --title x'
expect deny  'gh pr create --title "fix -d flag handling" --body x'
expect deny  "gh pr create --title x --body 'use -d here'"
expect deny  'gh pr create --title x --body "multi-line with -d
  here"'
expect deny  'gh pr create --title "a \" -d"'
expect deny  "gh pr create --title \$'a\\' -d'"
expect deny  'gh pr create --title fix\ -d'
expect allow 'gh pr create --draft --title x'
expect allow 'gh pr create -d --title x'
expect allow 'gh pr create --title "fix -d" --draft'
expect allow 'gh pr create --draft=true --title x'
expect deny  'gh pr create --draft=false'
expect deny  'gh pr create --title x --draft=false'
expect deny  'gh pr create --draft=false --title x'
# Wrapped in a quoted shell string: the wrapper's quote is not a quoted title.
expect allow "sh -c 'gh pr create --draft --title x'"
expect allow "bash -lc \"gh pr create -d --title x\""
expect deny  "sh -c 'gh pr create --title x'"
expect deny  "sh -c 'gh pr create --title \"a -d\" --body x'"
expect allow "sh -c 'gh pr create --draft'"
expect allow "eval \"gh pr create --title 'a -d' --draft\""
expect deny  'bash -c "gh pr create --body \"fix -d flag\" --title x"'
expect deny  "sh -c \"gh pr create --title 'x' --body \\\"y --draft z\\\"\""
# Every gh pr create/ready on the line needs its own draft flag; quoted text naming one doesn't count.
expect deny  "sh -c 'gh pr create --draft --title x' && gh pr create --title y"
expect deny  'gh pr create --draft --title x && gh pr create --title y'
expect deny  "echo 'gh pr create --draft x' && gh pr create --title x"
expect deny  "grep 'gh pr create -d foo' f; gh pr create --title x"
# Commands the split can't see into fail closed instead of riding on a draft elsewhere on the line.
expect deny  'gh pr create --draft; `gh pr create --title x`'
expect deny  'gh pr create --draft --title "$(gh pr create --title y)"'
expect deny  "gh pr create --draft; bash -c -e 'gh pr create --title x'"
expect deny  "gh pr create --draft; X=1 eval 'gh pr create --title x'"
expect deny  'gh pr create --title x # --draft'
expect deny  "gh pr create --draft; ksh -c 'gh pr create --title x'"
expect deny  '{ gh pr create --title x; }'
expect deny  'nice gh pr create --title x'
expect deny  'gh pr create --draft --body "$(timeout 5 gh pr create --title x)"'
expect allow '{ gh pr create --draft --title x; }'
expect allow 'gh pr create --draft --title x # opened as a draft'
expect deny  'gh pr create --title x "--draf\t"'
# A draft whose own text names the command is still a draft.
expect allow 'gh pr create --draft --title "docs: explain gh pr create flags"'
expect allow 'gh pr create --draft --title x --body "Run gh pr ready when done"'
expect allow 'git commit -m "guard: handle gh pr create" && gh pr create --draft --title x'
expect allow "gh pr create --draft --title x --body 'Fixes: gh pr create --draft wrapped in sh -c'"
expect allow 'gh pr create --draft --title x --body "steps: build; gh pr ready"'
expect allow "gh pr create --draft --title x --body 'see: a; gh pr ready'"
expect allow 'gh pr create --draft --title x --body "a (gh pr ready) b"'
expect allow "gh pr create --draft --title x --body 'Run \`gh pr ready\` when done'"
expect deny  'gh pr create --draft --title x --body "Run `gh pr ready` when done"'
expect deny  "sh -c 'echo \"\$(gh pr create --title y)\"'"
expect allow 'git commit -m "wip; gh pr ready next" && gh pr create --draft --title x'
expect allow 'git commit -m "handle drafts (gh pr ready)" && gh pr create --draft --title x'
expect allow "gh pr create --draft --title x --body \"\$(printf '%s' 'a; gh pr ready')\""
expect deny  'gh pr create --draft --title x --body "$(echo "a"; gh pr create --title y)"'
expect deny  'gh pr create --draft --title x --body "`echo "a"; gh pr create --title y`"'
expect deny  "gh pr create --draft; command eval 'gh pr create --title x'"
expect deny  "gh pr create --draft --title x --body \"\$(sh -c 'gh pr create --title y')\""
expect allow 'gh pr create --title x \
--draft'
expect deny  "bash -c \$'gh pr create --title \\'a -d\\''"
expect allow "bash -c \$'gh pr create --title x --draft'"

# #257: a leading `cd <dir> &&` is judged by that dir's repo; a dir outside any repo falls back to the session root.
git worktree add -q "$SB/wt-ok" -b ok && git -C "$SB/wt-ok" commit -q --allow-empty -m s
git worktree add -q "$SB/wt-no" -b no && git -C "$SB/wt-no" commit -q --allow-empty -m u
printf '%s\t%s\tready\tpass\n' "$(date +%s)" "$(git -C "$SB/wt-ok" rev-parse HEAD)" >.flow/ready.tsv
mkdir -p "$SB/norepo"
expect allow "cd $SB/wt-ok && gh pr ready 1"
expect allow "cd ../wt-ok && gh pr create --title x"
expect deny  "cd $SB/wt-no && gh pr ready 1"
expect deny  "cd $SB/norepo && gh pr ready 1"
expect deny  "cd $SB/wt-ok && cd $SB/wt-no && gh pr ready 1"
expect deny  "cd $SB/wt-ok && { cd $SB/wt-no; gh pr ready 1; }"
expect deny  "cd $SB/wt-ok && builtin cd $SB/wt-no && gh pr ready 1"
expect deny  "cd $SB/wt-ok && bash -c 'cd $SB/wt-no && gh pr ready 1'"
expect deny  "cd $SB/wt-ok && true
cd $SB/wt-no
gh pr ready 1"
expect deny  "cd $SB/wt-ok; gh pr ready 1 && cd $SB/wt-no && gh pr create --title x"
expect deny  "cd $SB/wt-ok && c''d $SB/wt-no && gh pr ready 1"
expect deny  "cd $SB/wt-ok && c\\d $SB/wt-no && gh pr ready 1"
expect deny  "cd $SB/wt-ok && cd\${IFS}$SB/wt-no && gh pr ready 1"
expect deny  "cd $SB/wt-ok && env -C $SB/wt-no gh pr ready 1"
expect deny  "cd $SB/wt-ok && cd; gh pr ready 1"
# another clone with its own stamp and review_gate: yolo is not this repo: judged by the session root
git clone -q "$SB/wt-ok" "$SB/other" && mkdir -p "$SB/other/.flow" && echo '{"review_gate":"yolo"}' >"$SB/other/.flow/config.json"
printf '%s\t%s\tready\tpass\n' "$(date +%s)" "$(git -C "$SB/other" rev-parse HEAD)" >"$SB/other/.flow/ready.tsv"
expect deny  "cd $SB/other && gh pr ready 1"
# the target is resolved like the shell's cd: L/.. is the dir holding L (here the unstamped session root), not wt-ok
mkdir -p "$SB/wt-ok/sub" && ln -s "$SB/wt-ok/sub" L
expect deny  "cd L/.. && gh pr create --title x"
rm L
expect deny  "cd .git && gh pr ready 1"
HOME="$SB" expect allow "cd ~/wt-ok && gh pr ready 1"
mkdir -p sub2 && pushd sub2 >/dev/null; expect allow "cd ../../wt-ok && gh pr ready 1"; popd >/dev/null
pushd "$SB/wt-no" >/dev/null; expect allow "cd ../wt-ok && gh pr ready 1"; expect deny  "gh pr ready 1"; popd >/dev/null

[ "$FAILS" -eq 0 ] && echo "ok" || { echo "$FAILS failed"; exit 1; }
