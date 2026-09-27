#!/usr/bin/env bash
# A fake existing toolchain inside the workspace:
#   - plugin "pstack" (enabled) with a router skill, how, unslop; SessionStart hook
#   - plugin "shinyreview" (enabled, never used) with a review skill
#   - user hooks: rtk-style Bash rewrite; a custom status line
#   - MCP: headroom (heavily used)
#   - transcripts: poteto-mode used 9x, pstack:how 4x, flow never, headroom 50x
set -e
. "$(dirname "$0")/../_lib/toy.sh"
toy_repo
C="$PWD/fake-claude"; mkdir -p "$C/plugins" "$C/projects/p1" "$C/hooks"
mk_plugin() { # id dir skills...
  local id="$1" dir="$2"; shift 2
  mkdir -p "$dir/skills" "$dir/hooks"
  for s in "$@"; do mkdir -p "$dir/skills/$s"; printf -- '---\nname: %s\ndescription: %s skill from %s.\n---\n' "$s" "$s" "$id" > "$dir/skills/$s/SKILL.md"; done
}
mk_plugin pstack@pstack-claude "$C/plugins/cache/pstack" poteto-mode how why unslop deslop tdd
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo invoke poteto-mode"}]}]}}' > "$C/plugins/cache/pstack/hooks/hooks.json"
mk_plugin shinyreview@market "$C/plugins/cache/shinyreview" review
jq -n --arg p "$C/plugins/cache/pstack" --arg r "$C/plugins/cache/shinyreview" \
  '{version:2, plugins:{"pstack@pstack-claude":[{scope:"user",installPath:$p,version:"1.0"}], "shinyreview@market":[{scope:"user",installPath:$r,version:"0.3"}]}}' \
  > "$C/plugins/installed_plugins.json"
printf '#!/bin/sh\nexit 0\n' > "$C/hooks/rtk-rewrite.sh"; chmod +x "$C/hooks/rtk-rewrite.sh"
jq -n --arg h "$C/hooks/rtk-rewrite.sh" '{
  enabledPlugins: {"pstack@pstack-claude": true, "shinyreview@market": true},
  hooks: {PreToolUse: [{matcher:"Bash", hooks:[{type:"command", command:$h}]}]},
  statusLine: {type:"command", command:"sh ~/.claude/my-statusline.sh"}
}' > "$C/settings.json"
echo '{"mcpServers":{"headroom":{"command":"headroom"}}}' > "$PWD/fake-claude.json"
t="$C/projects/p1/s1.jsonl"; : > "$t"
for i in 1 2 3 4 5 6 7 8 9; do echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pstack:poteto-mode"}}]}}' >> "$t"; done
for i in 1 2 3 4; do echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"pstack:how"}}]}}' >> "$t"; done
for i in $(seq 1 50); do echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__headroom__compress","input":{}}]}}' >> "$t"; done
mkdir -p fh
FLOW_STACK_HOME="$PWD/fh" "$FLOW_PLUGIN/skills/profile/scripts/init.sh" senior-backend >/dev/null
git add -A >/dev/null 2>&1 || true
