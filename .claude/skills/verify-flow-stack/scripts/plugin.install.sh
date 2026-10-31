#!/usr/bin/env bash
# plugin.install: the marketplace + plugin install cleanly: manifests validate, versions
# agree, every hook command exists and parses, every skill/agent has frontmatter, and
# every relative link inside skills resolves.
. "$(dirname "$0")/lib.sh"; sandbox plugin.install
cd "$REPO"
fm() { awk -v k="$2" 'NR==1&&$0=="---"{on=1;next} on&&$0=="---"{exit} on&&index($0,k":")==1{sub("^" k ":[[:space:]]*","");print;exit}' "$1"; }

if command -v claude >/dev/null 2>&1; then
  sees "claude plugin validate (plugin)" "Validation passed" claude plugin validate plugins/flow-stack
  sees "claude plugin validate (marketplace)" "Validation passed" claude plugin validate .
else echo "  – claude CLI not on PATH; manifest validation skipped"; fi
[ "$(jq -r .version "$PLUGIN/.claude-plugin/plugin.json")" = "$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)" ] \
  && ok "plugin.json and marketplace.json versions agree" || bad "version mismatch"
[ "$(jq -r '.plugins[0].source' .claude-plugin/marketplace.json)" = ./plugins/flow-stack ] && ok "marketplace source path" || bad "source path"

echo "-- hooks.json wiring"
for c in $(jq -r '.hooks[][].hooks[].command' "$PLUGIN/hooks/hooks.json" | sed 's/"//g; s#${CLAUDE_PLUGIN_ROOT}#'"$PLUGIN"'#'); do
  [ -x "$c" ] && bash -n "$c" && ok "$(basename "$c") exists, executable, parses" || bad "hook command broken: $c"
done
for e in SessionStart UserPromptSubmit PreToolUse PostToolUse PreCompact Stop Notification; do
  jq -e --arg e "$e" '.hooks[$e]' "$PLUGIN/hooks/hooks.json" >/dev/null && ok "event $e wired" || bad "event $e missing"
done

echo "-- scripts and JSON"
n=0; while IFS= read -r f; do bash -n "$f" 2>>"$ART/syntax.txt" || bad "syntax: $f"; [ -x "$f" ] || bad "not executable: $f"; n=$((n+1)); done < <(git ls-files 'plugins/*.sh' | grep -v '/evals/' | grep -v '/lib\.sh$' | grep -v '_lib/')
ok "$n scripts parse and are executable"
while IFS= read -r f; do jq empty "$f" 2>/dev/null || bad "invalid JSON: $f"; done < <(git ls-files '*.json')
ok "every tracked JSON parses"

echo "-- skills and agents"
for d in "$PLUGIN"/skills/*/; do
  s="$d/SKILL.md"; id="$(basename "$d")"
  [ -f "$s" ] || { bad "skills/$id has no SKILL.md"; continue; }
  [ "$(fm "$s" name)" = "$id" ] && [ -n "$(fm "$s" description)" ] || bad "skills/$id: name/description frontmatter"
done
ok "$(ls -d "$PLUGIN"/skills/*/ | wc -l | tr -d ' ') skills have name + description"
for a in "$PLUGIN"/agents/*.md; do
  [ -n "$(fm "$a" name)" ] && [ -n "$(fm "$a" description)" ] || bad "agent $(basename "$a"): frontmatter"
done
ok "$(ls "$PLUGIN"/agents/*.md | wc -l | tr -d ' ') agents have name + description"

echo "-- relative links inside skills resolve"
broken=0
while IFS= read -r f; do
  while IFS= read -r l; do
    l="${l%%#*}"; [ -n "$l" ] || continue
    [ -e "$(dirname "$f")/$l" ] || { echo "    $f → $l" >>"$ART/broken-links.txt"; broken=$((broken+1)); }
  done < <(grep -oE '\]\([^)[:space:]]+\)' "$f" | sed 's/^](//; s/)$//' | grep -vE '^(https?:|mailto:|#|/)')
done < <(find "$PLUGIN/skills" "$PLUGIN/agents" -name '*.md')
[ "$broken" -eq 0 ] && ok "no broken relative links" || bad "$broken broken link(s): $(head -n 5 "$ART/broken-links.txt")"
finish
