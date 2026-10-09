# Adapting flow-stack to an existing toolchain

flow-stack joins a setup the user has already tuned. It adapts to that setup; it doesn't replace it.

## Rules

1. **Evidence first.** Decide from `inventory.sh` (what is installed and enabled) and `usage.sh` (what is actually used). A plugin used 40 times last month is part of how this person works. An installed one never invoked is not.
2. **Never duplicate enforcement.** If another hook already does it (rewrites Bash for tokens, gates reads, blocks on Stop, notifies), flow-stack's hook for the same job is turned off or works alongside, not stacked blindly.
3. **Never fight another hook.** Two SessionStart primers that each say "always invoke my router" confuse the model. One router wins, chosen by the human.
4. **Delegate capabilities, keep guarantees.** A flow-stack capability can be handed to another tool (e.g. `how` → `pstack:how`). The guarantees stay flow-stack's: seals, blind checks, evidence, claims, trail, gates.
5. **Ask only about real overlaps.** Batch them into one question set, and recommend what the usage data supports.
6. **Record every decision** in the profile's `# Toolchain` section, so it applies on every session and can be revisited.

## Capability keys

Toolchain lines use these keys: `- <key>: <provider> · <why>`. A key is a flow-stack skill name, or one of the special keys.

| Key | flow-stack default | Typical alternatives |
|---|---|---|
| `router` | `flow-stack:flow` | `pstack:poteto-mode`, superpowers brainstorm → plan → execute, gstack `/autoplan` |
| `intent` | `flow-stack:intent` | mattpocock `/grill-me` or `/to-spec`, gstack `/office-hours` or `/spec` |
| `how` / `why` / `teach` | flow-stack | `pstack:how`, `pstack:why`, `pstack:teach` |
| `verify-driver` | `.claude/skills/verify-<repo>/` | `.claude/skills/verify/` (pstack create-verification-skill), gstack `/qa`, `/browse` |
| `review` | `flow-stack:review` | gstack `/review`, `pstack:interrogate`, `code-review`, `crh-review` |
| `tdd` / `diagnose` | flow-stack | `pstack:tdd`, gstack `/investigate`, mattpocock `/diagnosing-bugs` |
| `unslop` / `deslop` | flow-stack | `pstack:unslop`, `pstack:deslop` |
| `handoff` | flow-stack | mattpocock `/handoff` |
| `recall` | flow-stack | `pstack:recall` |
| `decision-log` | DECISIONS.tsv | `pstack:show-me-your-work` |
| `delegate` | `agent`: flow-stack worker subagents | `herdr-panes`: each worker in its own herdr pane and worktree (delegate/scripts/dispatch.sh); `pstack:swarm` or `pstack:arena` for exploration |
| `compaction` | PreCompact snapshot | a compaction plugin (e.g. jev-compaction); keep both unless it conflicts |
| `token-saver` | none | rtk hook, headroom MCP, serena MCP |
| `browser` | Playwright MCP | claude-in-chrome, gstack `/browse` |
| `statusline` | flow statusline | the user's existing status line (chain, don't replace) |
| `notify` | flow notify hook | another notifier hook or plugin: set flow's `notify: off`. An agent host is not a reason: inside one, flow already skips only its desktop ping and keeps ntfy |
| `host` | none | `herdr`, `orca`, `cmux`, `conductor`: the app that runs Claude in panes. flow reports its task, slice and gates to it |
| `orchestrator` | none (flow is the lead) | `herdr-projects`, `orca`: a coordinator that starts threads; each thread runs flow on its own |
| `note` | none | free text: an overlap or caveat worth remembering, e.g. another hook that can deny reads |

## Known tools

| Tool (how to spot it) | Adapt by |
|---|---|
| **pstack** (plugin `pstack@*`, SessionStart primer about poteto-mode) | Router overlap: ask. If they keep `poteto-mode` as the router, record `router: pstack:poteto-mode`; flow-stack's primer then stops pushing `flow`, and `flow` is used only when invoked. Delegate how/why/teach/unslop/deslop to pstack if the usage data shows they use them. Accept `.claude/skills/verify/` as the verify driver. |
| **gstack** (`~/.claude/skills/gstack/` or a `gstack` plugin) | `/qa` or `/browse` as `verify-driver` for UI. `/review` as `review` if used. `/ship` stays theirs; flow-stack's merge gate still applies before it. |
| **superpowers** (plugin, brainstorming/writing-plans skills) | Router overlap: ask. Its plans can feed `slice`; keep seals and evidence. |
| **mattpocock skills** (`grill-me`, `to-spec`, `handoff`) | `intent` → `grill-me` if preferred, but flow-stack still writes INTENT.md with runnable checks from the result. |
| **rtk** (a Bash PreToolUse hook that runs `rtk`) | Record `token-saver: rtk`. Both hooks can run on Bash; guard judges the original command. Point `budget` at `rtk gain` for savings. |
| **headroom / serena** (MCP servers) | Record them under `token-saver`. `map` and `how` use serena symbols; `budget` uses headroom. |
| **A read-gating hook** (PreToolUse on Read, Grep, or Glob, e.g. jev `run-gate.sh`) | It coexists with flow's read-guard, which only denies `blind/` and `.env`. Note it in Toolchain so a denied read is not blamed on flow-stack. |
| **A compaction plugin** | Keep flow's PreCompact snapshot (it only writes a file). If their plugin re-injects its own summary after compaction, record `compaction: <it>` and set `hooks.handoff: false` only if the human sees duplicate context. |
| **An existing status line** | Chain: `FLOW_STATUSLINE_CHAIN='<old>'`. Never replace it silently. |
| **An existing Stop hook that blocks** | Keep flow's claims check, but tell the human. Two blockers can each send the model back once. |
| **A strong CLAUDE.md** (many lines, imports) | Import hard constraints into Rules and preferences into Taste (with `src: CLAUDE.md`). Don't copy tool instructions it already carries (e.g. `@RTK.md`). |
| **An unknown plugin** | Read the `description` of each of its skills (first lines of SKILL.md under its `installPath`). Classify each against the capability keys. Only overlaps the user actually uses become questions. |

## Agent hosts

From `inventory.sh .hosts`. Every host runs the real `claude`, so flow-stack works inside it unchanged; what setup adds connects them.

| Host (how to spot it) | Adapt by |
|---|---|
| **herdr** (`hosts.herdr`) | Record `host: herdr`. Offer what's missing: the Claude integration (`claude_integration: false`), flow's sidebar rows (`sidebar_flow_rows: false`), and, only if they want a coordinator, herdr-projects (`projects: false`). Offer `delegate: herdr-panes` to anyone who wants to watch workers. |
| **herdr-projects** (`hosts.herdr.projects`) | Offer `orchestrator: herdr-projects`. If yes, offer one standing instruction in its project (`PROJECT.md`): "use /flow-stack:flow in every thread; lessons go to the repo's .flow/lessons.md". |
| **Orca** (`hosts.orca`) | Record `host: orca`. If its orchestration skill is installed (`hosts.orca.orchestration`), offer `orchestrator: orca`. Orca can switch Claude to a per-account config folder, so recommend enabling flow-stack in the repo's `.claude/settings.json`. Chain Orca's status line with flow's; never replace either. |
| **cmux** (`hosts.cmux`) | Record `host: cmux`. Nothing to install. |
| **Conductor, Vibe Kanban, Claude Squad** | No status API. Recommend the repo-scope plugin entry so their worktrees load flow-stack. |

`hooks.host: false` in `config.json` turns off both the sidebar push and the desktop-ping skip, for one repo or globally.

## Output of adaptation

1. The profile's `# Toolchain` section: capability lines, plus `- router: …` when it isn't flow.
2. `~/.flow-stack/config.json`: global hook toggles (`{"hooks": {"handoff": false}}`). Repo `.flow/config.json` overrides them.
3. `~/.flow-stack/toolchain.fp`: the fingerprint (`inventory.sh --fingerprint`). When it changes, SessionStart suggests re-running adaptation.
4. A ≤ 8-line summary for the human: what was detected, what flow-stack will use from their setup, what it turned off, what it kept.
