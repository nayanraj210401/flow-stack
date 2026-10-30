#!/usr/bin/env bash
# routines.sh: the mention routine renders, installs the plugin before the agent, and refuses commenters without write access.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
sh="$here/routines.sh"
repo="$(cd "$here/../../../../.." && pwd)"
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
t() { local d="$1"; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }

# the committed routines still match a fresh render (byte-identical)
t "committed routines render unchanged" bash -c 'cd "$1" && bash "$2" check >/dev/null' _ "$repo" "$sh"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cd "$work" || exit 1
mkdir -p .github/routines && cp "$repo/.github/routines/profile.md" .github/routines/
bash "$sh" add mention >/dev/null || bad "add mention"
w=.github/workflows/flow-mention.yml
[ -f "$w" ] && ok "add mention renders $w" || bad "add mention renders $w"
bash "$sh" list | grep -q '^mention ' && ok "list shows mention" || bad "list shows mention"
bash "$sh" check >/dev/null && ok "check passes" || bad "check passes"

access="$(grep -n 'name: Write access' "$w" | head -1 | cut -d: -f1)"
action="$(grep -n 'uses: anthropics/claude-code-action' "$w" | head -1 | cut -d: -f1)"
[ -n "$access" ] && [ -n "$action" ] && [ "$access" -lt "$action" ] && ok "write-access check runs before the agent" || bad "write-access check runs before the agent"
grep -q 'case "\$perm" in admin|maintain|write) ;; \*) .*exit 1' "$w" && ok "commenters without write access are refused" || bad "commenters without write access are refused"
grep -q "contains(github.event.comment.body, '@claude')" "$w" && ok "reacts only to @claude comments" || bad "reacts only to @claude comments"
grep -q 'plugins: flow-stack@flow-stack' "$w" && grep -q 'FLOW_STACK_HOME=' "$w" && ok "installs the plugin and sets FLOW_STACK_HOME" || bad "installs the plugin and sets FLOW_STACK_HOME"
grep -q '/flow-stack:flow --auto ship ' "$w" && ok "prompt starts with flow --auto ship" || bad "prompt starts with flow --auto ship"
grep -q 'comment.body' "$w" && grep -q 'prompt: |' "$w" && ! sed -n '/prompt: |/,/claude_args/p' "$w" | grep -q 'comment.body' && ok "comment text stays out of the prompt" || bad "comment text stays out of the prompt"

# a pinned plugin still puts the access check before the agent
sed -i 's/^timeout: 60/timeout: 60\nflow_ref: "v1"/' .github/routines/mention.md
bash "$sh" render >/dev/null
grep -q 'git clone' "$w" && grep -q 'name: Write access' "$w" && ok "pinned mention keeps the access check and clone" || bad "pinned mention keeps the access check and clone"

exit "$fail"
