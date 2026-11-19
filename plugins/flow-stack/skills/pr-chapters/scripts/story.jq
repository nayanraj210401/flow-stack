# story.jq: check a story and draw it. Input: collect.sh's JSON with .story filled.
#   jq -r 'errors[]'  every reason the story can't be published, one per line (none: it can)
#   jq -r 'page'      the page body, HTML, every value escaped

def prs_by_n: reduce .prs[] as $p ({}; .[$p.number | tostring] = $p);
def norm: ascii_downcase | gsub("\\s+"; " ");
def blank: (. // "") | tostring | test("^\\s*$");
# long sources a why must quote from, so the link proves the claim
def needs_quote($s): (["pr-body", "issue"] | index($s.kind)) != null or ($s.kind == "task" and ($s.ref // "INTENT.md") == "INTENT.md");
# a review's verdict: its body's "Verdict: x" first line, else its GitHub state
def verdict: ((.body // "") | (split("\n")[0] // "") | gsub("\\*"; "") | capture("(?i)^\\s*verdict:?\\s*(?<v>[a-z]+)")?.v | ascii_downcase) // (.state | ascii_downcase | gsub("_"; " "));
def kinds: ["pr-body", "commit", "review", "review-comment", "comment", "issue", "task"];

# the text and link a source points at, or null when it points at nothing that was collected
def resolve($s; $ch; $root): [
  ($root | prs_by_n) as $by | ($s.pr // $ch.pr) as $n | $by[$n | tostring] as $p
  | if $s.kind == "issue" then
      ($root.issues[] | select(.number == ($s.ref | tonumber? // -1)))
      | {text: ([.body] + [.comments[].body] | join("\n")), url, label: "issue #\(.number)"}
    elif $s.kind == "task" then
      if $root.task == null then null
      elif ($s.ref // "INTENT.md") == "INTENT.md" then {text: $root.task.intent, url: null, label: "flow task \($root.task.slug) · INTENT"}
      else (($s.ref | tostring | capture("^DECISIONS\\.tsv:(?<i>[0-9]+)$")?.i | tonumber) as $i
        | $root.task.decisions[$i - 1] // empty
        | {text: "\(.decision) \(.why)", url: null, label: "flow task \($root.task.slug) · decision \($i)"}) // null end
    elif $p == null then null
    elif $s.kind == "pr-body" then {text: $p.body, url: $p.url, label: "PR #\($p.number) description"}
    elif $s.kind == "commit" then
      ($p.commits[] | select(($s.ref | tostring | length) >= 7 and (.sha | startswith($s.ref | tostring))))
      | {text: "\(.headline)\n\(.body)", url: "https://github.com/\($p.repo)/commit/\(.sha)", label: "commit \(.sha[0:7])"}
    elif $s.kind == "review" then
      ($p.reviews[] | select(.id == $s.ref)) | {text: .body, url: $p.url, label: "review by \(.author) · \(verdict)"}
    elif $s.kind == "review-comment" then
      ($p.review_comments[] | select((.id | tostring) == ($s.ref | tostring)))
      | {text: .body, url: "\($p.url)#discussion_r\(.id)", label: "\(.author) on \(.path)"}
    elif $s.kind == "comment" then
      ($p.comments[] | select(.id == $s.ref)) | {text: .body, url: $p.url, label: "comment by \(.author)"}
    else null end ] | .[0];

# when a status source was written: a commit's date, a review's or a comment's time; null for anything else
def when_of($p): . as $s | [
  if $s.kind == "commit" then ($p.commits[] | select(($s.ref | tostring | length) >= 7 and (.sha | startswith($s.ref | tostring))) | .date)
  elif $s.kind == "review" then ($p.reviews[] | select(.id == $s.ref) | .submittedAt)
  elif $s.kind == "comment" then ($p.comments[] | select(.id == $s.ref) | .createdAt)
  else empty end] | .[0];

def errors:
  . as $root | (prs_by_n) as $by
  | if (.story | type) != "object" or ((.story.chapters // []) | length) == 0 then ["no story: fill .story with a title, a summary and chapters (see SKILL.md)"]
    else
      [ (.story.chapters | map(.id) | group_by(.)[] | select(length > 1) | "chapter id \(.[0]) is used twice"),
        (.story.chapters[] as $ch | ($ch.id // "?") as $id
         | ( (if ($id | tostring | test("^[a-z0-9-]+$")) then empty else "chapter \($id): id must be lowercase letters, digits and dashes" end),
             (if $by[$ch.pr | tostring] then empty else "chapter \($id): PR \($ch.pr) is not in this story" end),
             (if (["read", "skim", "skip"] | index($ch.tier)) then empty else "chapter \($id): tier '\($ch.tier)' is not read, skim or skip" end),
             (if ($ch.title | type) == "string" and ($ch.what | type) == "string" then empty else "chapter \($id): needs a title and a what" end),
             (if (($ch.why.sources // []) | length) > 0 or ($ch.question | blank | not) then empty
              else "chapter \($id): the why has no source and there is no question for the author; cite where the why is written, or ask" end),
             ($ch.why.sources[]? as $s
              | if (kinds | index($s.kind)) == null then "chapter \($id): source kind '\($s.kind)' is not one of \(kinds | join(", "))"
                else (resolve($s; $ch; $root)) as $r
                | if $r == null then "chapter \($id): \($s.kind) \($s.ref // "") was not collected for this story"
                  elif ($r.text | blank) then "chapter \($id): \($r.label) is empty, so it can't carry a why"
                  elif needs_quote($s) and ($s.quote | blank) then "chapter \($id): \($r.label) is long; add the quote that carries the why"
                  elif ($s.quote | blank | not) and (($r.text | norm) | contains($s.quote | norm) | not) then "chapter \($id): quote \"\($s.quote)\" is not in \($r.label)"
                  else empty end end),
             ($ch.refs[]? as $f | ($by[($f.pr // $ch.pr) | tostring]) as $p
              | ($p.files // [] | map(select(.path == $f.file)) | .[0]) as $file
              | if $file == null then "chapter \($id): \($f.file) is not a file of PR \($f.pr // $ch.pr)"
                elif $f.hunks == [] then "chapter \($id): \($f.file) lists no hunks; leave hunks out to show the whole file"
                else ($f.hunks[]? | select(. >= ($file.hunks | length) or . < 0) | "chapter \($id): \($f.file) has no hunk \(.) (it has \($file.hunks | length))") end) )),
        (.prs[] as $p | $p.files[] | .path as $path | (.hunks | length) as $nh
         | [$root.story.chapters[] | .pr as $cp | .refs[]? | select((.pr // $cp) == $p.number and .file == $path)] as $rs
         | if ($rs | length) == 0 then "\($path) (PR #\($p.number)) is in no chapter; every changed file goes in one, tests and generated files in a skip chapter"
           elif any($rs[]; .hunks == null) then empty
           else ([range($nh)] - [$rs[].hunks[]]) | .[] | "\($path) (PR #\($p.number)): hunk \(.) is in no chapter" end),
        # rounds: a finding quotes its review; a status other than unknown quotes a later commit, review or comment that says so
        ((.story.rounds // [])[] as $rd | ($rd.pr // $root.prs[0].number) as $n | $by[$n | tostring] as $p
         | ([$p.reviews[]? | select(.id == $rd.review)] | .[0]) as $rv | "round \($rd.review)" as $at
         | if $p == null then "\($at): PR \($n) is not in this story"
           elif $rv == null then "\($at): no such review on PR #\($n)"
           else ($rd.findings // [])[] as $f
             | if ($f.text | blank) then "\($at): a finding needs text"
               elif ($f.quote | blank) then "\($at): finding \"\($f.text)\" needs the sentence from the review that raises it"
               elif (($rv.body | norm) | contains($f.quote | norm) | not) then "\($at): quote \"\($f.quote)\" is not in that review"
               elif (["fixed", "partly", "open", "unknown"] | index($f.status)) == null then "\($at): status '\($f.status)' is not fixed, partly, open or unknown"
               elif $f.status == "unknown" then empty
               elif $f.source == null then "\($at): \"\($f.text)\" is \($f.status) by whose word? cite the later commit, review or comment that says so, or use unknown"
               else ([$f.source] | map(when_of($p)) | .[0]) as $t | resolve($f.source; {pr: $n}; $root) as $r
                 | if $r == null or $t == null then "\($at): \($f.source.kind) \($f.source.ref // "") was not collected, or can't settle a finding (use a commit, review or comment)"
                   elif $t <= $rv.submittedAt then "\($at): \($r.label) came before the review, so it can't settle \"\($f.text)\""
                   elif ($f.source.quote | blank) then "\($at): add the words from \($r.label) that settle \"\($f.text)\""
                   elif (($r.text | norm) | contains($f.source.quote | norm) | not) then "\($at): quote \"\($f.source.quote)\" is not in \($r.label)"
                   else empty end end end) ]
    end;

# ---- drawing
def e: tostring | @html;
def when($c; s): if $c then s else "" end;
def ago($t): $t | if . then (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | strftime("%b %-d, %H:%M")) else "" end;
def pad2: tostring | if length < 2 then "0" + . else . end;
def plural($n; $w): "\($n) \($w)\(when($n != 1; "s"))";
def tierlabel: {read: "Read closely", skim: "Skim", skip: "Safe to skip"}[.] // .;

# one diff row: old and new line numbers, the sign, the code
def row: "<span class=\"ln \(.k)\"><span class=\"no\">\(.o // "")</span><span class=\"no\">\(.n // "")</span><span class=\"sg\">\(.s)</span><span class=\"tx\">\(.t | e)</span></span>";
def hunk($tier):
  split("\n") as $ls
  | (($ls[0] | capture("^@@ -(?<o>[0-9]+)(,[0-9]+)? \\+(?<n>[0-9]+)")?) // {o: "1", n: "1"}) as $h
  | (reduce $ls[1:][] as $l ({o: ($h.o | tonumber), n: ($h.n | tonumber), rows: []};
      if ($l | startswith("+")) then .rows += [{k: "add", o: null, n: .n, s: "+", t: $l[1:]}] | .n += 1
      elif ($l | startswith("-")) then .rows += [{k: "del", o: .o, n: null, s: "−", t: $l[1:]}] | .o += 1
      elif ($l | startswith("\\")) then .rows += [{k: "note", o: null, n: null, s: "", t: $l}]
      else .rows += [{k: "ctx", o: .o, n: .n, s: "", t: ($l[1:] // "")}] | .o += 1 | .n += 1 end) | .rows) as $rows
  | ({read: 80, skim: 24, skip: 10, full: 400}[$tier] // 40) as $cap
  | "<div class=\"hunk\"><div class=\"hh\">\($ls[0] | e)</div><pre><code>"
    + ($rows[0:$cap] | map(row) | join(""))
    + "</code></pre>"
    + when(($rows | length) > $cap; "<details class=\"more\"><summary>Show \(plural(($rows | length) - $cap; "more line"))</summary><pre><code>" + ($rows[$cap:] | map(row) | join("")) + "</code></pre></details>")
    + "</div>";
def figcap($f):
  ($f.path | split("/")) as $parts
  | "<figcaption><span class=\"path\"><span class=\"dir\">\(($parts[:-1] | join("/")) | if . == "" then "" else . + "/" end | e)</span><b>\($parts[-1] | e)</b></span>"
    + "<span class=\"delta\"><span class=\"st st-\($f.status | e)\">\($f.status | e)</span><span class=\"plus\">+\($f.additions)</span><span class=\"minus\">−\($f.deletions)</span></span></figcaption>";
def omitted($p): "<p class=\"omitted\">Large or binary file: patch not shown. <a href=\"\($p.url | e)/files\">Open it on GitHub ↗</a></p>";
def fileref($p; $tier):
  .file as $path | (.hunks // null) as $want | ($p.files[] | select(.path == $path)) as $f
  | "<figure class=\"file\">" + figcap($f)
    + (if $f.patch_omitted then omitted($p)
       else ([$f.hunks | to_entries[] | select($want == null or (.key as $k | $want | index($k))) | .value | hunk($tier)] | join("")) end)
    + "</figure>";
def sources($ch; $root):
  "<ol class=\"sources\">" + ([.why.sources[] as $s | resolve($s; $ch; $root) as $r
    | "<li><span class=\"src-kind\">\($s.kind | gsub("-"; " ") | e)</span>"
      + (if $r.url then "<a href=\"\($r.url | e)\">\($r.label | e) ↗</a>" else "<span class=\"src-label\">\($r.label | e)</span>" end)
      + when(($s.quote // "") != ""; "<q>\($s.quote | e)</q>") + "</li>"] | join("")) + "</ol>";
def chhead($root; $num):
  "<header class=\"ch-head\"><span class=\"ch-num\">\($num | pad2)</span><div class=\"ch-title\">"
  + "<p class=\"ch-meta\"><span class=\"pill tier-\(.tier | e)\">\(.tier | tierlabel | e)</span>"
  + when(($root.prs | length) > 1; "<span>PR #\(.pr)</span>")
  + "<span>\(plural((.refs // []) | length; "file"))</span></p><h2>\(.title | e)</h2></div></header>";
def chtext($root):
  . as $ch
  | "<div class=\"ch-text\"><p class=\"what\">\(.what | e)</p>"
    + (if ((.why.sources // []) | length) > 0 then
        "<section class=\"why\"><h3>Why</h3><p>\(.why.text // "" | e)</p>" + sources($ch; $root) + "</section>"
       else "<section class=\"why missing\"><h3>Why</h3><p>\(when((.why.text // "") != ""; (.why.text | e) + " "))Nobody wrote the reason down in the PR, its commits, its reviews, or its ticket.</p></section>" end)
    + when((.question // "") != ""; "<aside class=\"ask\"><h3>Ask the author</h3><p>\(.question | e)</p></aside>")
    + "</div>";
def chgrid($root):
  . as $ch
  | "<div class=\"ch-grid\">" + chtext($root) + "<div class=\"ch-code\">"
    + (if ((.refs // []) | length) > 0 then ([.refs[] | . as $f | fileref(($root | prs_by_n)[($f.pr // $ch.pr) | tostring]; $ch.tier)] | join("")) else "<p class=\"nocode\">No code in this chapter.</p>" end)
    + "</div></div>";
def chapter($root; $num):
  "<article class=\"chapter slide tier-\(.tier | e)\" id=\"ch-\(.id | e)\">" + chhead($root; $num) + chgrid($root) + "</article>";
def prhead($p):
  "<section class=\"pr-head\"><p class=\"kicker\"><a href=\"\($p.url | e)\">PR #\($p.number) ↗</a><span class=\"state st-\($p.state | ascii_downcase | e)\">\($p.state | ascii_downcase | e)</span></p><h2>\($p.title | e)</h2>"
  + "<p class=\"meta\"><code>\($p.head | e)</code> → <code>\($p.base | e)</code> · \($p.author | e) · <span class=\"plus\">+\($p.additions)</span> <span class=\"minus\">−\($p.deletions)</span></p></section>";

# ---- slides: per chapter, a claim slide (what, why, ask) then one slide per hunk, the diff full screen
def slides($root; $num):
  . as $ch
  | [($ch.refs // [])[] as $f | (($root | prs_by_n)[($f.pr // $ch.pr) | tostring]) as $p | ($p.files[] | select(.path == $f.file)) as $file
      | if $file.patch_omitted then {f: $f, p: $p, file: $file, h: null, k: 0, n: 1}
        else ($file.hunks | length) as $n
          | ($file.hunks | to_entries[] | select(($f.hunks // null) == null or (.key as $k | $f.hunks | index($k))) | {f: $f, p: $p, file: $file, h: .value, k: .key, n: $n}) end] as $hs
  | "<article class=\"chapter slide claim tier-\($ch.tier | e)\" id=\"ch-\($ch.id | e)\" data-tier=\"\($ch.tier | e)\">"
    + chhead($root; $num) + chtext($root)
    + when(($hs | length) > 0; "<p class=\"next-up\">Next: \(plural($hs | length; "hunk")) →</p>") + "</article>"
    + ([$hs | to_entries[] | .key as $i | .value as $x
        | "<section class=\"slide hs tier-\($ch.tier | e)\" data-tier=\"\($ch.tier | e)\"><div class=\"hs-cap\"><span class=\"hs-num\">\($num | pad2)<small>.\($i + 1)</small></span>"
          + "<div><p class=\"ch-meta\"><span>\($ch.title | e)</span><span>hunk \($x.k + 1) of \($x.n)</span></p><p class=\"cap\">\(($x.f.note // $ch.what) | e)</p></div></div>"
          + "<figure class=\"file\">" + figcap($x.file) + (if $x.h == null then omitted($x.p) else ($x.h | hunk("full")) end) + "</figure></section>"] | join(""));

# ---- rounds: each review, what it found, what each finding became, and the commits that followed
def vclass: if test("ship|approved") then "ok" elif test("block|changes") then "bad" elif test("fix") then "warn" else "mute" end;
def stlabel: {fixed: "fixed", partly: "partly fixed", open: "still open", unknown: "no later word"}[.] // .;
def realcommits($p): [$p.commits[] | select(.headline | startswith("Merge ") | not)];
def commitlist($p):
  if length == 0 then "" else "<ul class=\"commits\">" + (map("<li><a href=\"https://github.com/\($p.repo)/commit/\(.sha)\"><code>\(.sha[0:7])</code></a><span class=\"hl\">\(.headline | e)</span>"
    + when(.files != null; "<span class=\"nf\">\(plural(.files | length; "file"))</span>") + "</li>") | join("")) + "</ul>" end;
def rounds($root):
  ($root.story.rounds // []) as $notes
  | [$root.prs[] as $p
     | ([$p.reviews[] | select(.submittedAt != null and ((.body | blank | not) or .state != "COMMENTED"))] | sort_by(.submittedAt)) as $rvs
     | realcommits($p) as $cs
     | when(($root.prs | length) > 1; prhead($p))
       + "<ol class=\"rd-list\">"
       + "<li class=\"rd start\"><span class=\"rd-mark\"></span><div class=\"rd-body\"><p class=\"rd-h\"><b>Opened</b><span>by \($p.author | e)</span><time>\(ago($p.createdAt) | e)</time></p>"
         + ([$cs[] | select(($rvs | length) == 0 or .date < $rvs[0].submittedAt)] | if length > 0 then "<p class=\"rd-then\">\(plural(length; "commit")) before the first review</p>" + commitlist($p) else "" end) + "</div></li>"
       + ([$rvs | to_entries[] | .key as $i | .value as $rv | ($rvs[$i + 1].submittedAt // null) as $next
           | ($rv | verdict) as $v
           | ([$notes[] | select(.review == $rv.id)] | .[0].findings // null) as $fs
           | [$cs[] | select(.date > $rv.submittedAt and ($next == null or .date <= $next))] as $after
           | "<li class=\"rd v-\($v | vclass)\"><span class=\"rd-mark\">\($i + 1)</span><div class=\"rd-body\"><p class=\"rd-h\"><b>Round \($i + 1)</b><span class=\"vd\">\($v | e)</span><span>by \($rv.author | e)</span><time>\(ago($rv.submittedAt) | e)</time><a href=\"\($p.url | e)\">review ↗</a></p>"
             + (if $fs != null and ($fs | length) > 0 then
                 "<ul class=\"findings\">" + ([$fs[] | . as $f | (if .source then resolve(.source; {pr: $p.number}; $root) else null end) as $r
                   | "<li><span class=\"fs fs-\(.status | e)\">\(.status | stlabel | e)</span><div><p>\(.text | e)</p><q>\(.quote | e)</q>"
                     + when($r != null; "<p class=\"by\">" + (if $r.url then "<a href=\"\($r.url | e)\">\($r.label | e) ↗</a>" else ($r.label | e) end) + when((.source.quote | blank | not); " <q>\(.source.quote | e)</q>") + "</p>")
                     + "</div></li>"] | join("")) + "</ul>"
               elif ($rv.body | blank) then "<p class=\"rd-none\">No comments.</p>"
               else "<p class=\"rd-none\">Findings not summarized here. <a href=\"\($p.url | e)\">Read the review ↗</a></p>" end)
             + when(($after | length) > 0; "<p class=\"rd-then\">Then \(plural($after | length; "commit"))</p>" + ($after | commitlist($p)))
             + "</div></li>"] | join(""))
       + "</ol>"] | join("") as $body
  | ([$notes[] | .review as $id | .findings[]? | select(.status == "open" or .status == "unknown") | . + {review: $id}]) as $open
  | "<section class=\"rounds\" id=\"rounds\"><h2 class=\"sec-h\">Review rounds</h2>" + $body
    + when(($open | length) > 0; "<div class=\"still-open\"><h3>Not settled on the current head</h3><ul>" + ($open | map("<li><span class=\"fs fs-\(.status | e)\">\(.status | stlabel | e)</span>\(.text | e)</li>") | join("")) + "</ul></div>")
    + "</section>";

def page:
  . as $root | .story as $s | ($s.chapters | to_entries | map(.value + {num: (.key + 1)})) as $chs
  | ([.prs[].repo] | unique | join(", ")) as $repos
  | [$chs[] | select((.question // "") != "")] as $qs
  | ([.prs[].reviews[] | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED")] | last) as $verdict
  | "<div class=\"story\" data-format=\"\(.format | e)\">"
    + "<header class=\"hero slide on\" id=\"cover\"><div class=\"hero-in\"><div class=\"hero-main\">"
    + "<p class=\"kicker\"><span class=\"repo\">\($repos | e)</span>"
    + (if .ref.kind == "issue" then "<a href=\"\(.issues[0].url | e)\">Issue #\(.issues[0].number) ↗</a><span>\(plural(.prs | length; "PR"))</span>"
       elif (.prs | length) > 1 then "<span>\(plural(.prs | length; "PR"))</span>"
       else "<a href=\"\(.prs[0].url | e)\">PR #\(.prs[0].number) ↗</a><span class=\"state st-\(.prs[0].state | ascii_downcase | e)\">\(.prs[0].state | ascii_downcase | e)</span>" end)
    + "</p><h1>\($s.title | e)</h1><p class=\"summary\">\($s.summary // "" | e)</p>"
    + "<dl class=\"stats\">"
    + "<div><dt>Change</dt><dd><span class=\"plus\">+\([.prs[].additions] | add)</span> <span class=\"minus\">−\([.prs[].deletions] | add)</span></dd></div>"
    + "<div><dt>Files</dt><dd>\([.prs[].files | length] | add)</dd></div>"
    + "<div><dt>Commits</dt><dd>\([.prs[].commits | length] | add)</dd></div>"
    + "<div><dt>Author</dt><dd>\([.prs[].author] | unique | join(", ") | e)</dd></div>"
    + when($verdict != null; "<div><dt>Last review</dt><dd>\($verdict.state | ascii_downcase | gsub("_"; " ") | e)</dd></div>")
    + when(.task != null; "<div><dt>Flow task</dt><dd><code>\(.task.slug | e)</code></dd></div>")
    + "</dl></div>"
    + "<nav class=\"plan\" aria-label=\"Reading plan\"><h2>Reading plan</h2><ol>"
    + ($chs | map("<li><a href=\"#ch-\(.id | e)\"><span class=\"n\">\(.num | pad2)</span><span class=\"t\">\(.title | e)</span><span class=\"dot tier-\(.tier | e)\" title=\"\(.tier | tierlabel | e)\"></span></a></li>") | join(""))
    + "</ol><p class=\"legend\"><span><i class=\"dot tier-read\"></i>read closely</span><span><i class=\"dot tier-skim\"></i>skim</span><span><i class=\"dot tier-skip\"></i>safe to skip</span></p>"
    + when(($qs | length) > 0; "<a class=\"qjump\" href=\"#questions\"><b>\($qs | length)</b> \(when(($qs | length) == 1; "question"))\(when(($qs | length) > 1; "questions")) the PR doesn’t answer →</a>")
    + "</nav></div></header>"
    + "<main class=\"chapters\">"
    + (if .format == "slides" then
        ([$chs[] | slides($root; .num)] | join(""))
       else
        when(.format == "rounds"; rounds($root) + "<h2 class=\"sec-h\">The change, chapter by chapter</h2>")
        + ([$chs | to_entries[] | .value as $c | (if .key == 0 then null else $chs[.key - 1].pr end) as $prev
          | when(($root.prs | length) > 1 and $c.pr != $prev; prhead(($root | prs_by_n)[$c.pr | tostring]))
            + ($c | chapter($root; $c.num))] | join(""))
       end)
    + when(($qs | length) > 0; "<section class=\"questions slide\" id=\"questions\"><div class=\"q-head\"><div><h2>Questions for the author</h2><p>The PR, its commits, reviews and ticket don’t answer these. Paste them into your review.</p></div><button type=\"button\" id=\"copy-qs\">Copy all</button></div><ol>"
        + ($qs | map("<li class=\"question\" data-q=\"\(.question | e)\">" + when($root.format == "slides"; "<input type=\"checkbox\" id=\"q-\(.id | e)\" aria-label=\"Asked\">") + "<a href=\"#ch-\(.id | e)\">Ch \(.num | pad2)</a><p>\(.question | e)</p></li>") | join("")) + "</ol></section>")
    + "</main>"
    + "<footer class=\"foot\">Built by <a href=\"https://github.com/nayanraj210401/flow-stack/tree/main/plugins/flow-stack/skills/pr-chapters\">flow-stack pr-chapters</a> from GitHub\(when(.task != null; " and the flow task")) · \(ago(.generated) | e) UTC · every why links to where it is written</footer>"
    + when(.format == "slides"; "<nav id=\"slide-nav\" aria-label=\"Chapters\"><button id=\"prev\" type=\"button\">← Prev</button><span id=\"slide-pos\"></span><button id=\"next\" type=\"button\">Next →</button></nav>")
    + "</div>";
