# story.jq: check a story and draw it. Input: collect.sh's JSON with .story filled.
#   jq -r 'errors[]'  every reason the story can't be published, one per line (none: it can)
#   jq -r 'page'      the page body, HTML, every value escaped

def prs_by_n: reduce .prs[] as $p ({}; .[$p.number | tostring] = $p);
def norm: ascii_downcase | gsub("\\s+"; " ");
def blank: (. // "") | tostring | test("^\\s*$");
# long sources a why must quote from, so the link proves the claim
def needs_quote($s): (["pr-body", "issue"] | index($s.kind)) != null or ($s.kind == "task" and ($s.ref // "INTENT.md") == "INTENT.md");
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
      ($p.reviews[] | select(.id == $s.ref)) | {text: .body, url: $p.url, label: "review by \(.author) · \(.state | ascii_downcase | gsub("_"; " "))"}
    elif $s.kind == "review-comment" then
      ($p.review_comments[] | select((.id | tostring) == ($s.ref | tostring)))
      | {text: .body, url: "\($p.url)#discussion_r\(.id)", label: "\(.author) on \(.path)"}
    elif $s.kind == "comment" then
      ($p.comments[] | select(.id == $s.ref)) | {text: .body, url: $p.url, label: "comment by \(.author)"}
    else null end ] | .[0];

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
           else ([range($nh)] - [$rs[].hunks[]]) | .[] | "\($path) (PR #\($p.number)): hunk \(.) is in no chapter" end) ]
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

# ---- timeline: real time, to scale
def secs: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
def dur: (. / 60 | floor) as $m
  | if $m < 60 then "\($m)m" elif $m < 1440 then "\($m / 60 | floor)h" + when($m % 60 > 0 and $m < 600; " \($m % 60)m")
    else "\($m / 1440 | floor)d" + when(($m % 1440) >= 60; " \(($m % 1440) / 60 | floor)h") end;
def evs($p):
  ([{t: $p.createdAt, k: "open", s: "Opened by \($p.author)"}]
   + [$p.commits[] | {t: .date, k: "commit", s: .headline, sha: .sha}]
   + [$p.reviews[] | {t: .submittedAt, k: "review", st: (.state | ascii_downcase), s: "\(.author) \(.state | ascii_downcase | gsub("_"; " "))"}]
   + [$p.comments[] | {t: .createdAt, k: "comment", s: "\(.author) commented"}]
   + (if $p.mergedAt then [{t: $p.mergedAt, k: "merged", s: "Merged into \($p.base)"}] else [] end))
  | map(select(.t != null) | .x = (.t | secs)) | sort_by(.x);
# the first commit that touched any file of the chapter: where its code was written
def pin($p): [.refs[]?.file] as $fs
  | [$p.commits[] | select((.files // []) as $cf | any($fs[]; . as $x | $cf | index($x) != null))] | sort_by(.date) | (.[0].sha // null);
def gaps: sort_by(.x) | [range(1; length) as $i | {a: .[$i - 1].x, b: .[$i].x}];
def axis($root):
  ([$root.prs[] | evs(.)[]] + [$root.issues[] | select(.createdAt) | {x: (.createdAt | secs), k: "issue"}]) as $all
  | ($all | map(.x) | min) as $t0
  | ([$all[].x] + (if any($root.prs[]; .mergedAt == null) then [now] else [] end) | max) as $t1
  | ([$t1 - $t0, 1] | max) as $span
  | def pos($x): ((($x - $t0) / $span * 1000) | round) / 10;
    def mk($cls; $x; $title): "<i class=\"mk \($cls)\" style=\"left:\(pos($x))%\" title=\"\($title | e)\"></i>";
  ($all | gaps | map(select(.b - .a > ([43200, $span * 0.15] | max)))) as $quiet
  | "<section class=\"tl-axis\" aria-label=\"Time to scale\"><div class=\"tl-scale\"><span>\(ago($t0 | todate) | e)</span><span>\(($t1 - $t0) | dur) end to end</span><span>\(ago($t1 | todate) | e)</span></div><div class=\"lanes\">"
    + ([$root.issues[] | select(.createdAt) | "<div class=\"lane\"><span class=\"lane-label\">Issue #\(.number)</span><div class=\"track\">" + mk("issue"; .createdAt | secs; "Issue #\(.number) opened") + "</div></div>"] | join(""))
    + ([$root.prs[] as $p | evs($p) as $ev | ($p.createdAt | secs) as $a | (if $p.mergedAt then $p.mergedAt | secs else $t1 end) as $b
        | "<div class=\"lane\"><span class=\"lane-label\">PR #\($p.number)</span><div class=\"track\">"
          + "<span class=\"bar\(when($p.mergedAt == null; " open"))\" style=\"left:\(pos($a))%;width:\([pos($b) - pos($a), 0.6] | max)%\"></span>"
          + ([$ev[] | select(.k != "open") | mk(.k + when(.st; " r-" + .st); .x; "\(ago(.t)) · \(.s)")] | join(""))
          + "</div></div>"] | join(""))
    + when(($quiet | length) > 0; "<div class=\"lane quiet\"><span class=\"lane-label\"></span><div class=\"track\">"
        + ($quiet | map("<span class=\"gap\" style=\"left:\(pos(.a))%;width:\(pos(.b) - pos(.a))%\"><b>\((.b - .a) | dur) quiet</b></span>") | join("")) + "</div></div>")
    + "</div><p class=\"tl-key\"><span><i class=\"mk commit\"></i>commit</span><span><i class=\"mk review r-commented\"></i>review</span><span><i class=\"mk review r-changes_requested\"></i>changes requested</span><span><i class=\"mk review r-approved\"></i>approved</span><span><i class=\"mk merged\"></i>merged</span></p></section>";
def metrics($root):
  ([$root.prs[].createdAt | secs] | min) as $open
  | ([$root.prs[].reviews[].submittedAt | select(.) | secs] | min) as $first
  | ([$root.prs[] | evs(.)[]] | gaps | map(.b - .a) | max) as $quiet
  | def m($label; $value): "<div><dt>\($label)</dt><dd>\($value | e)</dd></div>";
  "<dl class=\"stats metrics\">"
  + m("Open → merged"; if all($root.prs[]; .mergedAt) then (([$root.prs[].mergedAt | secs] | max) - $open | dur) else "still open" end)
  + m("First review"; if $first then ($first - $open | dur) + " after opening" else "none yet" end)
  + m("Reviews"; [$root.prs[].reviews[]] | length | tostring)
  + m("Commits after first review"; if $first then [$root.prs[].commits[] | select((.date | secs) > $first)] | length | tostring else "–" end)
  + when($quiet != null; m("Longest quiet"; $quiet | dur))
  + "</dl>";
def tlpr($root; $chs; $p):
  [$chs[] | select(.pr == $p.number) | . + {pin: pin($p)}] as $mine
  | evs($p) as $ev | [$ev[] | select(.k == "review" and .st == "changes_requested") | .x] as $crs
  | def fold: "<details class=\"fold chapter tier-\(.tier | e)\" id=\"ch-\(.id | e)\"\(when(.tier == "read"; " open"))><summary>" + chhead($root; .num) + "</summary>" + chgrid($root) + "</details>";
  "<section class=\"pr-group\">" + prhead($p) + "<ol class=\"rail\">"
  + ([$ev[] | . as $v
      | "<li class=\"ev \(.k)\(when(.st; " r-" + .st))\"><time>\(ago(.t) | e)</time><span>\(when(.sha; "<code>\(.sha[0:7] | e)</code> "))\(.s | e)"
        + when(.k == "commit" and any($crs[]; . < $v.x); "<em class=\"tag\">after changes requested</em>") + "</span></li>"
        + ([$mine[] | select(.pin != null and .pin == $v.sha) | "<li class=\"ev-ch\">" + fold + "</li>"] | join(""))] | join(""))
  + ([$mine[] | select(.pin == null)] | when(length > 0; "<li class=\"ev-ch loose\"><p class=\"loose-h\">Not tied to one commit</p>" + (map(fold) | join("")) + "</li>"))
  + "</ol></section>";

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
    + (if .format == "timeline" then
        "<section class=\"tl-top\"><h2 class=\"tl-h\">How it unfolded</h2>" + metrics($root) + axis($root) + "</section>"
        + ([.prs[] as $p | tlpr($root; $chs; $p)] | join(""))
       elif .format == "slides" then
        ([$chs[] | slides($root; .num)] | join(""))
       else
        ([$chs | to_entries[] | .value as $c | (if .key == 0 then null else $chs[.key - 1].pr end) as $prev
          | when(($root.prs | length) > 1 and $c.pr != $prev; prhead(($root | prs_by_n)[$c.pr | tostring]))
            + ($c | chapter($root; $c.num))] | join(""))
       end)
    + when(($qs | length) > 0; "<section class=\"questions slide\" id=\"questions\"><div class=\"q-head\"><div><h2>Questions for the author</h2><p>The PR, its commits, reviews and ticket don’t answer these. Paste them into your review.</p></div><button type=\"button\" id=\"copy-qs\">Copy all</button></div><ol>"
        + ($qs | map("<li class=\"question\" data-q=\"\(.question | e)\">" + when($root.format == "slides"; "<input type=\"checkbox\" id=\"q-\(.id | e)\" aria-label=\"Asked\">") + "<a href=\"#ch-\(.id | e)\">Ch \(.num | pad2)</a><p>\(.question | e)</p></li>") | join("")) + "</ol></section>")
    + "</main>"
    + "<footer class=\"foot\">Built by <a href=\"https://github.com/nayanraj210401/flow-stack/tree/main/plugins/flow-stack/skills/pr-chapters\">flow-stack pr-chapters</a> from GitHub\(when(.task != null; " and the flow task")) · \(ago(.generated) | e) UTC · every why links to where it is written</footer>"
    + when(.format == "slides"; "<nav id=\"slide-nav\" aria-label=\"Chapters\"><button id=\"prev\" type=\"button\">← Prev</button><span id=\"slide-pos\"></span><button id=\"next\" type=\"button\">Next →</button></nav>")
    + "</div>";
