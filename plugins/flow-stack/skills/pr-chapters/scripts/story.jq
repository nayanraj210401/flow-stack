# story.jq: check a story and draw it. Input: collect.sh's JSON with .story filled.
#   jq -r 'errors[]'  every reason the story can't be published, one per line (none: it can)
#   jq -r 'page'      the page body, HTML, every value escaped

def prs_by_n: reduce .prs[] as $p ({}; .[$p.number | tostring] = $p);
def norm: ascii_downcase | gsub("\\s+"; " ");
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
             (if (($ch.why.sources // []) | length) > 0 or (($ch.question // "") | length) > 0 then empty
              else "chapter \($id): the why has no source and there is no question for the author; cite where the why is written, or ask" end),
             ($ch.why.sources[]? as $s
              | if (kinds | index($s.kind)) == null then "chapter \($id): source kind '\($s.kind)' is not one of \(kinds | join(", "))"
                else (resolve($s; $ch; $root)) as $r
                | if $r == null then "chapter \($id): \($s.kind) \($s.ref // "") was not collected for this story"
                  elif ($s.quote // "") != "" and (($r.text | norm) | contains($s.quote | norm) | not) then "chapter \($id): quote \"\($s.quote)\" is not in \($r.label)"
                  else empty end end),
             ($ch.refs[]? as $f | ($by[($f.pr // $ch.pr) | tostring]) as $p
              | ($p.files // [] | map(select(.path == $f.file)) | .[0]) as $file
              | if $file == null then "chapter \($id): \($f.file) is not a file of PR \($f.pr // $ch.pr)"
                else ($f.hunks[]? | select(. >= ($file.hunks | length) or . < 0) | "chapter \($id): \($f.file) has no hunk \(.) (it has \($file.hunks | length))") end) )),
        (.prs[] as $p | $p.files[] | .path as $path
         | select([$root.story.chapters[] | .pr as $cp | .refs[]? | select((.pr // $cp) == $p.number and .file == $path)] | length == 0)
         | "\($path) (PR #\($p.number)) is in no chapter; every changed file goes in one, tests and generated files in a skip chapter") ]
    end;

# ---- drawing
def e: tostring | @html;
def when($c; $s): if $c then $s else "" end;
def ago($t): $t | if . then (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | strftime("%b %-d, %H:%M")) else "" end;
def hunk:
  split("\n") as $ls
  | "<pre class=\"hunk\"><code>"
    + ($ls[0:400] | map(
        (if startswith("@@") then "hh" elif startswith("+") then "add" elif startswith("-") then "del" else "ctx" end) as $c
        | "<span class=\"ln \($c)\">\(e)</span>") | join(""))
    + when(($ls | length) > 400; "<span class=\"ln more\">… \(($ls | length) - 400) more lines on GitHub</span>")
    + "</code></pre>";
def fileref($p):
  .file as $path | (.hunks // null) as $want | ($p.files[] | select(.path == $path)) as $f
  | "<figure class=\"file\"><figcaption><span class=\"path\">\($path | e)</span><span class=\"delta\"><span class=\"plus\">+\($f.additions)</span> <span class=\"minus\">−\($f.deletions)</span> · \($f.status | e)</span></figcaption>"
    + (if $f.patch_omitted then "<p class=\"omitted\">patch not shown: GitHub leaves out large and binary diffs. <a href=\"\($p.url | e)/files\">Open on GitHub</a></p>"
       else ([$f.hunks | to_entries[] | select($want == null or (.key as $k | $want | index($k))) | .value | hunk] | join("")) end)
    + "</figure>";
def chapter($root; $num):
  . as $ch | (($root | prs_by_n)[.pr | tostring]) as $p
  | "<article class=\"chapter slide tier-\(.tier | e)\" id=\"ch-\(.id | e)\">"
    + "<header class=\"ch-head\"><span class=\"ch-num\">Chapter \($num)</span><span class=\"pill tier-\(.tier | e)\">\(.tier | e)</span>"
    + when(($root.prs | length) > 1; "<span class=\"ch-pr\">PR #\(.pr)</span>") + "</header>"
    + "<h2>\(.title | e)</h2><p class=\"what\">\(.what | e)</p>"
    + (if ((.why.sources // []) | length) > 0 then
        "<section class=\"why\"><h3>Why</h3><p>\(.why.text // "" | e)</p><ul class=\"sources\">"
        + ([.why.sources[] as $s | resolve($s; $ch; $root) as $r
            | "<li><span class=\"src-kind\">\($s.kind | e)</span> "
              + (if $r.url then "<a href=\"\($r.url | e)\">\($r.label | e)</a>" else "<span>\($r.label | e)</span>" end)
              + when(($s.quote // "") != ""; " <q>\($s.quote | e)</q>") + "</li>"] | join(""))
        + "</ul></section>"
       else "<section class=\"why missing\"><h3>Why</h3><p>\(when((.why.text // "") != ""; (.why.text | e) + " "))Nobody wrote the reason down in the PR, its commits, reviews or ticket.</p></section>" end)
    + when((.question // "") != ""; "<p class=\"ask\"><span>Ask the author</span>\(.question | e)</p>")
    + when(((.refs // []) | length) > 0; "<div class=\"refs\">" + ([.refs[] | . as $f | fileref(($root | prs_by_n)[($f.pr // $ch.pr) | tostring])] | join("")) + "</div>")
    + "</article>";
def events($p):
  ([{t: $p.createdAt, k: "open", s: "opened by \($p.author)"}]
   + [$p.commits[] | {t: .date, k: "commit", s: "\(.sha[0:7]) \(.headline)"}]
   + [$p.reviews[] | {t: .submittedAt, k: "review r-\(.state | ascii_downcase)", s: "\(.author): \(.state | ascii_downcase | gsub("_"; " "))"}]
   + [$p.comments[] | {t: .createdAt, k: "comment", s: "\(.author) commented"}]
   + (if $p.mergedAt then [{t: $p.mergedAt, k: "merged", s: "merged into \($p.base)"}] else [] end))
  | sort_by(.t)
  | "<ol class=\"rail\">" + (map("<li class=\"ev \(.k)\"><time>\(ago(.t) | e)</time><span>\(.s | e)</span></li>") | join("")) + "</ol>";
def prhead($p):
  "<section class=\"pr-head\"><h2><a href=\"\($p.url | e)\">PR #\($p.number)</a> \($p.title | e)</h2>"
  + "<p class=\"meta\">\($p.author | e) · \($p.head | e) → \($p.base | e) · <span class=\"plus\">+\($p.additions)</span> <span class=\"minus\">−\($p.deletions)</span> · \($p.files | length) files · \($p.commits | length) commits · \($p.state | ascii_downcase | e)</p></section>";

def page:
  . as $root | .story as $s | ($s.chapters | to_entries | map(.value + {num: (.key + 1)})) as $chs
  | ([.prs[].repo] | unique | join(", ")) as $repos
  | (if .ref.kind == "issue" then "\($repos) · issue #\(.issues[0].number) · \(.prs | length) PRs"
     elif (.prs | length) > 1 then "\($repos) · \(.prs | length) PRs"
     else "\($repos) · PR #\(.prs[0].number)" end) as $eyebrow
  | [$chs[] | select((.question // "") != "")] as $qs
  | "<main class=\"story\" data-format=\"\(.format | e)\">"
    + "<header class=\"cover slide on\" id=\"cover\"><p class=\"eyebrow\">\($eyebrow | e)</p><h1>\($s.title | e)</h1><p class=\"summary\">\($s.summary // "" | e)</p>"
    + "<p class=\"meta\"><span class=\"plus\">+\([.prs[].additions] | add)</span> <span class=\"minus\">−\([.prs[].deletions] | add)</span> · \([.prs[].files | length] | add) files · \([.prs[].commits | length] | add) commits · by \([.prs[].author] | unique | join(", ") | e)"
    + when(.task != null; " · flow task <code>\(.task.slug | e)</code>") + "</p>"
    + "<ol class=\"toc\">" + ($chs | map("<li><a href=\"#ch-\(.id | e)\"><span class=\"pill tier-\(.tier | e)\">\(.tier | e)</span>\(.title | e)</a></li>") | join("")) + "</ol>"
    + "<p class=\"legend\"><span class=\"pill tier-read\">read</span> line by line · <span class=\"pill tier-skim\">skim</span> check it matches the intent · <span class=\"pill tier-skip\">skip</span> mechanical, reason given</p>"
    + when(($qs | length) > 0; "<p class=\"qcount\"><a href=\"#questions\">\($qs | length) question\(when(($qs | length) > 1; "s")) for the author</a></p>")
    + "</header>"
    + (if .format == "timeline" then
        ([.prs[] as $p | "<section class=\"pr-group\">" + prhead($p) + events($p)
          + ([$chs[] | select(.pr == $p.number) | chapter($root; .num)] | join("")) + "</section>"] | join(""))
       else
        ([$chs | to_entries[] | .value as $c | (if .key == 0 then null else $chs[.key - 1].pr end) as $prev
          | when(($root.prs | length) > 1 and $c.pr != $prev; prhead(($root | prs_by_n)[$c.pr | tostring]))
            + ($c | chapter($root; $c.num))] | join(""))
       end)
    + when(($qs | length) > 0; "<section class=\"questions slide\" id=\"questions\"><h2>Questions for the author</h2><p class=\"hint\">The PR doesn't answer these. Paste them into the review.</p><ol>"
        + ($qs | map("<li class=\"question\"><a href=\"#ch-\(.id | e)\">Chapter \(.num)</a> \(.question | e)</li>") | join("")) + "</ol></section>")
    + "<footer class=\"foot\">Built by flow-stack pr-chapters from GitHub data\(when(.task != null; " and the flow task")), \(ago(.generated) | e) UTC. Every why links to where it is written.</footer>"
    + when(.format == "slides"; "<nav id=\"slide-nav\" aria-label=\"Chapters\"><button id=\"prev\" type=\"button\">← Prev</button><span id=\"slide-pos\"></span><button id=\"next\" type=\"button\">Next →</button></nav>")
    + "</main>";
