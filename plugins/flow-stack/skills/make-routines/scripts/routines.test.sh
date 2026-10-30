#!/usr/bin/env bash
# routines.test.sh: the mention routine renders a workflow that installs the plugin before the agent step, runs
# flow --auto ship, and refuses a commenter without write access; the catalog lists it; this repo's routines
# still render byte-identical.
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
S="$D/routines.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/routines.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
(cd "$D/../../../../.." && bash "$S" check >/dev/null) && ok "this repo's routines render byte-identical" || bad "routines.sh check fails at the repo root"

cd "$SB" && git init -q
grep -q '^mention  *mention ' <<<"$(bash "$S" list)" && ok "list shows mention" || bad "list: $(bash "$S" list)"
bash "$S" add mention >/dev/null || bad "add mention failed"
W=.github/workflows/flow-mention.yml
[ -f "$W" ] && ok "add mention renders $W" || bad "no $W"
bash "$S" check >/dev/null && ok "check passes" || bad "check fails"
! bash "$S" schedule mention "0 3 * * *" 2>/dev/null && ok "schedule refused" || bad "schedule accepted a cron"

line() { grep -n -m1 -F -- "$1" "$W" | cut -d: -f1; }
g="$(line 'collaborators/$COMMENTER/permission')" a="$(line 'anthropics/claude-code-action@v1')"
home="$(line 'FLOW_STACK_HOME=')" plug="$(line 'plugins: flow-stack@flow-stack')"
[ -n "$g" ] && [ -n "$a" ] && [ "$g" -lt "$a" ] && ok "permission check runs before the agent step" || bad "guard line $g, action line $a"
[ -n "$home" ] && [ -n "$plug" ] && [ "$home" -lt "$a" ] && [ "$plug" -gt "$a" ] && ok "FLOW_STACK_HOME set and the plugin installed by the agent step" || bad "home $home, plugin $plug"
grep -q '^            /flow-stack:flow --auto ship Run the routine in .github/routines/mention.md' "$W" && ok "prompt starts with /flow-stack:flow --auto ship" || bad "prompt"
grep -q "^    if: contains(github.event.comment.body, '@claude') && contains(fromJSON(" "$W" && ok "job runs only on @claude from an associated user" || bad "job if:"
grep -q '^  issue_comment:' "$W" && grep -q '^  pull_request_review_comment:' "$W" && ok "triggers on comments" || bad "on:"

# Run the rendered guard against a stub gh: the commenter's permission and the PR's head repo
mkdir bin; cat >bin/gh <<'GH'
#!/bin/sh
case "$2" in
  repos/o/r/collaborators/someone/permission) [ "$PERM" = fail ] && exit 1; echo "$PERM" ;;
  repos/o/r/pulls/7) [ "$HEAD" = fail ] && exit 1; echo "$HEAD" ;;
  *) echo "unexpected gh $*" >&2; exit 1 ;;
esac
GH
chmod +x bin/gh
sed -n '/^          COMMENTER=/,/^          \[ -z "\$PR" \]/p' "$W" | sed 's/^          //; s/\${{ github.event.comment.user.login }}/someone/' >guard.sh
[ "$(wc -l <guard.sh)" -eq 5 ] || bad "guard extract: $(cat guard.sh)"
guard() { # guard <perm> <pr number or ""> <head repo>
  sed "s/\${{ github.event.pull_request.number .* }}/$2/" guard.sh >g.sh
  PERM="$1" HEAD="${3:-}" PATH="$SB/bin:$PATH" GITHUB_REPOSITORY=o/r GITHUB_STEP_SUMMARY="$SB/summary" bash g.sh >/dev/null 2>&1
}
for p in admin maintain write; do guard "$p" "" && ok "$p passes on an issue" || bad "$p refused"; done
for p in read triage none fail; do ! guard "$p" "" && ok "$p refused" || bad "$p passed"; done
grep -q 'refused: someone has read access' summary && ok "refusal written to the run summary" || bad "summary: $(cat summary)"
guard write 7 o/r && ok "same-repo PR passes" || bad "same-repo PR refused"
! guard write 7 evil/r && ok "fork PR refused" || bad "fork PR passed"
! guard write 7 fail && ok "PR lookup failure refused" || bad "PR lookup failure passed"
[ "$FAILS" = 0 ]
