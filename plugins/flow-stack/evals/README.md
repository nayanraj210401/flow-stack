# flow-stack evals

Behavior evals for `claude plugin eval`. Each case runs with and without the plugin, so the report shows what the plugin changes (Δ).

## Run

```bash
cd plugins/flow-stack
# everything that doesn't need Bash
claude plugin eval . --tag routing hooks define quality context forge \
  --scaffold --allow-tools Edit Write --runs 3 --no-publish
# cases that run scripts (evidence.sh, probe.sh, init.sh)
claude plugin eval . --tag needs-bash --scaffold --allow-tools Bash Edit Write --runs 3 --no-publish
```

- `--scaffold` is required: most cases build a toy git repo with an active flow task via `fixture.sh` → `_lib/toy.sh`.
- `--case` takes one glob. `--threshold 0` reports without failing the exit code.
- Bash-granting runs are refused on machines whose `~/.docker` credential store contains a symlink. Run the `needs-bash` cases elsewhere, or fix the store.

## Cases

| Tag | Case | What it proves |
|---|---|---|
| routing | routes-feature-to-flow | A feature request invokes `flow` and plans checks-first |
| routing | question-skips-ceremony | A quick question gets a short answer and no task folder |
| routing | bug-routes-to-diagnose | A bug report triggers `flow`/`diagnose`: reproduce first, no symptom patches |
| routing, attention | brief-long-reply | A long reply is restated in a few plain lines, keeping the risks |
| routing, trust | no-unverified-done | A status update doesn't claim unverified work is done |
| hooks, trust | seal-blocks-test-edit | A sealed test can't be weakened to get a pass |
| hooks, trust | env-read-denied | `.env` secrets never reach the transcript |
| hooks, trust | blind-checks-hidden | Blind checks stay hidden even when asked directly |
| hooks, trust | fence-blocks-out-of-scope | The fence hook fires on out-of-slice edits; widening is deliberate |
| hooks, trust | claims-need-evidence | An unverified "done" is sent back and ends as `~ assumed` |
| define | intent-writes-checks | `intent` writes a goal, non-goals, and runnable checks, and no implementation |
| define, trust | intent-fact-checks-ticket | A ticket criterion with a false premise is flagged with evidence; the valid ones become checks and are not argued |
| quality | unslop-pr-description | AI-sounding prose loses the slop and keeps every fact |
| quality | deslop-diff | Narrating comments and debug clutter go; behavior stays |
| context | handoff-writes-resume | HANDOFF.md names the failing check and a concrete next action |
| forge | make-gates-from-configs | Deploy, migration, infra, and publish commands become enforceable gate lines |
| loop, needs-bash | loop-records-evidence | The inner loop records PASS via evidence.sh and TEETH via probe.sh |
| verify, needs-bash | probe-flags-toothless | probe flags a test that passes without the change |
| design | challenge-breaks-anchor | Asked to plan a new module, the advocate finds that existing code already does it and recommends reuse |
| design, routing | devils-advocate-on-request | "Is there a better way?" gets a comparison with the simplest option, not a defense |
| quality, design | least-code-reuses-helper | A small edit reuses an existing helper found by search; no duplicated logic, no new files |
| loop, needs-bash | slice-gate-refuses-unproven | The slice-done gate refuses unproven work; the agent produces proofs or forces with an honest reason |
| self, needs-bash | setup-profile-preset | Profile init from a preset, then the lint |
| self, adapt, needs-bash | setup-adapts-to-toolchain | Against a fake toolchain (pstack, rtk hook, status line, unused review plugin, usage transcripts), `setup adapt` makes pstack the router, delegates `how`, chains the status line, and ignores the unused plugin |

Graders marked `tool_used: Skill` are with-only indicators (did the skill fire?), not part of the score.

## Adding a case

`claude plugin eval init --bare <name>`, then add `case.yaml` (`schema_version`, `name`, `tags`, and `context.scaffold_script` if it needs a repo). Prefer deterministic graders (`regex`, `file_exists`, `tool_used`) and use `llm` graders with a `focus` on the file that matters. A case where both arms pass is a regression test, not evidence of value. Say which one it is.
