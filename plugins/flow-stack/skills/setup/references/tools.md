# Tools setup can offer

Install commands change. **Before running any install, fetch the tool's README and confirm the command.** The commands below are starting points, not gospel. Always ask the human before installing, and never edit `~/.claude/settings.json` without a backup.

| Tool | Saves | Check | Typical install (confirm first) | Source |
|---|---|---|---|---|
| rtk | tokens: compresses CLI output via a Bash PreToolUse hook | `rtk --version` and `rtk gain` | see README | https://github.com/rtk-ai/rtk. Beware the name collision with another "rtk" (Rust Type Kit): `rtk gain` must work |
| headroom | tokens: context compression MCP | `claude mcp list` | see README | project README |
| serena | tokens: symbol-level reads and edits via LSP | `claude mcp list` | `claude mcp add serena -- uvx --from git+https://github.com/oraios/serena serena start-mcp-server --context ide-assistant --project "$(pwd)"` | https://github.com/oraios/serena |
| graphify | tokens: repo knowledge graph for `map` | `command -v graphify` | see README | confirm the repo URL with the human |
| ccusage | $: usage and cost reports | `npx -y ccusage@latest --help` | none needed (npx) | https://github.com/ryoppippi/ccusage |
| Playwright MCP | attention: real browser verification | `claude mcp list` | `claude mcp add playwright -- npx @playwright/mcp@latest` | https://github.com/microsoft/playwright-mcp |
| ntfy | attention: phone push when blocked | `curl -d test ntfy.sh/<topic>` | none: pick a hard-to-guess topic | https://ntfy.sh |

## Status line

`skills/budget/scripts/statusline.sh` shows model · ctx% · $ · active task. If the human already has a status line, chain it rather than replacing it:

```json
"statusLine": { "type": "command", "command": "FLOW_STATUSLINE_CHAIN='<old command>' <plugin>/skills/budget/scripts/statusline.sh" }
```

Use the absolute path of the plugin's installed copy (under `~/.claude/plugins/cache/…/flow-stack/<version>/`). That path changes on upgrade, so tell the human, or copy the script to `~/.flow-stack/statusline.sh` and point at the copy.

## Editing settings.json safely

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak.$(date +%s)
jq '<filter>' ~/.claude/settings.json > /tmp/s.json && jq empty /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

Never remove existing hooks. flow-stack's own hooks come with the plugin (`hooks/hooks.json`), so settings.json needs no hook edits for them.
