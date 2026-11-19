#!/usr/bin/env bash
# chapters.test.sh: pr-chapters end to end against a stub gh.
#   chapters.test.sh [collect|refuse|render|format]   one group, or all of them
# collect: PR, issue, and PR list → one story JSON. refuse: render.sh rejects uncited whys,
# uncovered files, bad hunk refs, made-up sources. render: the page in all three formats.
# format: the chapters.format setting reaches the story.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$H/../../settings/scripts/settings.sh"
SB="$(mktemp -d "${TMPDIR:-/tmp}/chapters.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
pass=0; fail=0
ck() { if eval "$2"; then pass=$((pass+1)); else echo "  ✗ $1"; fail=1; fi; }
want="${1:-all}"; on() { [ "$want" = all ] || [ "$want" = "$1" ]; }

# --- fixtures: acme/app, issue 5 closed by PRs 7 (earlier) and 9; issue 6 has no PRs
F="$SB/fix"; mkdir -p "$F" "$SB/bin"
cat >"$F/pr9.json" <<'J'
{"number":9,"title":"Rate-limit login","url":"https://github.com/acme/app/pull/9","author":{"login":"ana"},"state":"MERGED",
 "createdAt":"2026-03-02T10:00:00Z","mergedAt":"2026-03-03T12:00:00Z","baseRefName":"main","headRefName":"limit","additions":30,"deletions":4,
 "body":"Login had no limit, so a script could try passwords forever.\n\nAdds a token bucket per account.",
 "closingIssuesReferences":[{"number":5}],
 "commits":[{"oid":"aaa1111","messageHeadline":"add token bucket","messageBody":"5 tries a minute, refill 1 per 12s","committedDate":"2026-03-02T10:05:00Z","authors":[{"login":"ana"}]},
            {"oid":"bbb2222","messageHeadline":"wire limiter into login","messageBody":"","committedDate":"2026-03-02T11:00:00Z","authors":[{"login":"ana"}]}],
 "reviews":[{"id":"R1","author":{"login":"bo"},"state":"CHANGES_REQUESTED","body":"What happens when the clock goes backwards?","submittedAt":"2026-03-02T15:00:00Z"},
            {"id":"R2","author":{"login":"bo"},"state":"APPROVED","body":"","submittedAt":"2026-03-03T11:00:00Z"}],
 "comments":[{"id":"C1","author":{"login":"ana"},"body":"Monotonic clock now.","createdAt":"2026-03-02T16:00:00Z"}],
 "statusCheckRollup":[{"name":"test","conclusion":"SUCCESS"}]}
J
cat >"$F/pr9.files.json" <<'J'
[{"filename":"src/limit.ts","status":"added","additions":24,"deletions":0,"patch":"@@ -0,0 +1,3 @@\n+export class Bucket {\n+  take() { return true }\n+}\n@@ -10,2 +13,3 @@ refill\n-  old()\n+  refill()\n+  now()"},
 {"filename":"src/login.ts","status":"modified","additions":6,"deletions":4,"patch":"@@ -1,2 +1,2 @@\n-login()\n+if (!bucket.take()) throw tooMany()"},
 {"filename":"dist/bundle.js","status":"modified","additions":0,"deletions":0}]
J
echo '[{"id":77,"user":{"login":"bo"},"path":"src/limit.ts","line":2,"body":"take() never says no </script><b>x</b>"}]' >"$F/pr9.comments.json"
cat >"$F/pr7.json" <<'J'
{"number":7,"title":"Account lockout table","url":"https://github.com/acme/app/pull/7","author":{"login":"ana"},"state":"MERGED",
 "createdAt":"2026-03-01T09:00:00Z","mergedAt":"2026-03-01T18:00:00Z","baseRefName":"main","headRefName":"lockout","additions":8,"deletions":0,
 "body":"","closingIssuesReferences":[{"number":5}],
 "commits":[{"oid":"ccc3333","messageHeadline":"lockout table","messageBody":"","committedDate":"2026-03-01T09:30:00Z","authors":[{"login":"ana"}]}],
 "reviews":[],"comments":[],"statusCheckRollup":[]}
J
echo '[{"filename":"db/lockout.sql","status":"added","additions":8,"deletions":0,"patch":"@@ -0,0 +1,1 @@\n+create table lockout (id int);"}]' >"$F/pr7.files.json"
echo '[]' >"$F/pr7.comments.json"
# the files each commit touched (gh api .../commits/<sha> --jq '[.files[].filename]')
echo '["src/limit.ts"]' >"$F/commit-aaa1111.json"
echo '["src/limit.ts","src/login.ts","dist/bundle.js"]' >"$F/commit-bbb2222.json"
echo '["db/lockout.sql"]' >"$F/commit-ccc3333.json"
# PR 11 closes an issue in another repo, other/lib#5 (not acme/app#5)
jq '.number=11 | .url="https://github.com/acme/app/pull/11" | .closingIssuesReferences=[{"number":5,"repository":{"name":"lib","owner":{"login":"other"}}}]' "$F/pr7.json" >"$F/pr11.json"
cp "$F/pr7.files.json" "$F/pr11.files.json"; echo '[]' >"$F/pr11.comments.json"
echo '{"number":5,"title":"Lib bug","url":"https://github.com/other/lib/issues/5","author":{"login":"dd"},"state":"OPEN","body":"lib side","comments":[],"closedByPullRequestsReferences":[]}' >"$F/issue-other-lib-5.json"
cat >"$F/issue5.json" <<'J'
{"number":5,"title":"Brute-force on login","url":"https://github.com/acme/app/issues/5","author":{"login":"cy"},"state":"CLOSED",
 "body":"Anyone can guess passwords without limit.","comments":[{"id":"IC1","author":{"login":"cy"},"body":"Seen in prod logs.","createdAt":"2026-02-28T09:00:00Z"}],
 "closedByPullRequestsReferences":[{"number":9},{"number":7}]}
J
echo '{"number":6,"title":"Orphan","url":"https://github.com/acme/app/issues/6","author":{"login":"cy"},"state":"OPEN","body":"","comments":[],"closedByPullRequestsReferences":[]}' >"$F/issue6.json"
cat >"$SB/bin/gh" <<'SH'
#!/usr/bin/env bash
F="$GH_FIX"; R=""; a=("$@"); for i in "${!a[@]}"; do [ "${a[$i]}" = -R ] && R="${a[$((i+1))]}"; done
case "$1 $2" in
  "repo view") [ -z "${GH_NO_REPO:-}" ] || { echo "no git remotes found" >&2; exit 1; }; echo acme/app; exit 0 ;;
  "pr view") f="$F/pr$3.json" ;;
  "issue view") f="$F/issue$3.json"; [ "$R" = acme/app ] || f="$F/issue-${R/\//-}-$3.json" ;;
  api\ repos/acme/app/pulls/*/files) [ -z "${GH_FAIL_FILES:-}" ] || { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
    p="${2#repos/acme/app/pulls/}"; f="$F/pr${p%%/*}.${p#*/}.json" ;;
  api\ repos/acme/app/commits/*) f="$F/commit-${2##*/}.json" ;;
  api\ repos/acme/app/pulls/*) p="${2#repos/acme/app/pulls/}"; f="$F/pr${p%%/*}.${p#*/}.json" ;;
  *) echo "stub gh: unexpected $*" >&2; exit 3 ;;
esac
[ -f "$f" ] && cat "$f" || { echo "GraphQL: Could not resolve to a PullRequest with the number of $3." >&2; exit 1; }
SH
chmod +x "$SB/bin/gh"
R="$SB/repo"; mkdir -p "$R/.flow/tasks/limit" "$SB/home"; git -C "$R" init -q
printf '#9\n' >"$R/.flow/tasks/limit/TICKET"
printf '# Intent · limit\n\n## Goal\nLogin stops brute force\n\n## Approaches\n- chosen: token bucket · cheap\n' >"$R/.flow/tasks/limit/INTENT.md"
printf 'ts\twho\tdecision\twhy\tevidence\treversible\n2026-03-02\tagent\tbucket per account\tIP limits miss botnets\t-\tyes\n' >"$R/.flow/tasks/limit/DECISIONS.tsv"
collect() { (cd "$R" && PATH="$SB/bin:$PATH" GH_FIX="$F" FLOW_STACK_HOME="$SB/home" "$H/collect.sh" "$@"); }

if on collect; then
  collect 9 >"$SB/one.json" 2>"$SB/err"; ck "collect 9 exits 0 ($(head -c 200 "$SB/err"))" '[ -s "$SB/one.json" ]'
  ck "single PR: kind, commits in order, files, hunks split" 'jq -e ".ref.kind==\"pr\" and (.prs|length)==1 and .prs[0].commits[0].sha==\"aaa1111\" and (.prs[0].files|length)==3 and (.prs[0].files[0].hunks|length)==2 and (.prs[0].files[1].hunks[0]|startswith(\"@@ -1,2\"))" "$SB/one.json" >/dev/null'
  ck "reviews, review comments, conversation, checks kept" 'jq -e ".prs[0].reviews[0].id==\"R1\" and .prs[0].review_comments[0].id==77 and .prs[0].review_comments[0].path==\"src/limit.ts\" and .prs[0].comments[0].id==\"C1\" and .prs[0].checks[0].conclusion==\"SUCCESS\"" "$SB/one.json" >/dev/null'
  ck "each commit carries the files it touched" 'jq -e ".prs[0].commits[0].files==[\"src/limit.ts\"] and (.prs[0].commits[1].files|length)==3" "$SB/one.json" >/dev/null'
  ck "linked issue fetched" 'jq -e "(.issues|map(.number))==[5] and .issues[0].comments[0].id==\"IC1\"" "$SB/one.json" >/dev/null'
  ck "omitted patch: file kept, patch_omitted, no hunks" 'jq -e ".prs[0].files[2] | .path==\"dist/bundle.js\" and .patch_omitted==true and .hunks==[]" "$SB/one.json" >/dev/null'
  ck "task matched by TICKET: goal, intent, decisions" 'jq -e ".task.slug==\"limit\" and .task.goal==\"Login stops brute force\" and (.task.intent|test(\"token bucket\")) and .task.decisions[0].decision==\"bucket per account\"" "$SB/one.json" >/dev/null'
  ck "story is empty for Claude to write" 'jq -e ".story==null" "$SB/one.json" >/dev/null'
  collect 5 >"$SB/issue.json" 2>"$SB/err"
  ck "issue: its PRs as chapters in time order" 'jq -e ".ref.kind==\"issue\" and (.prs|map(.number))==[7,9] and .issues[0].number==5" "$SB/issue.json" >/dev/null'
  collect 9 https://github.com/acme/app/pull/7 >"$SB/list.json" 2>"$SB/err"
  ck "PR list (number + URL): one story, time order" 'jq -e ".ref.kind==\"prs\" and (.prs|map(.number))==[7,9]" "$SB/list.json" >/dev/null'
  ck "acme/app#7 form resolves" 'collect acme/app#7 2>/dev/null | jq -e ".prs[0].number==7" >/dev/null'
  ck "issue with no PRs: exit 1, says so" '! collect 6 >/dev/null 2>"$SB/err" && grep -qi "no pull requests" "$SB/err"'
  ck "unknown ref: exit non-zero, names it" '! collect 404 >/dev/null 2>"$SB/err" && grep -q "404" "$SB/err"'
  ck "closed issue in another repo is fetched from that repo" 'collect 11 2>/dev/null | jq -e ".issues==[.issues[0]] and .issues[0].repo==\"other/lib\" and .issues[0].title==\"Lib bug\"" >/dev/null'
  ck "gh failing mid-PR: exit 1 with its message" '! GH_FAIL_FILES=1 collect 9 >/dev/null 2>"$SB/err" && grep -q "could not read the files" "$SB/err"'
  ck "bare number outside a GitHub repo: one clear error" '! GH_NO_REPO=1 collect 9 >/dev/null 2>"$SB/err" && grep -q "not in a GitHub repo" "$SB/err" && [ "$(wc -l <"$SB/err")" -eq 1 ]'
  ck "--task overrides the TICKET match" 'mkdir -p "$R/.flow/tasks/other" && printf "## Goal\nOther goal\n" >"$R/.flow/tasks/other/INTENT.md" && collect 9 --task other | jq -e ".task.slug==\"other\"" >/dev/null'
fi

# a valid story for PR 9 (plus the shared data from collect)
story() {
  collect 9 2>/dev/null | jq '.story = {
    title: "Rate-limit login", summary: "Login gets a per-account token bucket.",
    chapters: [
      {id: "core", title: "The bucket", pr: 9, tier: "read", what: "A token bucket that refills one try per 12s.",
       why: {text: "Scripts could guess passwords forever.", sources: [{kind: "pr-body", pr: 9, quote: "a script could try passwords forever"}, {kind: "commit", pr: 9, ref: "aaa1111"}]},
       refs: [{pr: 9, file: "src/limit.ts", hunks: [0, 1]}]},
      {id: "wire", title: "Login asks the bucket", pr: 9, tier: "read", what: "login() throws tooMany when the bucket is empty.",
       why: {text: "Reviewer asked about clock skew.", sources: [{kind: "review", pr: 9, ref: "R1"}, {kind: "review-comment", pr: 9, ref: 77}, {kind: "issue", ref: 5, quote: "guess passwords without limit"}, {kind: "task", ref: "DECISIONS.tsv:1"}]},
       question: "Why throw instead of returning 429 from the route?",
       refs: [{pr: 9, file: "src/login.ts"}]},
      {id: "gen", title: "Generated bundle", pr: 9, tier: "skip", what: "Rebuilt bundle.", why: null,
       question: "Is dist/bundle.js meant to be committed?", refs: [{pr: 9, file: "dist/bundle.js"}]}]}'
}
render() { "$H/render.sh" "$@"; }

if on refuse; then
  story >"$SB/ok.json"; ck "valid story renders" 'render "$SB/ok.json" "$SB/ok.html" >/dev/null 2>"$SB/err" || { cat "$SB/err"; false; }'
  bad() { jq "$2" "$SB/ok.json" >"$SB/bad.json"; ! render "$SB/bad.json" "$SB/bad.html" >/dev/null 2>"$SB/err" && grep -q -- "$3" "$SB/err" && [ ! -e "$SB/bad.html" ]; }
  ck "no story: refused" 'bad x ".story=null" "story"'
  ck "why with no source and no question: refused, names chapter" 'bad x ".story.chapters[0].why.sources=[]" "core"'
  ck "null why, no question: refused" 'bad x ".story.chapters[2].question=null" "gen"'
  ck "a changed file in no chapter: refused, names it" 'bad x ".story.chapters[1].refs=[]" "src/login.ts"'
  ck "hunk index out of range: refused" 'bad x ".story.chapters[0].refs[0].hunks=[0,5]" "hunk 5"'
  ck "ref to a file not in the PR: refused" 'bad x ".story.chapters[0].refs += [{pr: 9, file: \"src/nope.ts\"}]" "src/nope.ts"'
  ck "commit not in the PR: refused" 'bad x ".story.chapters[0].why.sources[1].ref=\"fff9999\"" "fff9999"'
  ck "review id not in the PR: refused" 'bad x ".story.chapters[1].why.sources[0].ref=\"R9\"" "R9"'
  ck "issue not collected: refused" 'bad x ".story.chapters[1].why.sources[2].ref=42" "42"'
  ck "quote not in its source: refused" 'bad x ".story.chapters[0].why.sources[0].quote=\"bots rule\"" "bots rule"'
  ck "task source with no task: refused" 'bad x ".task=null" "task"'
  ck "unknown tier: refused" 'bad x ".story.chapters[0].tier=\"maybe\"" "tier"'
  ck "source with empty text: refused (hollow citation)" 'bad x ".prs[0].body=\"\"" "is empty"'
  ck "long source cited without a quote: refused" 'bad x "del(.story.chapters[0].why.sources[0].quote)" "add the quote"'
  ck "blank question counts as none" 'bad x ".story.chapters[2].question=\"  \"" "gen"'
  ck "ref listing no hunks: refused" 'bad x ".story.chapters[0].refs[0].hunks=[]" "lists no hunks"'
  ck "a hunk in no chapter: refused, names it" 'bad x ".story.chapters[0].refs[0].hunks=[0]" "hunk 1 is in no chapter"'
  ck "unknown source kind: refused" 'bad x ".story.chapters[0].why.sources[0].kind=\"vibes\"" "vibes"'
fi

if on render; then
  at() { grep -bo "id=\"$2\"" "$1" | head -1 | cut -d: -f1; }  # byte offset: the page body is one line
  story >"$SB/ok.json"
  for fmt in scroll slides timeline; do
    jq --arg f "$fmt" '.format=$f' "$SB/ok.json" >"$SB/$fmt.json"; render "$SB/$fmt.json" "$SB/$fmt.html" >/dev/null 2>&1
    ck "$fmt: page carries its format" 'grep -q "data-format=\"$fmt\"" "$SB/$fmt.html"'
    ck "$fmt: chapters in story order" 'h="$SB/$fmt.html"; a=$(at "$h" ch-core); b=$(at "$h" ch-wire); c=$(at "$h" ch-gen); [ -n "$a" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ]'
  done
  h="$SB/scroll.html"
  ck "title, summary, page title" 'grep -q "<title>Rate-limit login</title>" "$h" && grep -q "per-account token bucket" "$h"'
  ck "hunks drawn with numbered added/removed lines" 'grep -q "<span class=\"ln add\"><span class=\"no\"></span><span class=\"no\">1</span><span class=\"sg\">+</span><span class=\"tx\">export class Bucket" "$h" && grep -q "<span class=\"ln del\"><span class=\"no\">10</span><span class=\"no\"></span><span class=\"sg\">−</span><span class=\"tx\">  old()" "$h"'
  ck "only the referenced hunks of a file" 'grep -q "@@ -10,2 +13,3 @@ refill" "$h"'
  ck "omitted patch says so" 'grep -q "patch not shown" "$h"'
  ck "sources cited with links: commit, review, issue, quote" 'grep -q "https://github.com/acme/app/commit/aaa1111" "$h" && grep -q "href=\"https://github.com/acme/app/pull/9#discussion_r77\"" "$h" && grep -q "review by bo · changes requested" "$h" && grep -q "https://github.com/acme/app/issues/5" "$h" && grep -q "a script could try passwords forever" "$h"'
  ck "questions for the author collected, both of them" '[ "$(grep -o "class=\"question\"" "$h" | wc -l)" -ge 2 ] && grep -q "Is dist/bundle.js meant to be committed?" "$h" && grep -q "Questions for the author" "$h"'
  ck "tiers shown" 'grep -q "tier-read" "$h" && grep -q "tier-skip" "$h"'
  ck "values escaped" '! grep -q "<b>x</b>" "$h" && ! grep -q "never says no </script>" "$h"'
  ck "timeline: PR events (opened, commits, review, merged)" 'grep -q "class=\"ev" "$SB/timeline.html" && grep -q "CHANGES_REQUESTED\|changes requested" "$SB/timeline.html" && grep -q "merged" "$SB/timeline.html"'
  ck "footer links to the skill" 'grep -q "Built by <a href=\"https://github.com/nayanraj210401/flow-stack/tree/main/plugins/flow-stack/skills/pr-chapters\">flow-stack pr-chapters</a>" "$h"'
  s="$SB/slides.html"; t="$SB/timeline.html"
  ck "slides: a claim slide per chapter" '[ "$(grep -o "class=\"chapter slide claim" "$s" | wc -l)" -eq 3 ]'
  ck "slides: one slide per shown hunk (2 + 1 + omitted 1)" '[ "$(grep -o "class=\"slide hs " "$s" | wc -l)" -eq 4 ] && grep -q "hunk 2 of 2" "$s"'
  ck "slides: hunk slides show the whole hunk, captioned" 'grep -q "<p class=\"cap\">A token bucket that refills one try per 12s.</p>" "$s"'
  ck "slides: questions are a checklist" '[ "$(grep -o "type=\"checkbox\"" "$s" | wc -l)" -eq 2 ] && ! grep -q "type=\"checkbox\"" "$h"'
  ck "timeline: metrics from real times" 'grep -q "<dt>First review</dt><dd>5h after opening</dd>" "$t" && grep -q "<dt>Open → merged</dt><dd>1d 2h</dd>" "$t" && grep -q "<dt>Reviews</dt><dd>2</dd>" "$t"'
  ck "timeline: a lane per PR on a to-scale axis, quiet gaps labeled" 'grep -q "lane-label\">PR #9<" "$t" && grep -q "mk review r-changes_requested\" style=\"left:" "$t" && grep -q "19h quiet" "$t"'
  ck "timeline: each chapter sits under the commit that first touched its files" 'a=$(at "$t" ch-core); w=$(at "$t" ch-wire); c1=$(grep -bo "aaa1111</code>" "$t" | head -1 | cut -d: -f1); c2=$(grep -bo "bbb2222</code>" "$t" | head -1 | cut -d: -f1); [ "$c1" -lt "$a" ] && [ "$a" -lt "$c2" ] && [ "$c2" -lt "$w" ]'
  ck "timeline: read chapters open, others folded" 'grep -q "<details class=\"fold chapter tier-read\" id=\"ch-core\" open>" "$t" && grep -q "<details class=\"fold chapter tier-skip\" id=\"ch-gen\"><summary>" "$t"'
  ck "a story.jq in the working directory doesn't hijack render" '(cd "$SB" && echo ". = 1" >story.jq && "$H/render.sh" "$SB/ok.json" "$SB/cwd.html" >/dev/null 2>&1) && grep -q "id=\"ch-core\"" "$SB/cwd.html"'
  ck "slides: nav present" 'grep -q "id=\"slide-nav\"" "$SB/slides.html"'
fi

if on format; then
  ck "default format is scroll" 'collect 9 | jq -e ".format==\"scroll\"" >/dev/null'
  ck "settings.sh chapters format slides writes it" '(cd "$R" && FLOW_STACK_HOME="$SB/home" "$SETTINGS" chapters format slides >/dev/null) && jq -e ".chapters.format==\"slides\"" "$SB/home/settings.json" >/dev/null'
  ck "collect carries the setting" 'collect 9 | jq -e ".format==\"slides\"" >/dev/null'
  ck "settings.sh chapters format prints it" '(cd "$R" && FLOW_STACK_HOME="$SB/home" "$SETTINGS" chapters format) | grep -q slides'
  ck "unknown format refused" '! (cd "$R" && FLOW_STACK_HOME="$SB/home" "$SETTINGS" chapters format poster) 2>/dev/null'
  ck "--format overrides the setting" 'collect 9 --format timeline | jq -e ".format==\"timeline\"" >/dev/null'
fi

[ $fail = 0 ] && echo "chapters ($want): $pass passed" || exit 1
