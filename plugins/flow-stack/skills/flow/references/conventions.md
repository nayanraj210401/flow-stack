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
| `<repo>/.flow/ACTIVE` | slug of the active task, one line | no |
| `<repo>/.flow/tasks/<slug>/` | task folder | no (trace can export) |

`FLOW_STACK_HOME` overrides `~/.flow-stack`.

`.gitignore` gets:

```
.flow/ACTIVE
.flow/tasks/
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

### SLICES.md block

```
## S1 · short title
status: todo            # todo | doing | done | blocked
check: npm test -- rate-limit
fence: src/api/** tests/api/**
budget: 150             # max changed lines (added + removed)
red: n/a behavior-preserving refactor   # optional; default: a "<id>:before" FAIL is required
teeth: n/a pure rename                  # optional; default: a "probe:<id>" TEETH is required
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

## Human gates

A gate is a moment where the human decides. Present it in this shape and nothing more:

```
GATE · <what needs deciding, one line>
  options: A) ...  B) ...   (recommend: A, because ...)
  evidence: <file:line or EVIDENCE entry>
```

Batch open gates into one message. Log the answer to DECISIONS.tsv with `who=human`.

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
