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
fi
