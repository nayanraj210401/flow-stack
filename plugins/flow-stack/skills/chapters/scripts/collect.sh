#!/usr/bin/env bash
# collect.sh: the raw material for a PR story, as one JSON document on stdout.
#   collect.sh <ref> [<ref> ...] [--task <slug>] [--format scroll|slides|rounds]
#
# A ref is a PR or issue: 12, #12, owner/repo#12, or its github.com URL. One PR is a story of
# its own; one issue is the story of the PRs that close it; several refs are one story, PRs in
# the order they were opened. Reads gh only, plus the flow task whose TICKET names one of the
# refs (or --task). Writes "story": null; the skill fills it, and render.sh checks it.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../../../hooks/roots.sh"
die() { echo "collect.sh: $*" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || die "needs jq"
command -v gh >/dev/null 2>&1 || die "needs gh"

refs=(); task=""; format=""
while [ $# -gt 0 ]; do
  case "$1" in
    --task) task="${2:-}"; shift ;;
    --format) format="${2:-}"; shift ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) refs+=("$1") ;;
  esac; shift
done
[ "${#refs[@]}" -gt 0 ] || die "usage: collect.sh <pr|issue> [<pr> ...] [--task <slug>] [--format scroll|slides|rounds]"
[ -n "$format" ] || format="$("$here/../../settings/scripts/settings.sh" chapters format 2>/dev/null)"
case "${format:-scroll}" in scroll|slides|rounds) format="${format:-scroll}" ;; *) die "format '$format': want scroll, slides or rounds" ;; esac

here_repo=""
for r in "${refs[@]}"; do
  [[ "$r" =~ ^#?[0-9]+$ ]] || continue
  here_repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" && [ -n "$here_repo" ] || die "not in a GitHub repo; pass owner/repo#N or a URL"
  break
done

# parse <ref> → "repo<TAB>number<TAB>hint" (hint: pr, issue, or empty)
parse() {
  local r="$1"
  if [[ "$r" =~ ^https?://github\.com/([^/]+/[^/]+)/(pull|issues)/([0-9]+) ]]; then
    printf '%s\t%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}" "$([ "${BASH_REMATCH[2]}" = pull ] && echo pr || echo issue)"
  elif [[ "$r" =~ ^([^/#[:space:]]+/[^/#[:space:]]+)#([0-9]+)$ ]]; then
    printf '%s\t%s\t\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  elif [[ "$r" =~ ^#?([0-9]+)$ ]]; then
    printf '%s\t%s\t\n' "$here_repo" "${BASH_REMATCH[1]}"
  else die "'$r' is not a PR or issue (12, #12, owner/repo#12, or a github.com URL)"; fi
}

PR_FIELDS=number,title,url,author,state,createdAt,mergedAt,baseRefName,headRefName,additions,deletions,body,closingIssuesReferences,commits,reviews,comments,statusCheckRollup
ISSUE_FIELDS=number,title,url,author,state,createdAt,body,comments,closedByPullRequestsReferences

# pr_json <repo> <n>: one PR, normalized, with every file's patch split into hunks
pr_json() {
  local view files comments
  view="$(gh pr view "$2" -R "$1" --json "$PR_FIELDS" 2>"$tmp/err")" || return 1
  files="$(gh api "repos/$1/pulls/$2/files" --paginate | jq -s 'add // []')" || die "could not read the files of $1#$2"
  comments="$(gh api "repos/$1/pulls/$2/comments" --paginate | jq -s 'add // []')" || die "could not read the review comments of $1#$2"
  jq -n --arg repo "$1" --argjson v "$view" --argjson f "$files" --argjson c "$comments" '
    def who: .login // .name // "unknown";
    def hunks: if . == null then [] else reduce (split("\n")[]) as $l ([];
      if ($l | startswith("@@")) or length == 0 then . + [$l] else .[-1] += "\n" + $l end) end;
    $v | {repo: $repo, number, title, url, author: (.author | who), state, createdAt, mergedAt,
      base: .baseRefName, head: .headRefName, additions, deletions, body: (.body // ""),
      closes: [.closingIssuesReferences[]? | {repo: (.repository | if . then "\(.owner.login)/\(.name)" else $repo end), number}],
      commits: [.commits[]? | {sha: .oid, headline: .messageHeadline, body: (.messageBody // ""), date: .committedDate,
        author: ((.authors // [])[0] | if . then who else "unknown" end)}],
      reviews: [.reviews[]? | {id, author: (.author | who), state, body: (.body // ""), submittedAt}],
      comments: [.comments[]? | {id, author: (.author | who), body: (.body // ""), createdAt}],
      checks: [.statusCheckRollup[]? | {name: (.name // .context), conclusion: (.conclusion // .state)}],
      review_comments: [$c[] | {id, author: (.user | who), path, line: (.line // .original_line), body: (.body // "")}],
      files: [$f[] | {path: .filename, status, additions, deletions, patch_omitted: (.patch == null), hunks: (.patch | hunks)}]}'
}
issue_json() {
  local v; v="$(gh issue view "$2" -R "$1" --json "$ISSUE_FIELDS" 2>"$tmp/err")" || return 1
  jq --arg repo "$1" 'def who: .login // .name // "unknown";
    {repo: $repo, number, title, url, author: (.author | who), state, createdAt, body: (.body // ""),
     comments: [.comments[]? | {id, author: (.author | who), body: (.body // ""), createdAt}],
     prs: [.closedByPullRequestsReferences[]? | {repo: (.repository | if . then "\(.owner.login)/\(.name)" else $repo end), number}]}' <<<"$v"
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
: >"$tmp/prs"; : >"$tmp/issues"; kind=""
add_pr() { grep -qx "$1#$2" "$tmp/seen" 2>/dev/null && return 0; echo "$1#$2" >>"$tmp/seen"; pr_json "$1" "$2" >>"$tmp/prs"; }
for r in "${refs[@]}"; do
  IFS=$'\t' read -r repo n hint < <(parse "$r") || exit 1
  if [ "$hint" != issue ] && add_pr "$repo" "$n"; then kind="${kind:+prs}"; kind="${kind:-pr}"; continue; fi
  [ "$hint" = pr ] && die "$r: $(head -1 "$tmp/err")"
  ij="$(issue_json "$repo" "$n")" || die "$r is not a PR or an issue in $repo: $(head -1 "$tmp/err")"
  echo "$ij" >>"$tmp/issues"
  ps="$(jq -r '.prs[] | "\(.repo)\t\(.number)"' <<<"$ij")"
  [ -n "$ps" ] || die "issue $repo#$n has no pull requests that close it; pass the PRs instead"
  while IFS=$'\t' read -r prepo p; do add_pr "$prepo" "$p" || die "$prepo#$p (from issue #$n): $(head -1 "$tmp/err")"; done <<<"$ps"
  kind="${kind:+prs}"; kind="${kind:-issue}"
done
[ "${#refs[@]}" -gt 1 ] && kind=prs

# the issues the PRs close, once each
jq -r '.closes[] | "\(.repo)\t\(.number)"' "$tmp/prs" | sort -u | while IFS=$'\t' read -r repo n; do
  jq -e --arg r "$repo" --argjson n "$n" 'select(.repo == $r and .number == $n)' "$tmp/issues" >/dev/null 2>&1 \
    || issue_json "$repo" "$n" >>"$tmp/issues" 2>/dev/null || true
done

# the flow task: --task, else the one whose TICKET names a ref of this story
flow_roots
names="$(jq -rs '.[] | .repo as $r | .number as $n | "#\($n)", "\($n)", "\($r)#\($n)", .url' "$tmp/prs" "$tmp/issues")"
tdir=""
if [ -n "$task" ]; then
  tdir="$FLOW_DIR/tasks/$task"; [ -d "$tdir" ] || die "no task '$task' in $FLOW_DIR/tasks"
else
  for t in "$FLOW_DIR"/tasks/*/TICKET; do
    [ -f "$t" ] || continue
    tk="$(head -1 "$t" | tr -d '[:space:]')"
    [ -n "$tk" ] && grep -qxF -- "$tk" <<<"$names" && { tdir="$(dirname "$t")"; break; }
  done
fi
md_first() { awk -v h="## $2" '/<!--/{c=1} c{if(/-->/)c=0; next} $0==h{on=1;next} on&&/^## /{exit} on&&NF&&$0!="- "{print;exit}' "$1" 2>/dev/null; }
task_json=null
if [ -n "$tdir" ]; then
  task_json="$(jq -n --arg slug "$(basename "$tdir")" --arg goal "$(md_first "$tdir/INTENT.md" Goal)" \
    --rawfile intent <(head -c 20000 "$tdir/INTENT.md" 2>/dev/null) \
    --rawfile dec <(cat "$tdir/DECISIONS.tsv" 2>/dev/null) \
    --rawfile sl <(grep '^## S' "$tdir/SLICES.md" 2>/dev/null | sed 's/^## //') '
    {slug: $slug, goal: $goal, intent: $intent, slices: ($sl | split("\n") | map(select(length > 0))),
     decisions: ($dec | split("\n") | .[1:] | map(select(length > 0) | split("\t")
       | {ts: .[0], who: .[1], decision: .[2], why: .[3], evidence: .[4]}))}')"
fi

jq -n --arg kind "$kind" --arg format "$format" --argjson task "$task_json" \
  --slurpfile prs "$tmp/prs" --slurpfile issues "$tmp/issues" '
  {version: 1, generated: (now | todate), format: $format,
   ref: {kind: $kind}, prs: ($prs | sort_by(.createdAt)), issues: ($issues | map(del(.prs))),
   task: $task, story: null}'
