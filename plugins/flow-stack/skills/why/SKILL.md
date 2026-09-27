---
name: why
description: Explain why code is the way it is from git history, PRs, issues, and docs, with citations. Use for "why is it like this", "when did this change", before removing something odd.
---

# why

Chesterton's fence: before removing something odd, find out why it's there.

## Evidence, cheapest first

1. **Code comments and docs** near the thing: ADRs, `docs/`, README, `.flow/lessons.md`.
2. **git:** `git log -L <start>,<end>:<file>` for a line range, `git log -S '<string>' --oneline` to find the commit that introduced a string, `git blame -w -C <file>` for authorship, then `git show <sha>` for the full commit message.
3. **The PR** behind the commit: `gh pr list --search <sha> --state merged` and then `gh pr view <n> --comments`, when `gh` is authed.
4. **Issue trackers and chat** through whatever MCP tools are connected (Linear, Jira, Slack, Notion). Search by the PR or issue number found in steps 2 and 3.

Run independent lookups in parallel. Stop when you have a cited answer; don't exhaust every source.

## Answer shape

- Line 1: the reason, in one sentence.
- Then 1 to 4 citations: `abc1234 (2025-03-02, @author): "…quote…"`, PR links, doc paths.
- Confidence: `certain` (explicitly stated), `likely` (strongly implied), or `unknown` (no record; say what you checked).

When the reason no longer holds, say what changed, and hand the decision to the human. Removing a fence is their call.
