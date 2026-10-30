#!/usr/bin/env bash
# setup.toolchain: read-only discovery for setup: detect.sh (helpers present),
# inventory.sh (toolchain JSON + fingerprint, no secrets), scan-repos.sh, usage.sh.
. "$(dirname "$0")/lib.sh"; sandbox setup.toolchain
D="$S/setup/scripts"
jq -n '{statusLine:{command:"echo hi"}, env:{MY_TOKEN:"s3cr3t-value"}, enabledPlugins:{"x@y":true},
        hooks:{Stop:[{hooks:[{type:"command",command:"say done"}]}]}}' >"$CLAUDE_CONFIG_DIR/settings.json"
jq -n '{mcpServers:{serena:{command:"uvx", env:{KEY:"mcp-secret"}}}}' >"$FLOW_CLAUDE_JSON"
mkdir -p "$CLAUDE_CONFIG_DIR/skills/my-skill"

echo "-- detect.sh"
out="$("$D/detect.sh")"; echo "$out" >"$ART/detect.txt"
grep -qE '^jq +ok' <<<"$out" && ok "jq ok" || bad "no jq row"
grep -qE '^mcp:serena +ok' <<<"$out" && ok "serena MCP seen (fake ~/.claude.json)" || bad "serena row"
grep -qE '^statusline +set' <<<"$out" && ok "status line seen" || bad "statusline row"
grep -qE '^features +missing' <<<"$out" && ok "repo: feature map missing" || bad "features row"
echo "-- inventory.sh"
inv="$("$D/inventory.sh")"; echo "$inv" >"$ART/inventory.json"
jq -e '.status_line=="echo hi" and (.env_keys|index("MY_TOKEN")) and (.mcp.user|index("serena")) and (.user_skills|index("my-skill")) and (.hooks.user[0].event=="Stop")' <<<"$inv" >/dev/null \
  && ok "status line, env keys, MCP, skills, hooks" || bad "inventory: $(jq -c '{status_line,env_keys,mcp,user_skills}' <<<"$inv")"
has "$inv" "s3cr3t-value" && bad "env value leaked" || ok "env values never printed"
has "$inv" "mcp-secret" && bad "MCP env leaked" || ok "MCP env never printed"
fp1="$("$D/inventory.sh" --fingerprint)"
jq '.statusLine.command="echo changed"' "$CLAUDE_CONFIG_DIR/settings.json" >c && mv c "$CLAUDE_CONFIG_DIR/settings.json"
fp2="$("$D/inventory.sh" --fingerprint)"
[ -n "$fp1" ] && [ "$fp1" != "$fp2" ] && ok "fingerprint changes with the toolchain" || bad "fp $fp1 → $fp2"
echo "-- scan-repos.sh"
mkdir -p "$SB/work/app" && git -C "$SB/work/app" init -q && echo '{"scripts":{"test":"jest","dev":"vite"}}' >"$SB/work/app/package.json"
out="$("$D/scan-repos.sh" "$SB/work")"
grep -qE $'app\tnode\tnpm test\tnpm run dev' <<<"$out" && ok "node repo with test + run" || bad "scan: $out"
echo "-- usage.sh"
sees "no transcripts" "no transcripts in the last 30 days" "$D/usage.sh"
mkdir -p "$CLAUDE_CONFIG_DIR/projects/p"
cat >"$CLAUDE_CONFIG_DIR/projects/p/a.jsonl" <<'JSONL'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"flow-stack:flow"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__serena__find_symbol","input":{}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"Explore"}}]}}
JSONL
out="$("$D/usage.sh" 30)"; echo "$out" >"$ART/usage.txt"
has "$out" "flow-stack:flow" && has "$out" "serena" && has "$out" "Explore" && ok "skills, MCP, subagents counted" || bad "usage: $out"
finish
