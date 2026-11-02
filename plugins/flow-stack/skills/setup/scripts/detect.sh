#!/usr/bin/env bash
# detect.sh: report which flow-stack helper tools are present. Read-only.
set -uo pipefail
C="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CJ="${FLOW_CLAUDE_JSON:-$HOME/.claude.json}"
row() { printf '%-12s %-8s %s\n' "$1" "$2" "$3"; }
have() { command -v "$1" >/dev/null 2>&1; }
row TOOL STATUS DETAIL
for t in jq git gh curl perl shasum; do
  if have "$t"; then row "$t" ok "$(command -v "$t")"; else row "$t" MISSING "required or strongly recommended"; fi
done
have rtk && row rtk ok "$(rtk --version 2>/dev/null | head -n1)" || row rtk missing "token saver: compresses CLI output"
have headroom && row headroom ok "$(command -v headroom)" || row headroom missing "token saver: context compression MCP"
have graphify && row graphify ok "$(command -v graphify)" || row graphify missing "repo knowledge graph (map)"
have ccusage && row ccusage ok "$(command -v ccusage)" || { have npx && row ccusage via-npx "npx -y ccusage@latest works" || row ccusage missing "cost reports"; }
have uvx && row uvx ok "needed for serena" || row uvx missing "needed for serena (install uv)"
have npx && row npx ok "needed for playwright MCP / ccusage" || row npx missing "install Node.js"
have osascript && row osascript ok "macOS notifications" || row osascript n/a "not macOS; use ntfy"
mcps="$([ -f "$CJ" ] && jq -r '.mcpServers // {} | keys[]' "$CJ" 2>/dev/null || true)"
for m in serena playwright headroom; do
  grep -qix "$m" <<<"$mcps" && row "mcp:$m" ok "configured (user scope)" || row "mcp:$m" missing "not in user MCP servers"
done
s="$C/settings.json"
if [ -f "$s" ] && have jq; then
  row statusline "$(jq -r 'if .statusLine then "set" else "none" end' "$s")" "$(jq -r '.statusLine.command // ""' "$s" | cut -c1-60)"
  row user-hooks info "$(jq -r '[.hooks // {} | to_entries[] | "\(.key)×\(.value | length)"] | join(" ")' "$s")"
fi
for h in herdr orca cmux; do have "$h" && row "host:$h" ok "agent host: $(command -v "$h")"; done
[ -n "${CONDUCTOR_WORKSPACE_PATH:-}" ] && row host:conductor ok "agent host (env only)"
[ -f "${FLOW_STACK_HOME:-$HOME/.flow-stack}/profile.md" ] && row profile ok "${FLOW_STACK_HOME:-$HOME/.flow-stack}/profile.md" || row profile missing "run the profile interview"
root=""; if git rev-parse --show-toplevel >/dev/null 2>&1; then . "$(dirname "$0")/../../../hooks/roots.sh"; flow_roots; root="$FLOW_MAIN"; fi
if [ -n "$root" ]; then
  for f in config.json map.md taste.md gates.md; do
    [ -f "$root/.flow/$f" ] && row ".flow/$f" ok "" || row ".flow/$f" missing ""
  done
  nf="$(ls "$root"/.flow/features/*.md 2>/dev/null | grep -vc '/README\.md$' || true)"
  if [ "${nf:-0}" -gt 0 ]; then row features ok "$nf feature(s) in .flow/features/"; else row features missing "feature-map"; fi
  drv="$(ls -d "$root"/.claude/skills/verify-* "$root"/.claude/skills/verify 2>/dev/null | head -n1)"
  if [ -n "$drv" ]; then row verify-drv ok "$(basename "$drv")"; else row verify-drv missing "make-verifier"; fi
  ls -d "$root"/.claude/skills/run-* >/dev/null 2>&1 && row run-drv ok "" || row run-drv missing "make-runner"
  ls "$root"/.flow/playbooks/*.md >/dev/null 2>&1 && row playbooks ok "$(ls "$root"/.flow/playbooks/*.md | wc -l | tr -d ' ') repo playbook(s)" || row playbooks none "make-playbook (optional)"
  ls "$root"/.github/routines/*.md >/dev/null 2>&1 && row routines ok "$(ls "$root"/.github/routines/*.md | grep -vc '/profile\.md$' || true) routine(s)" || row routines none "make-routines (optional)"
  # Factory: one row per loop stage (skills/flow/references/factory.md). verify and the routine stage rows
  # read HEAD of this checkout (a worktree included), since runners see only the clone; triage and spec are fixed text.
  row FACTORY STATUS "loop stage: what serves it, or the fix"
  # what runs is the committed workflow make-routines renders, so a stage row reads HEAD like verify does
  wf() { git -C "$FLOW_ROOT" cat-file -e "HEAD:.github/workflows/flow-$1.yml" 2>/dev/null; }
  routine() { wf "$1" && row "$2" ok "$1 routine" || row "$2" missing "make-routines: $1${3:+ ($3)}"; }
  routine self-create monitor
  row triage planned "#185 triage, #186 ideate"
  row spec ok "intent + seal (plugin); edge-case matrix planned #187"
  # self-heal (issues) or mention (@claude) runs the build unattended
  s=""; wf self-heal && s=self-heal; wf mention && s="${s:+$s + }mention"
  [ -n "$s" ] && row implement ok "$s routine" || row implement missing "make-routines: self-heal or mention (flow --auto works in a session)"
  # The same check that gates --auto ship and self-heal, on this checkout (a worktree included)
  . "$(dirname "$0")/../../../hooks/lib.sh"
  if miss="$(factory_ready "$FLOW_ROOT")"; then ready=1; row verify ok "committed verify driver + a feature with a scenario"; else ready=""; row verify missing "${miss:-factory_ready failed}"; fi
  routine review review "ready.sh works in a session"
  wf auto-merge && row ship ok "auto-merge routine" || row ship missing "auto-merge routine (no make-routines template yet; #184)"
  [ -n "$ready" ] && row factory ok "ready; impacted scenarios must also pass on HEAD (ready.sh)" || row factory missing "not ready: needs verify; --auto ship warns, or runs as plain --auto with factory_ready: enforce"
fi
