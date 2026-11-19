---
name: pr-chapters
description: "Tell the story of a PR, a GitHub issue, or several PRs as a private artifact page a reviewer reads before the diff: core-first chapters, each with its hunks, a read/skim/skip tier, and a why that links to where it is written, or a question for the author. /flow-stack:pr-chapters <pr> | <issue> | <pr> <pr> …. Use for \"tell the story of this PR\", \"onboard me to PR 12\", \"chapters for #40\", or an author self-reviewing AI-written code before asking for review."
---

# pr-chapters: the story a reviewer reads first

A diff is in file order. A reviewer needs the order the change was reasoned in: the core change first, then what it affects, then glue, tests, and generated files. Every claim about *why* links to where someone wrote it down. A why nobody wrote down becomes a question for the author, never a guess. Paths below are relative to this skill's base directory.

## 1. Collect

```bash
mkdir -p .flow/chapters && scripts/collect.sh <ref> [<ref> ...] > .flow/chapters/story.json
```

A ref is `12`, `#12`, `owner/repo#12`, or a github.com PR or issue URL. One PR is its own story. One issue is the story of the PRs that close it. Several refs make one story, with the PRs in the order they were opened. The JSON holds every PR's commits, files with their patches split into hunks, reviews, inline review comments, conversation, checks, and the issues it closes. It also includes the flow task whose `TICKET` names one of the refs (`--task <slug>` picks a task instead): its goal, INTENT, slices, and decisions. That data is how an author's reasoning reaches the reviewer. If `gh` is not signed in, collect fails with gh's own message. Pass that message on as is.

## 2. Write the chapters into `.story`

Read the hunks and the sources, then set `.story` in story.json (with `jq` or a small script, never by hand-editing the patches):

```json
{"title": "Rate-limit login", "summary": "One to three sentences: the problem, the change, what a user notices.",
 "chapters": [
  {"id": "bucket", "title": "A token bucket per account", "pr": 9, "tier": "read",
   "what": "What changes, in behavior terms.",
   "why": {"text": "Why it changes, as the sources say it.",
           "sources": [{"kind": "pr-body", "quote": "a script could try passwords forever"}, {"kind": "commit", "ref": "aaa1111"}]},
   "question": "Optional: what the reviewer should ask the author.",
   "refs": [{"file": "src/limit.ts", "hunks": [0, 1]}]}]}
```

- **Order.** Put the core change first, the change everything else exists for. Then the things it affects (callers, schema, config), then error handling and edges. Tests, generated files, and lockfiles go last, in one `skip` chapter. Group by concern, never by file or commit: one chapter may span files, and one file's hunks may split across chapters. Aim for 3–7 chapters per PR. With several PRs, keep each PR's chapters together, in PR order, and set `pr` on each chapter.
- **Tier.** Use `tour`'s rules (`../tour/SKILL.md`). `read`: new logic, changed contracts, security, concurrency, data loss. `skim`: tests, error handling, config, renames. `skip`: mechanical work, and the `what` says why it is safe to skip.
- **Why.** Only from a source. Kinds: `pr-body`, `commit` (ref: sha, 7+ chars), `review` (ref: review id), `review-comment` (ref: comment id), `comment` (ref: comment id), `issue` (ref: number), and `task` (ref: `INTENT.md` or `DECISIONS.tsv:<row>`). A source defaults to the chapter's PR; set `"pr": n` to cite another PR. A `pr-body`, `issue`, or `task` INTENT source needs a `quote`, the sentence that carries the reason; other kinds may add one. A quote must appear in its source word for word, ignoring case and spacing. A source with no text (an approval with no comment, an empty PR body) can't carry a why. When no source gives the reason, set `"why": null` (or leave the sources empty) and write the `question` a peer would ask: specific, answerable, about this chapter's change. Never infer a why and present it as the author's.
- **Coverage.** Every hunk of every changed file goes in some chapter's `refs`. Omit `hunks` to show the whole file, or split a file's hunks (0-based) across chapters. A file whose patch GitHub left out still gets a chapter ref, and the page links to it.

## 3. Render

```bash
scripts/render.sh .flow/chapters/story.json .flow/chapters/story.html
```

It refuses while any chapter's why has no source and no question, any hunk is in no chapter, a long source has no quote, or any source, quote, or hunk points at something that wasn't collected or is empty. It lists each problem. Fix the story and re-run; never edit the checks or the HTML. The page format comes from the `chapters.format` setting: `scroll` (the default, one long read), `slides` (one chapter per screen, arrow keys), or `timeline` (each PR's real events, then its chapters). Set it with `../settings/scripts/settings.sh chapters format <scroll|slides|timeline>`, or pass `--format` to collect for one run.

## 4. Publish

There is one artifact per story. Re-running updates the same link. The key is the story's refs, sorted and joined by spaces (`acme/app#9`, or `acme/app#7 acme/app#9`), stored in `${FLOW_STACK_HOME:-~/.flow-stack}/chapters/urls.tsv` as `key<TAB>url`.

- **Key found:** `read` that URL first, since the tool refuses otherwise, then publish `.flow/chapters/story.html` with `url` set to it. If the read fails because the artifact was deleted or isn't yours, treat the key as missing.
- **Key missing:** publish as a new artifact (icon `book`, description "Chapters for <refs>: the change in the order to review it, every why cited.") and append the key and URL to urls.tsv.

If there is no Artifact tool, say so in one line and stop. The page is an artifact by design.

Never post the link, the questions, or anything else to GitHub. The human shares it.

## 5. Reply (≤ 5 lines)

The link, the chapter count with how many are `read`, the number of questions for the author with the first one, and the format. The artifact is private. It quotes PR text, review comments, and diffs, so say that before the human shares it.
