#!/usr/bin/env bash
# leads.sh: the flow sessions (leads) on this machine, and messages between them.
#   leads.sh [list] [--json] [--no-prs]   every lead: id, repo, branch, worktree, task, slice,
#                                         ticket, PR (via gh; --no-prs skips it), last seen
#   leads.sh msg <to> "<text>" [--from <id>]   to = a lead id (or its prefix), branch, task
#                                         slug, or "all". The sender is the lead in this checkout
#                                         (--from <your id> when several share it). The recipient
#                                         reads it on its next tool call or prompt.
# Leads register themselves (hooks/lead.sh) in $FLOW_STACK_HOME/leads/<session>.json.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../../../hooks/roots.sh"; flow_roots
dir="${FLOW_STACK_HOME:-$HOME/.flow-stack}/leads"
die() { echo "leads.sh: $*" >&2; exit 1; }
all() { cat "$dir"/*.json 2>/dev/null | jq -s 'sort_by(.ts) | reverse'; }
self="$(all | jq -r --arg r "$FLOW_ROOT" '.[] | select(.root == $r) | .sid')"
label() { jq -r '[(.repo | split("/") | last), .branch, (if .task != "" then "task " + .task else empty end)] | join(" · ")'; }

cmd="${1:-list}"; [ $# -eq 0 ] || shift
case "$cmd" in
  list)
    json=""; prs=1
    for a in "$@"; do case "$a" in --json) json=1 ;; --no-prs) prs="" ;; *) die "unknown flag: $a" ;; esac; done
    command -v gh >/dev/null 2>&1 || prs=""
    rows="$(all | jq -c '.[]')"
    out="[]"
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      pr=""
      if [ -n "$prs" ]; then
        pr="$(cd "$(jq -r .root <<<"$e")" 2>/dev/null && gh pr view "$(jq -r .branch <<<"$e")" --json number,state -q '"#\(.number) \(.state | ascii_downcase)"' 2>/dev/null || true)"
      fi
      out="$(jq -c --argjson e "$e" --arg pr "$pr" --arg me "$self" '. + [$e + {pr:$pr, me:($me | split("\n") | index($e.sid) != null)}]' <<<"$out")"
    done <<<"$rows"
    if [ -n "$json" ]; then jq . <<<"$out"; exit 0; fi
    [ "$(jq length <<<"$out")" -gt 0 ] || { echo "no leads registered"; exit 0; }
    { printf 'ID\tREPO\tBRANCH\tWORKTREE\tTASK\tSLICE\tTICKET\tPR\tSEEN\n'
      jq -r --arg home "$HOME" --argjson now "$(date +%s)" '.[] |
        (($now - .ts) as $s | if $s < 3600 then "\($s / 60 | floor)m" elif $s < 86400 then "\($s / 3600 | floor)h" else "\($s / 86400 | floor)d" end) as $age |
        [(if .me then "*" else "" end) + .id, (.repo | split("/") | last), .branch, (.root | sub("^" + $home; "~")),
         .task, .slice, .ticket, .pr, $age] | map(if . == "" then "-" else . end) | @tsv' <<<"$out"
    } | column -t -s $'\t'
    ;;
  msg)
    to="${1:-}"; text="${2:-}"
    [ -n "$to" ] && [ -n "$text" ] || die 'usage: leads.sh msg <id|branch|task|all> "<text>" [--from <id>]'
    if [ "${3:-}" = --from ] && [ -n "${4:-}" ]; then
      self="$(all | jq -r --arg f "$4" '[.[] | select(.sid | startswith($f))][0].sid // empty')"
      [ -n "$self" ] || die "no lead '$4' (leads.sh list)"
    elif [ "$(grep -c . <<<"$self" || true)" -gt 1 ]; then
      die "several leads share this checkout ($(cut -c1-8 <<<"$self" | tr '\n' ' ')); say which you are with --from <your id> (the [flow lead] line names it)"
    fi
    targets="$(all | jq -r --arg to "$to" --arg me "$self" '.[] | select(.sid != $me) |
      select($to == "all" or (.sid | startswith($to)) or .branch == $to or .task == $to) | .sid')"
    [ -n "$targets" ] || die "no other lead matches '$to' (leads.sh list)"
    n="$(wc -l <<<"$targets" | tr -d ' ')"
    [ "$to" = all ] || [ "$n" -eq 1 ] || die "'$to' matches $n leads; use an id: $(tr '\n' ' ' <<<"$targets")"
    from="${self:0:8}"; lab="outside a lead session"
    [ -z "$self" ] || lab="$(label <"$dir/$self.json")"
    while IFS= read -r t; do
      jq -nc --arg ts "$(date -u +%FT%TZ)" --arg from "${from:-human}" --arg label "$lab" --arg text "$text" \
        '{ts:$ts, from:$from, label:$label, text:$text}' >"$dir/.msg.$$"
      mkdir -p "$dir/$t.inbox"; mv "$dir/.msg.$$" "$dir/$t.inbox/$(date +%s).$$.$RANDOM.json"
    done <<<"$targets"
    if [ "$to" = all ]; then echo "sent to $n lead(s)"
    else echo "sent to ${targets:0:8} ($(label <"$dir/$targets.json"))"; fi
    ;;
  -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command: $cmd (try -h)" ;;
esac
