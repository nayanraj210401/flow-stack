# flow-stack conventions

The single source of truth for file locations and formats. Skills and hooks both depend on these shapes. Change one here first, then the scripts that parse it.

## Locations

| Path | Scope | Committed? |
|---|---|---|
| `~/.flow-stack/profile.md` | you, all repos | no (personal) |
| `~/.flow-stack/hooks.log` | hook warnings | no |
| `<repo>/.flow/config.json` | repo settings, hook toggles | yes |
| `<repo>/.flow/taste.md` | repo/team taste, overrides personal taste | yes |
| `<repo>/.flow/gates.md` | repo irreversible actions (from `make-gates`) | yes |
| `<repo>/.flow/lessons.md` | mistakes worth not repeating | yes |
| `<repo>/.flow/map.md` | cached repo map (from `map`) | yes |
| `<repo>/.flow/debt.md` | debt ledger | yes |
| `<repo>/.flow/playbooks/*.md` | repo playbooks (from `make-playbook`) | yes |
| `<repo>/.flow/features/<id>.md` | feature map: one file per user-facing feature (from `feature-map`) | yes |
| `<repo>/.flow/features/README.md` | generated index (`features.sh index`) | yes |
| `<repo>/.flow/features/.ignore` | globs that are not features (for `coverage`) | yes |
| `<repo>/.flow/board/` | board staging: `board.json`, `board.html` (from `board`; the artifact is the product) | no |
| `~/.flow-stack/board/url` | the board artifact's link, reused on every publish | no (personal) |
| `~/.flow-stack/auto/<session_id>` | auto mode is on for that session: `--auto` in a prompt creates it, `--no-auto` removes it (anchor hook); hooks turn every ask into deny-and-queue | no |
| `~/.flow-stack/leads/<session_id>.json` | one per flow session (a lead), written by the lead hook on start, each prompt, and every 5 min of tool calls; removed at session end, pruned after 3 days: `sid id repo root branch task goal slice ticket updated ts` | no |
| `~/.flow-stack/leads/<session_id>.inbox/` | messages to that lead, one `{ts, from, label, text}` JSON file each, from `leads.sh msg`; consumed on its next prompt or tool call (never a subagent's) | no |
| `<repo>/.flow/ready.tsv` | ready-for-review ledger: `ts\tsha\tkind\tresult\tnote`, kinds review, deslop, tour, ready, and each `do` id (from `review/scripts/ready.sh`). The repo's own pre-PR gates are `.flow/config.json` `"ready": [{"id": "e2e", "run": "<cmd>"}, {"id": "sec-scan", "do": "<step, e.g. an MCP scan>"}]`: a `run` is checked live, and a `do` needs `ready.sh record <id> done` for HEAD | no |
| `<repo>/.flow/ACTIVE` | the active task: `<slug>`, or `@<home-repo-path>:<slug>` in a non-home repo of a multi-repo task | no |
| `<main>/.git/worktrees/<name>/flow-active` | the task a linked worktree leads (same format as ACTIVE); written by `task.sh new/switch` run in that worktree, removed by its `close` and with the worktree | no |
| `<main>/.git/worktrees/<name>/flow-lane` | a worker's join: the slug and the lead's root (a worktree lead, not main); written by the worker's first hook | no |
| `<repo>/.flow/tasks/<slug>/` | task folder | no (trace can export) |

`FLOW_STACK_HOME` overrides `~/.flow-stack`.

`.gitignore` gets:

```
.flow/ACTIVE
.flow/tasks/
.flow/trail.jsonl
```

## Task folder: `.flow/tasks/<slug>/`

| File | Writer | Format |
|---|---|---|
| `INTENT.md` | intent | template `INTENT.md`; `## Goal` first line is the anchor |
| `ESTIMATE` | flow | `usd=<n> ctx_pct=<n> human_min=<n>` |
| `SLICES.md` | slice | blocks, see below |
| `SEALS` | seal script | `sha256sum` output: `<hash>  <repo-relative path>` |
| `blind/` | checker agent | `MANIFEST` + check files; nobody reads these directly |
| `EVIDENCE.md` | evidence script | appended blocks, see below |
| `DECISIONS.tsv` | anyone | `ts	who	decision	why	evidence	reversible` |
| `trail.jsonl` | trail hook | one JSON object per tool call |
| `HANDOFF.md` | handoff skill | template `HANDOFF.md` |
| `HANDOFF.auto.md` | pre-compact hook | deterministic snapshot |
| `TRACE.md` | trace skill | template `TRACE.md` |
| `.circuit` | circuit hook | counters, internal |
| `REPOS` | `task.sh new --workspace/--repos` | multi-repo tasks only: `name<TAB>path` per repo; names are the profile's `# Repos` names |
| `TICKET` | `task.sh ticket <ref>` | the ticket id or URL the task works on, first line; shown by `leads.sh` |
| `GATES.md` | the agent (auto mode, gate skill) | open human gates, blocks as in Human gates below |
| `TDD` | `task.sh tdd` | opt-in TDD lock: `<slice> <red\|green> <red-FAIL count at the switch>`; per lane in a worktree |
| `lanes/<lane>/` | a worker in a linked git worktree | its own `EVIDENCE.md`, `trail.jsonl`, `.circuit`, `HANDOFF.auto.md`; imported with `task.sh accept <lane>` |

**Multi-repo tasks.** A profile `# Workspaces` entry (`- repos: a, b, c`) lists repos from `# Repos` (`- path:`, `- role: primary|dep|reference`, optional `- remote:`, `- run:`). `task.sh new <slug> <playbook> --workspace <name>` puts the task folder in the primary repo and points every other repo's ACTIVE at it. Each slice names its `repo:` (default: the home repo) and its fence is relative to that repo; an edit in any other repo is denied, whichever repo the session runs in. SEALS paths outside the home repo are `<repo>:<path>`, and evidence blocks run elsewhere carry `- repo: <name>`. Each repo gets its own branch, PR, and ready-for-review stamp.

**Worktrees.** `.flow/` is untracked, so a linked worktree has none. Every hook and script resolves `.flow/` through `hooks/roots.sh` to the main checkout's copy. A worktree with no `flow-active` is a lane of main's task: plan files (INTENT, SLICES, SEALS, blind/) are read-only there, and its writes go to `lanes/<branch>/` so parallel workers never share a file. `task.sh new` or `switch` run in a worktree writes its `flow-active`, making it a lead of its own task: it keeps the main-checkout role (plan files writable, evidence in the task folder), and main's ACTIVE is untouched. One owner per task: a slug named by main's ACTIVE or any worktree's `flow-active` is refused elsewhere.

### SLICES.md block

```
## S1 · short title
status: todo            # todo | doing | done | blocked
check: npm test -- rate-limit
repo: api                # multi-repo tasks: which repo this slice edits (default: the home repo)
fence: src/api/** tests/api/**
budget: 150             # max changed lines (added + removed)
red: n/a behavior-preserving refactor   # optional; default: a "<id>:before" FAIL is required
teeth: n/a pure rename                  # optional; default: a "probe:<id>" TEETH is required
tests: tests/api/** src/**/*.spec.ts     # optional; what the TDD lock treats as tests (default: test/, tests/, __tests__/, spec/, test_*, *_test.*, *.test.*, *.spec.* …)
```

`task.sh slice <id> done` checks the proofs (`task.sh proofs <id>`): a `<id>:before` (or `<id>:red`) FAIL, a `<id>` PASS newer than the last edit, a `probe:<id>` TEETH newer than the last edit, and changed lines within `budget` (via `loop/scripts/diffstat.sh <fence>`). `--force "<reason>"` overrides and logs a decision.

Exactly one slice is `doing` at a time in a single-agent run. Fence globs are repo-relative. `**` matches across directories.

### EVIDENCE.md block

```
### <ISO time> · S1 · PASS|FAIL · exit=<code>
- cmd: `<command>`
- head: <short commit>  dirty: <yes|no>
<details><summary>output (last 40 lines)</summary>

...
</details>
```

Only the evidence script writes these blocks. A hand-written evidence block is not evidence.

### DECISIONS.tsv

Header row: `ts	who	decision	why	evidence	reversible`. `who` is `agent`, `human`, or an agent name. `reversible` is `yes` or `no`.

## Feature files: `.flow/features/<id>.md`

Frontmatter (one line per key; `features.sh` parses it):

```
id: auth.login                       # lowercase dotted, equals the file name, permanent
title: Log in
owns: src/auth/** src/routes/login.ts   # space-separated globs; ** crosses directories
entries: web /login | api POST /api/session | cli acme login   # " | "-separated, every entry point
scenario: bash .claude/skills/verify-acme/scripts/login.sh      # command; empty until make-verifier
status: verified                     # verified | unverified | stale | broken
verified: 2026-09-27 a1b2c3d         # date + short sha of the last PASS
```

Body sections, in order: `## Sub-features` (lines `- <id>.<sub> · <behavior>`), `## How to get to it`, `## Driving it`, `## Proof`, `## Gotchas`. Evidence labels for scenario runs are `feat:<id>`. Acceptance checks cite sub-feature IDs.

## Human gates

A gate is a moment where the human decides. Present it in this shape and nothing more:

```
GATE · <what needs deciding, one line>
  options: A) ...  B) ...   (recommend: A, because ...)
  evidence: <file:line or EVIDENCE entry>
  decided: <who> <approve|reject> <ISO time>     # written by task.sh gate; the gate is closed
```

Batch open gates into one message. Log the answer to DECISIONS.tsv with `who=human`. Gates queued in `GATES.md` are numbered 1, 2, … in file order; the `/flow-pane` lists the open ones (no `decided:` line) and its buttons run `task.sh gate <n> approve|reject "<question>"`.

## Resolution order for slots

A generic skill with a slot looks for its fill in this order and uses the first hit:

0. the profile's `# Toolchain` line for that key: the user's own tool (see `setup/references/adapt.md`)
1. repo-local: `<repo>/.claude/skills/<name>-<repo>/` or `<repo>/.flow/<file>`
2. user-local: `~/.claude/skills/<user>-<name>/`
3. the flow-stack default in the skill itself

| Slot | Repo-local fill | Forge skill |
|---|---|---|
| drive the app | `.claude/skills/verify-<repo>/` or `.claude/skills/verify/` | make-verifier |
| build/run | `.claude/skills/run-<repo>/` | make-runner |
| repo playbooks | `.flow/playbooks/*.md` | make-playbook |
| irreversible actions | `.flow/gates.md` | make-gates |
| anything else | `.claude/skills/<name>/` | make-skill |

## Delegation

When the profile's `# Toolchain` maps a flow-stack skill's key to another provider (for example `- how: pstack:how`), a flow-stack skill or playbook step that would use that skill invokes the provider instead. Hand the provider the same inputs; take its output back into the flow-stack artifact (INTENT.md, EVIDENCE.md, and so on). Delegation never removes a guarantee: seals, blind checks, evidence through `evidence.sh`, the claims check, the trail, and the gates still apply.

## The skill contract (every generated skill)

- Frontmatter `description` with trigger phrases. Metadata lines in the body: `generated-by`, `generated-at`, `source-commit`.
- A `## Self-test` section with one command that proves the skill still works.
- A `Currency saved:` line (tokens, $, or attention).
- Body under ~150 lines; detail in `references/`.
- Prose passes `unslop`.

## Scripts

Shared scripts live in `skills/flow/scripts/`. A skill refers to them relative to its own base directory, for example `../flow/scripts/task.sh`. Every script prints a usage line on `-h` and fails with a clear message, never silently.
