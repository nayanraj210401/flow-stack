#!/usr/bin/env bash
# inventory.sh: read-only snapshot of the user's existing Claude Code toolchain,
# so setup can adapt flow-stack to it instead of duplicating or clashing.
#   inventory.sh               JSON (plugins, skills, agents, hooks, MCP, status line,
#                              output style, CLAUDE.md imports, user skills, CLI tools)
#   inventory.sh --fingerprint one hash of what matters for adaptation
# Reads ${CLAUDE_CONFIG_DIR:-~/.claude}, ~/.claude.json (MCP server names only),
# and the current repo's .claude/ and .mcp.json. Never prints secrets or env values.
set -uo pipefail
C="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CJ="${FLOW_CLAUDE_JSON:-$HOME/.claude.json}"
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
command -v jq >/dev/null || { echo '{"error":"jq missing"}'; exit 1; }

json_or_empty() { [ -f "$1" ] && jq -c . "$1" 2>/dev/null || echo '{}'; }

settings="$(json_or_empty "$C/settings.json")"
settings_local="$(json_or_empty "$C/settings.local.json")"
proj_settings="$(json_or_empty "$root/.claude/settings.json")"
proj_local="$(json_or_empty "$root/.claude/settings.local.json")"

# hosts: agent hosts present on this machine ({} when none). Read-only; never starts a server.
hosts() {
  local h='{}' v rows=false
  if command -v herdr >/dev/null 2>&1; then
    v="$(herdr --version 2>/dev/null | awk 'NR==1{print $NF}')"
    grep -qs '\$flow_' "$HOME/.config/herdr/config.toml" && rows=true
    h="$(jq -c --arg v "$v" --argjson r "$rows" --argjson i "$(jq 'any(.. | strings; test("herdr-agent-state"))' <<<"$settings")" \
      --argjson p "$(command -v herdr-projects >/dev/null 2>&1 && echo true || echo false)" \
      '.herdr={version:$v, claude_integration:$i, sidebar_flow_rows:$r, projects:$p}' <<<"$h")"
  fi
  command -v orca >/dev/null 2>&1 && h="$(jq -c --argjson m "$(jq 'any(.. | strings; test("orca"))' <<<"$settings")" '.orca={cli:true, managed_hooks:$m}' <<<"$h")"
  command -v cmux >/dev/null 2>&1 && h="$(jq -c '.cmux={cli:true}' <<<"$h")"
  [ -n "${CONDUCTOR_WORKSPACE_PATH:-}" ] && h="$(jq -c '.conductor={env:true}' <<<"$h")"
  echo "$h"
}

fingerprint() {
  {
    jq -r '.enabledPlugins // {} | to_entries[] | select(.value) | .key' <<<"$settings" | sort
    jq -r '.hooks // {} | to_entries[] | .key as $e | .value[] | .hooks[]? | "\($e) \(.command // .type)"' <<<"$settings" | sort
    [ -f "$CJ" ] && jq -r '.mcpServers // {} | keys[]' "$CJ" | sort
    jq -r '.statusLine.command // ""' <<<"$settings"
    hosts | jq -r 'del(.conductor) | to_entries[] | "host \(.key) \(.value | tostring)"'
  } | shasum | cut -c1-12
}
[ "${1:-}" = --fingerprint ] && { fingerprint; exit 0; }

# Plugins: enabled flag + what each contributes
plugins="$(
  enabled="$(jq -c '.enabledPlugins // {}' <<<"$settings")"
  if [ -f "$C/plugins/installed_plugins.json" ]; then
    jq -r '.plugins | to_entries[] | "\(.key)\t\(.value[0].installPath)\t\(.value[0].version)"' "$C/plugins/installed_plugins.json"
  fi | while IFS=$'\t' read -r id path ver; do
    [ -n "$id" ] || continue
    skills="$(ls "$path/skills" 2>/dev/null | jq -R . | jq -sc .)"
    agents="$(ls "$path/agents" 2>/dev/null | sed 's/\.md$//' | jq -R . | jq -sc .)"
    cmds="$(ls "$path/commands" 2>/dev/null | sed 's/\.md$//' | jq -R . | jq -sc .)"
    hooks="$(jq -c '.hooks // {} | keys' "$path/hooks/hooks.json" 2>/dev/null || echo '[]')"
    mcp="$(jq -c '.mcpServers // {} | keys' "$path/.mcp.json" 2>/dev/null || echo '[]')"
    jq -nc --arg id "$id" --arg ver "$ver" --argjson en "$enabled" \
      --argjson s "$skills" --argjson a "$agents" --argjson c "$cmds" --argjson h "$hooks" --argjson m "$mcp" \
      '{id:$id, version:$ver, enabled:($en[$id] // false), skills:$s, agents:$a, commands:$c, hook_events:$h, mcp:$m}'
  done | jq -sc .
)"

hooks_of() { jq -c '[.hooks // {} | to_entries[] | .key as $e | .value[] | {event:$e, matcher:(.matcher // "*"), commands:[.hooks[]? | (.command // .type)]}]' <<<"$1"; }

mcp_user="$([ -f "$CJ" ] && jq -c '.mcpServers // {} | keys' "$CJ" || echo '[]')"
mcp_project="$([ -f "$CJ" ] && jq -c --arg r "$root" '.projects[$r].mcpServers // {} | keys' "$CJ" || echo '[]')"
mcp_repo="$(jq -c '.mcpServers // {} | keys' "$root/.mcp.json" 2>/dev/null || echo '[]')"

user_skills="$(ls -d "$C"/skills/*/ 2>/dev/null | xargs -n1 basename 2>/dev/null | jq -R . | jq -sc .)"
repo_skills="$(ls -d "$root"/.claude/skills/*/ 2>/dev/null | xargs -n1 basename 2>/dev/null | jq -R . | jq -sc .)"
user_agents="$(ls "$C"/agents/*.md 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.md$//' | jq -R . | jq -sc .)"
user_cmds="$(ls "$C"/commands/*.md 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.md$//' | jq -R . | jq -sc .)"

claude_md="$(
  for f in "$C/CLAUDE.md" "$root/CLAUDE.md" "$root/.claude/CLAUDE.md" "$root/AGENTS.md"; do
    [ -f "$f" ] || continue
    imports="$(grep -Eo '^@[^[:space:]]+' "$f" | sed 's/^@//' | jq -R . | jq -sc .)"
    jq -nc --arg f "${f/#$HOME/~}" --argjson l "$(wc -l <"$f" | tr -d ' ')" --argjson i "$imports" '{file:$f, lines:$l, imports:$i}'
  done | jq -sc .
)"

clis="$(for t in rtk headroom graphify ccusage gh uvx npx docker ntfy osascript jq; do
  command -v "$t" >/dev/null 2>&1 && echo "$t"; done | jq -R . | jq -sc .)"

jq -n \
  --arg fp "$(fingerprint)" \
  --arg root "$root" \
  --argjson hosts "$(hosts)" \
  --argjson plugins "$plugins" \
  --argjson uh "$(hooks_of "$settings")" \
  --argjson ulh "$(hooks_of "$settings_local")" \
  --argjson ph "$(hooks_of "$proj_settings")" \
  --argjson plh "$(hooks_of "$proj_local")" \
  --argjson mu "$mcp_user" --argjson mp "$mcp_project" --argjson mr "$mcp_repo" \
  --argjson us "$user_skills" --argjson rs "$repo_skills" --argjson ua "$user_agents" --argjson uc "$user_cmds" \
  --argjson cm "$claude_md" --argjson clis "$clis" \
  --argjson s "$settings" \
  '{
    fingerprint: $fp,
    repo: $root,
    model: ($s.model // null),
    output_style: ($s.outputStyle // null),
    status_line: ($s.statusLine.command // null),
    env_keys: ($s.env // {} | keys),
    permission_allow_count: ($s.permissions.allow // [] | length),
    plugins: $plugins,
    hooks: {user: $uh, user_local: $ulh, project: $ph, project_local: $plh},
    mcp: {user: $mu, project: $mp, repo: $mr},
    user_skills: $us, repo_skills: $rs, user_agents: $ua, user_commands: $uc,
    claude_md: $cm,
    cli_tools: $clis,
    hosts: $hosts
  }'
