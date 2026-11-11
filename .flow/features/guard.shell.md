---
id: guard.shell
title: Guard destructive shell commands and secrets
owns: plugins/flow-stack/hooks/guard.sh plugins/flow-stack/hooks/read-guard.sh plugins/flow-stack/hooks/lib.sh .claude/skills/verify-flow-stack/scripts/guard.shell.sh
entries: hook PreToolUse Bash | hook PreToolUse Read | file .flow/gates.md | config .flow/config.json hooks.guard
scenario: bash .claude/skills/verify-flow-stack/scripts/guard.shell.sh
status: verified
verified: 2026-10-29 90da7be
---
# Guard destructive shell commands and secrets

While the agent works, dangerous shell commands are blocked or put to the human, repo-specific gates apply, and .env files never reach the transcript. Any hook error fails open.

## Sub-features
- guard.shell.hardstop · `rm -rf /` or `~`, force-push to main/master, and `cat .env` are denied
- guard.shell.escalate · force-push to a branch, `git reset --hard`, `git clean -f`, DROP/TRUNCATE TABLE, and `curl | sh` ask the human
- guard.shell.gates · `- deny:` / `- ask:` lines in .flow/gates.md apply to matching commands, with their reason
- guard.shell.env · Read of .env / .env.* is denied; .env.example/.sample/.template are allowed
- guard.shell.toggle · `hooks.guard: false` in .flow/config.json disables it
- guard.shell.failopen · malformed input produces no decision and logs to $FLOW_STACK_HOME/hooks.log
- guard.shell.pkgcheck · npm/pip installs of packages that 404 on the registry are denied

## How to get to it
- Automatic: Claude Code runs `hooks/guard.sh` before every Bash call and `hooks/read-guard.sh` before Read/Grep/Glob.
- Repo gates: write `.flow/gates.md` (template in `templates/gates.md`, or `/flow-stack:make-gates`).

## Driving it
`.claude/skills/verify-flow-stack/scripts/guard.shell.sh` runs in a throwaway toy repo with a sandboxed FLOW_STACK_HOME, drives every entry point above, and prints one ✓/✗ per sub-feature.

## Proof
- `deny`/`ask` in `hookSpecificOutput.permissionDecision` per case (table in `.flow/artifacts/guard.shell/decisions.tsv`)
- absence: `ls`, `git status`, plain `git push`, and `cat .env.example` get no decision

## Gotchas
- `guard.pkgcheck` is not driven: it needs the network (npm/PyPI). Check it by hand with a made-up package name.
- lib.sh is shared by every hook; a change here can break all hook features, so run `features.sh run --all`.
