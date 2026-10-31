#!/usr/bin/env bash
# factory.sh: the factory's live board, a GitHub Project whose cards follow issue and PR state.
#   factory.sh project              print the profile's factory project (owner/n); exit 3 when none
#   factory.sh dry-run [owner/n]    print the card moves the sync would make
#   factory.sh apply   [owner/n]    make them (gh project item-edit), then print them
#   factory.sh json    [owner/n]    the board's factory panel data, for collect.sh
# The project comes from the profile ("factory:" then "  project: <owner>/<n>"). One GraphQL read
# gets every card, its content, labels, label history, and the head's flow/ready check. The column
# a card belongs in is col() below; a card already there is left alone, so re-runs move nothing.
# Ready is the human's intake gate (Triage → Ready = approved to build): the sync never moves a card into it.
set -uo pipefail
profile="${FLOW_STACK_HOME:-$HOME/.flow-stack}/profile.md"
cmd="${1:-}"; proj="${2:-}"
[ -n "$proj" ] || proj="$(awk '/^factory:/{f=1; next} f && /^[^[:space:]]/{f=0} f && /^[[:space:]]+project:/{sub(/^[[:space:]]+project:[[:space:]]*/,""); sub(/[[:space:]]+(#.*)?$/,""); print; exit}' "$profile" 2>/dev/null)"
case "$cmd" in project|dry-run|apply|json) ;; *) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;; esac
[ -n "$proj" ] || { echo "factory.sh: no factory project (profile: factory: / project: <owner>/<n>)" >&2; exit 3; }
[[ "$proj" =~ ^[A-Za-z0-9._-]+/[0-9]+$ ]] || { echo "factory.sh: project must be <owner>/<n>, got: $proj" >&2; exit 2; }
[ "$cmd" = project ] && { echo "$proj"; exit 0; }

labels='labels(first: 30) { nodes { name } } timelineItems(itemTypes: [LABELED_EVENT], first: 50) { nodes { ... on LabeledEvent { createdAt label { name } } } }'
q='query($owner: String!, $number: Int!, $endCursor: String) { repositoryOwner(login: $owner) { ... on ProjectV2Owner { projectV2(number: $number) {
  id url title
  field(name: "Status") { ... on ProjectV2SingleSelectField { id options { id name } } }
  items(first: 100, after: $endCursor) { pageInfo { hasNextPage endCursor } nodes { id
    fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
    content { __typename
      ... on Issue { number title url state stateReason createdAt body repository { nameWithOwner } '"$labels"' }
      ... on PullRequest { number title url state isDraft createdAt mergedAt repository { nameWithOwner } '"$labels"'
        closingIssuesReferences(first: 5) { nodes { number createdAt labels(first: 30) { nodes { name } } } }
        commits(last: 1) { nodes { commit { statusCheckRollup { contexts(first: 50) { nodes { ... on CheckRun { name conclusion } } } } } } } } } } } } } } }'
raw="$(gh api graphql --paginate -f query="$q" -F owner="${proj%/*}" -F number="${proj#*/}" 2>&1)" || { echo "factory.sh: gh api graphql failed: ${raw:0:300}" >&2; exit 1; }

# one card per item: where it is (status) and where its state says it belongs (col)
board="$(jq -sc '
  def names: [.nodes[]?.name];
  def col: if .type == "pr" and .state == "MERGED" then "Merged"
    elif .type == "issue" and .state == "CLOSED" and .reason == "COMPLETED" then "Merged"
    elif .state != "OPEN" then .status
    elif any(.labels[]; . == "needs-human") then "Blocked"
    elif .type == "pr" and any(.labels[]; . == "rework") then "Rework"
    elif .type == "pr" and (.ready or (.draft | not)) then "Review"
    elif .type == "pr" then "Building"
    else .status // "Triage" end;
  map(.data.repositoryOwner.projectV2 // empty) as $p
  | if ($p | length) == 0 then error("project not found or no access (a PAT needs the project scope)") else . end
  | {id: $p[0].id, url: $p[0].url, title: $p[0].title, field: $p[0].field.id, options: ($p[0].field.options // []),
     cards: [$p[].items.nodes[] | .content as $c | select($c.__typename == "Issue" or $c.__typename == "PullRequest")
       | {id, status: .fieldValueByName.name, type: (if $c.__typename == "Issue" then "issue" else "pr" end),
          ref: "\($c.repository.nameWithOwner)#\($c.number)", repo: $c.repository.nameWithOwner, number: $c.number, title: $c.title, url: $c.url,
          state: $c.state, reason: $c.stateReason, draft: ($c.isDraft // false), created: $c.createdAt, merged: $c.mergedAt,
          labels: ($c.labels | names), relabels: [$c.timelineItems.nodes[]? | .label.name],
          ready: any($c.commits.nodes[]?.commit.statusCheckRollup.contexts.nodes[]?; .name == "flow/ready" and .conclusion == "SUCCESS"),
          issues: [$c.closingIssuesReferences.nodes[]? | {number, created: .createdAt, labels: (.labels | names)}],
          refs: ([($c.body // "") | scan("#([0-9]+)") | .[0] | tonumber] | unique)}
       | . + {col: col}]}' <<<"$raw" 2>&1)" || { echo "factory.sh: $board" >&2; exit 1; }

moves() { jq -c '.options as $o | .cards[] | select(.col != null and .col != .status and .col != "Ready")
  | .col as $to | {id, ref, from: (.status // "no status"), to: $to, option: ([$o[] | select(.name == $to)][0].id // null)}' <<<"$board"; }

case "$cmd" in
  dry-run|apply)
    m="$(moves)"; [ -n "$m" ] || { echo "no moves"; exit 0; }
    pid="$(jq -r .id <<<"$board")"; fid="$(jq -r .field <<<"$board")"; rc=0
    while IFS= read -r mv; do
      line="$(jq -r '"\(.ref): \(.from) → \(.to)"' <<<"$mv")"; opt="$(jq -r '.option // empty' <<<"$mv")"
      if [ -z "$opt" ]; then echo "skip $line (the project has no column $(jq -r .to <<<"$mv"))"; continue; fi
      if [ "$cmd" = dry-run ]; then echo "would move $line"
      elif gh project item-edit --id "$(jq -r .id <<<"$mv")" --project-id "$pid" --field-id "$fid" --single-select-option-id "$opt" >/dev/null; then echo "moved $line"
      else echo "failed $line" >&2; rc=1; fi
    done <<<"$m"
    exit $rc ;;
  json)
    jq -c '
      def hours: fromdateiso8601; def h($a; $b): (($b | hours) - ($a | hours)) / 360 | round / 10;
      def median: sort | if length == 0 then null else .[length / 2 | floor] end;
      def rank: {"risk:low": 0, "risk:med": 1, "risk:high": 2}[.];
      .cards as $c | ($c | map(select(.type == "pr"))) as $prs | ($prs | map(select(.merged != null))) as $m
      | ([.options[].name] + [$c[] | .col // .status // "No status"] | reduce .[] as $n ([]; if index([$n]) then . else . + [$n] end)) as $cols
      | ([$c[] | select(.type == "issue" and any(.labels[]; . == "bug" or . == "type:bug"))
          | . as $b | select(any($m[]; .repo == $b.repo and (.number | IN($b.refs[]))))]) as $esc
      | ([$prs[] | ([.labels[] | rank | values] | max) as $a | ([.issues[].labels[] | rank | values] | max) as $p
          | select($a != null and $p != null) | $a > $p]) as $risk
      | {url, title,
         columns: [$cols[] as $n | {name: $n, cards: [$c[] | select((.col // .status // "No status") == $n) | {ref, title, url, type, open: (.state == "OPEN")}]}],
         cycle: {merged: ($m | length),
           intake_h: ([$m[] | .created as $pc | .issues[] | h(.created; $pc)] | median),
           build_h: ([$m[] | h(.created; .merged)] | median)},
         rework: {prs: ($prs | length), reworked: ($prs | map(select(any(.relabels[]; . == "rework"))) | length)},
         escaped: {bugs: ($esc | length), refs: [$esc[] | {ref, url}]},
         risk: {scored: ($risk | length), misses: ($risk | map(select(.)) | length)}}' <<<"$board" ;;
esac
