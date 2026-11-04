#!/usr/bin/env bash
# state.sh: the factory facts detect.sh can't see: this machine (profile, shift) and the GitHub side
# (secret, branch rules, labels, kill switch, issues). Read-only. One row per fact: name status detail.
# A gh call that fails (offline, no auth, no admin) prints `unknown`, never a guess.
set -uo pipefail
row() { printf '%-12s %-8s %s\n' "$1" "$2" "${3:-}"; }
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { row repo none "not a git repo"; exit 0; }
H="${FLOW_STACK_HOME:-$HOME/.flow-stack}"

# where this session runs: a guess the interview confirms
if [ "${GITHUB_ACTIONS:-}" = true ]; then host="actions GitHub Actions runner"
elif [ -n "${CLAUDE_CODE_REMOTE:-}" ]; then host="cloud Claude Code cloud session"
elif [ "$(uname)" = Darwin ]; then host="laptop macOS"
elif [ -n "${SSH_CONNECTION:-}" ] || [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then host="server Linux, no desktop (a server or VPS?)"
else host="laptop Linux desktop"; fi
row MACHINE STATUS "this machine"
row host "${host%% *}" "${host#* }"
if [ -f "$H/profile.md" ]; then
  key() { sed -n "s/^$1:[[:space:]]*\([^[:space:]#]*\).*/\1/p" "$H/profile.md" | head -n1; }
  row profile ok "$H/profile.md · factory_ready: $(key factory_ready | grep . || echo warn) · notify: $(key notify | grep . || echo unset) · review_gate: $(key review_gate | grep . || echo on)"
  if ! grep -q '^shift:' "$H/profile.md"; then row shift none "no shift: block (make-routines add shift --local)"
  elif [ -s "$H/shift/token" ]; then row shift ok "shift: block + $H/shift/token"
  else row shift missing "no $H/shift/token: a fine-grained token for shift.repos"; fi
else
  row profile missing "/flow-stack:setup"; row shift none "needs a profile first"
fi

row REPO STATUS "$root"
ls "$root"/.github/workflows/*.y*ml >/dev/null 2>&1 \
  && row ci ok "$(ls "$root"/.github/workflows/*.y*ml | grep -vc '/flow-[^/]*$' || true) non-flow workflow(s)" || row ci none "no CI workflows"
t="$(jq -r '.commands.test // empty' "$root/.flow/config.json" 2>/dev/null)"
[ -n "$t" ] && row tests ok "$t" || row tests none "no commands.test in .flow/config.json"
[ -f "$root/.github/workflows/claude.yml" ] && row stock-yml warn "claude.yml answers @claude too; drop its comment triggers if you add mention"

url="$(git -C "$root" remote get-url origin 2>/dev/null)"
case "$url" in *github.com*) ;; *) row GITHUB none "no github.com origin: routines can't run; laptop only"; exit 0 ;; esac
row GITHUB STATUS "${url%.git}"
gh auth status >/dev/null 2>&1 || { row gh unknown "gh not logged in: gh auth login"; exit 0; }
cd "$root" || exit 0
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" || { row gh unknown "gh repo view failed"; exit 0; }
def="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)"

if s="$(gh secret list --json name -q '.[].name' 2>/dev/null)"; then
  grep -qxE 'CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY' <<<"$s" && row secret ok "$(grep -xE 'CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY' <<<"$s" | head -n1)" \
    || row secret missing "claude setup-token, then gh secret set CLAUDE_CODE_OAUTH_TOKEN"
else row secret unknown "can't list secrets (needs admin)"; fi

# rulesets are readable with read access; classic protection needs admin, and only an admin hears "Branch not protected"
if n="$(gh api "repos/$repo/rules/branches/$def" -q 'length' 2>/dev/null)" && [ "${n:-0}" -gt 0 ]; then row protect ok "$def: $n ruleset rule(s)"
elif e="$(gh api "repos/$repo/branches/$def/protection" 2>&1 >/dev/null)"; then row protect ok "$def: branch protection"
elif grep -q 'Branch not protected' <<<"$e"; then row protect missing "$def: require a PR and a passing check"
else row protect unknown "$def: no ruleset, and classic protection needs admin to read"; fi

if v="$(gh variable get FLOW_FACTORY 2>"${TMPDIR:-/tmp}/state.$$")"; then
  [ "$v" = off ] && row kill off "FLOW_FACTORY=off: every routine is paused" || row kill on "FLOW_FACTORY=$v: routines run"
elif grep -qi 'not found' "${TMPDIR:-/tmp}/state.$$"; then row kill on "routines run (gh variable set FLOW_FACTORY --body off pauses them)"
else row kill unknown "can't read repo variables"; fi
rm -f "${TMPDIR:-/tmp}/state.$$"

if l="$(gh label list --limit 500 --json name -q '.[].name' 2>/dev/null)"; then
  want="$(awk '$1 == "heal-ok" { print $2 }' "$root/.github/routines/labels.tsv" 2>/dev/null)"; want="${want:-heal-ok}"
  grep -qx "$want" <<<"$l" && row labels ok "$want exists" || row labels missing "$want (make-routines creates it, or map yours in labels.tsv)"
else row labels unknown "gh label list failed"; fi

o="$(gh issue list --state open --limit 1000 --json number -q length 2>/dev/null)" \
  && row issues ok "$o open$( [ "${want:-}" ] && h="$(gh issue list --label "$want" --state open --json number -q length 2>/dev/null)" && echo ", $h labelled $want")" \
  || row issues unknown "gh issue list failed"
