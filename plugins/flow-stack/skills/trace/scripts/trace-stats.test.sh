#!/usr/bin/env bash
# trace-stats.test.sh: no task and no arg exits 2; a task without a trail lists no unrelated commits.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"; PLUGIN="$(cd "$H/../../.." && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/trace-stats.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"; trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR" "$SB/repo"; cd "$SB/repo" || exit 1
# shellcheck source=/dev/null
. "$PLUGIN/evals/_lib/toy.sh"; toy_repo
# A future committer date: an empty --since means "now", so main lists this commit on every run, not only same-second ones.
GIT_COMMITTER_DATE="$(date -v+1H +%s 2>/dev/null || date -d '+1 hour' +%s) +0000" git commit -q --amend --no-edit
mkdir -p .flow/tasks/t2; rm -f .flow/ACTIVE

"$H/trace-stats.sh" >/dev/null 2>&1; rc=$?
if [ "$rc" = 2 ]; then ok "no task, no arg → exit 2"; else bad "no task, no arg → exit $rc, want 2"; fi

out="$("$H/trace-stats.sh" t2 2>&1)"
case "$out" in
  *"initial calculator"*) bad "task without a trail lists unrelated commits" ;;
  *"## git"*) ok "no trail → no git history" ;;
  *) bad "no trail → output has no '## git' section" ;;
esac

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL: $FAILS"; exit 1; }
