#!/usr/bin/env bash
# routines.sh: flow-stack routines on GitHub Actions. Run from the target repo's root.
#   routines.sh list                                  the catalog: each template routine and when to use it
#   routines.sh add <name> [--cron "<m h d M w>"] [--tz <zone>] [--preset <p>] [--force] [--local]
#                                                     write .github/routines/<name>.md (from the catalog when the
#                                                     name is in it, else a stub) and render it
#   routines.sh schedule <name> "<m h d M w>" [--tz <zone>]
#                                                     change a scheduled routine's cron (in its timezone) and re-render it
#   routines.sh render                                .github/routines/*.md → .github/workflows/flow-<name>.yml
#   routines.sh check                                 every routine's workflow matches a fresh render; no orphans
# Frontmatter: trigger (schedule | pull_request), cron and timezone (schedule only; an IANA zone, default UTC), timeout (minutes), labels, auth
# (oauth | api-key), grants (token scopes it may write: issues pull-requests contents; the rest are read),
# flow_ref (pin the plugin to a tag or branch; empty = the default branch, fresh each run). The body is the prompt.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tpl="$here/../templates"
dir=.github/routines
market=https://github.com/nayanraj210401/flow-stack.git
name_re='^[a-z0-9][a-z0-9-]*$'
die() { echo "routines.sh: $*" >&2; exit 2; }

field() { # field <file> <key> <default>
  local v
  v="$(tr -d '\r' <"$1" | awk -v k="$2" 'NR==1&&/^---$/{on=1;next} on&&/^---$/{exit} on&&index($0,k":")==1{sub("^"k":[[:space:]]*","");print;exit}')"
  v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
  printf '%s' "${v:-$3}"
}

valid_cron() { [[ "$1" =~ ^[0-9*/,-]+( [0-9*/,A-Za-z-]+){4}$ ]]; }
# A canonical IANA zone (Asia/Kolkata, America/New_York) or UTC / Etc/GMT±N. With the tz database's zone.tab, only
# zones it lists pass, so old aliases (Asia/Calcutta, US/Eastern) and non-zones (posixrules, Factory) are refused.
valid_tz() {
  [[ "$1" =~ ^(UTC|GMT|Etc/(UTC|GMT(-1[0-4]|\+1[0-2]|[+-][0-9])?))$ ]] && return
  [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+){1,2}$ ]] || return 1
  local tab=/usr/share/zoneinfo/zone.tab
  [ ! -f "$tab" ] || cut -f3 "$tab" | grep -qxF "$1"
}
tz_hint="a canonical IANA zone like Asia/Kolkata or America/New_York (not an alias like Asia/Calcutta or US/Eastern)"

set_key() { # set_key <name> <key> <value>: put key: "value" in the routine's frontmatter
  local f="$dir/$1.md"
  [ "$(field "$f" trigger schedule)" = schedule ] || die "$f: trigger is $(field "$f" trigger schedule), which takes no $2"
  local tmp; tmp="$(mktemp)"
  # Only the frontmatter (between the first two --- lines) is touched: replace the key, or add it before the
  # closing ---. The line ending of the --- line is kept, so CRLF files stay CRLF.
  K="$2" V="$3" perl -ne '
    if ($. == 1) { /^---(\r?)$/ or exit; $eol = $1; $fm = 1; print; next }
    if ($fm && /^---\r?$/) { print qq{$ENV{K}: "$ENV{V}"$eol\n} unless $done; $fm = 0; $done = 1; print; next }
    if ($fm && /^\Q$ENV{K}\E:/) { print qq{$ENV{K}: "$ENV{V}"$eol\n}; $done = 1; next }
    print; END { exit 4 unless $done }' "$f" >"$tmp" || { rm -f "$tmp"; die "$f: no frontmatter to put a $2 in"; }
  [ "$(field "$tmp" "$2" "")" = "$3" ] || { rm -f "$tmp"; die "$f: the $2 didn't land in the frontmatter"; }
  mv "$tmp" "$f"
}

set_schedule() { # set_schedule <name> <cron> <tz or "">
  valid_cron "$2" || die "cron must be five fields (minute hour day month weekday), got '$2'"
  [ -z "$3" ] || valid_tz "$3" || die "timezone must be $tz_hint, got '$3'"
  set_key "$1" cron "$2"
  [ -z "$3" ] || set_key "$1" timezone "$3"
}

render_one() { # render_one <name>: the workflow on stdout
  local f="$dir/$1.md" auth trigger cron tz timeout labels grants ref g s on="" iff="" group="" cancel=false ctx="" mode="--auto"
  case "$(field "$f" auth oauth)" in
    oauth) auth='claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}' ;;
    api-key) auth='anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}' ;;
    *) die "$f: auth must be oauth or api-key" ;;
  esac
  trigger="$(field "$f" trigger schedule)" timeout="$(field "$f" timeout 60)" labels="$(field "$f" labels "")"
  grants="$(field "$f" grants issues)" ref="$(field "$f" flow_ref "")"
  case "$trigger" in
    schedule)
      cron="$(field "$f" cron "0 3 * * *")"
      valid_cron "$cron" || die "$f: cron must be five fields, got '$cron'"
      tz="$(field "$f" timezone "")"
      [ -z "$tz" ] || valid_tz "$tz" || die "$f: timezone must be $tz_hint, got '$tz'"
      on=$'  schedule:\n    - cron: "'"$cron"'"'
      [ -z "$tz" ] || on+=$'\n      timezone: "'"$tz"'"'
      on+=$'\n  workflow_dispatch:' ;;
    pull_request)
      on='  pull_request:'$'\n''    types: [opened, synchronize, ready_for_review]'
      # drafts aren't ready, fork PRs get no secrets, and Dependabot runs get only Dependabot's secrets
      iff="    if: github.event.pull_request.draft == false && github.event.pull_request.head.repo.full_name == github.repository && github.actor != 'dependabot[bot]'"
      group='-${{ github.event.pull_request.number }}' cancel=true
      ctx=' The pull request is #${{ github.event.pull_request.number }}.' ;;
    *) die "$f: trigger must be schedule or pull_request" ;;
  esac
  [[ "$timeout" =~ ^[0-9]+$ ]] || die "$f: timeout must be whole minutes, got '$timeout'"
  [[ "$labels" =~ ^([a-z0-9:._-]+( [a-z0-9:._-]+)*)?$ ]] || die "$f: labels are space-separated, no quotes, got '$labels'"
  for g in $grants; do case "$g" in issues|pull-requests|contents) ;; *) die "$f: grants takes issues pull-requests contents, got '$g'" ;; esac; done
  [[ "$ref" =~ ^[A-Za-z0-9._/-]*$ ]] || die "$f: flow_ref must be a tag or branch, got '$ref'"
  [[ ! "$ref" =~ ^[0-9a-f]{7,40}$ ]] || die "$f: flow_ref looks like a commit SHA; the clone takes a tag or branch (one that isn't 7-40 hex characters)"
  for s in contents issues pull-requests; do
    if [[ " $grants " == *" $s "* ]]; then export "R_PERM_${s//-/_}=write"; else export "R_PERM_${s//-/_}=read"; fi
  done
  # Without github_token the action swaps in the Claude App's token, with every scope the App has. Only a
  # routine that pushes needs it (PRs opened with github.token don't trigger CI); the rest stay inside `grants`.
  local token='github_token: ${{ github.token }}' mkt="$market" clone=""
  if [[ " $grants " == *" contents "* ]]; then mode="/flow-stack:flow --auto ship" token=""; fi
  case "$(field "$f" gha false)" in
    true) [ "$trigger" = schedule ] || die "$f: gha: true is for schedule routines; a pull_request routine reads untrusted text"
      [[ " $grants " == *" contents "* ]] || die "$f: gha: true needs contents in grants (--gha adds releases to the ship set)"; mode="/flow-stack:flow --auto ship --gha" ;;
    false) ;;
    *) die "$f: gha must be true or false" ;;
  esac
  # The action accepts only marketplace URLs ending in .git, so a pin is a clone at the ref, added by path
  if [ -n "$ref" ]; then
    clone="          git clone -q --depth 1 --branch '$ref' $market \"\$RUNNER_TEMP/flow-stack-plugin\""
    mkt='${{ runner.temp }}/flow-stack-plugin'
  fi
  R_NAME="$1" R_ON="$on" R_IF="$iff" R_GROUP="$group" R_CANCEL="$cancel" R_TIMEOUT="$timeout" R_LABELS="$labels" \
  R_AUTH="$auth" R_TOKEN="$token" R_MARKET="$mkt" R_CLONE="$clone" R_MODE="$mode" R_CTX="$ctx" \
    perl -pe 's/\@([A-Za-z_]+)\@/exists $ENV{"R_$1"} ? $ENV{"R_$1"} : die "unknown placeholder $1\n"/ge' "$tpl/workflow.yml"
}

names() {
  local f
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue; f="${f##*/}"; f="${f%.md}"
    [ "$f" = profile ] && continue
    [[ "$f" =~ $name_re ]] || die "$dir/$f.md: name must be lowercase letters, digits, dashes"
    echo "$f"
  done
}

write_one() { # write_one <name>: render to a temp file first, so a bad routine never empties its workflow
  local out=".github/workflows/flow-$1.yml" tmp
  mkdir -p .github/workflows; tmp="$(mktemp)"
  render_one "$1" >"$tmp" || { rm -f "$tmp"; exit 2; }
  mv "$tmp" "$out"; echo "rendered $out"
}

render() { local n ns; ns="$(names)" || exit 2; for n in $ns; do write_one "$n"; done; }

list() {
  local f n
  for f in "$tpl"/*.md; do
    n="${f##*/}"; n="${n%.md}"
    printf '%-12s %-13s %s\n' "$n" "$(field "$f" trigger schedule)" "$(field "$f" about "")"
  done
}

profile() { # profile <preset>: a headless profile for CI runs, notifications off
  [ -f "$dir/profile.md" ] && return 0
  local h; h="$(mktemp -d)"
  FLOW_STACK_HOME="$h" "$here/../../profile/scripts/init.sh" "$1" >/dev/null || { rm -rf "$h"; die "preset '$1' failed"; }
  perl -pi -e 's/^notify:\s*\S+/notify: off/' "$h/profile.md"
  mkdir -p "$dir" && cp "$h/profile.md" "$dir/profile.md" && rm -rf "$h"
  echo "wrote $dir/profile.md (preset $1; edit it: it is how the routines work, and it is committed)"
}

add() {
  local name="${1:-}" preset=solo-hacker force="" cron="" tz="" lcl=""; shift || true
  [[ "$name" =~ $name_re ]] || die "add <name>: lowercase letters, digits, dashes"
  while [ $# -gt 0 ]; do
    case "$1" in --preset) preset="$2"; shift 2 ;; --cron) cron="$2"; shift 2 ;; --tz) tz="$2"; shift 2 ;; --force) force=1; shift ;; --local) lcl=1; shift ;; *) die "unknown flag $1" ;; esac
  done
  # --local: the shift, on this machine's scheduler (shift.sh); nothing under .github
  [ -z "$lcl" ] || exec "$here/shift.sh" install "$name" ${force:+--force}
  [ -z "$tz" ] || [ -n "$cron" ] || die "--tz needs --cron"
  [ -z "$cron" ] || valid_cron "$cron" || die "--cron must be five fields (minute hour day month weekday), got '$cron'"
  [ -z "$tz" ] || valid_tz "$tz" || die "--tz must be $tz_hint, got '$tz'"
  local f="$dir/$name.md"
  [ ! -f "$f" ] || [ -n "$force" ] || die "$f exists (--force replaces it)"
  if [ -n "$cron" ] && [ -f "$tpl/$name.md" ] && [ "$(field "$tpl/$name.md" trigger schedule)" != schedule ]; then
    die "$name runs on $(field "$tpl/$name.md" trigger schedule), which takes no --cron"
  fi
  profile "$preset"
  if [ -f "$tpl/$name.md" ]; then cp "$tpl/$name.md" "$f"
  else printf -- '---\nabout: TODO one line: what it does and when to use it\ntrigger: schedule\ncron: "0 3 * * *"\ntimeout: 60\ngrants: issues\n---\n# %s\n\nTODO: what this routine does, its caps, and what it must never do.\n' "$name" >"$f"
  fi
  [ -z "$cron" ] || set_schedule "$name" "$cron" "$tz"
  echo "wrote $f"
  write_one "$name"
}

schedule() { # schedule <name> <cron> [--tz <zone>]: change an existing routine's schedule and re-render it
  [ -f "$dir/${1:-}.md" ] || die "schedule <name> <cron>: no routine $dir/${1:-}.md"
  local name="$1" cron="${2:-}" tz=""; shift $(($# < 2 ? $# : 2))
  while [ $# -gt 0 ]; do
    case "$1" in --tz) [ -n "${2:-}" ] || die "--tz needs a zone"; tz="$2"; shift 2 ;; *) die "unknown argument $1" ;; esac
  done
  set -- "$name" "$cron"
  local f="$dir/$1.md" bak; bak="$(mktemp)"; cp "$f" "$bak"
  (set_schedule "$1" "${2:-}" "$tz") || { cp "$bak" "$f"; rm -f "$bak"; exit 2; }
  (write_one "$1") || { cp "$bak" "$f"; rm -f "$bak"; die "$f: render failed, schedule left as it was"; }
  rm -f "$bak"
}

check() {
  local n w ns bad=0; ns="$(names)" || exit 2
  [ -f "$dir/profile.md" ] || { echo "✗ $dir/profile.md missing"; bad=1; }
  for n in $ns; do
    if diff -q <(render_one "$n") ".github/workflows/flow-$n.yml" >/dev/null 2>&1; then echo "✓ $n"
    else echo "✗ $n: .github/workflows/flow-$n.yml differs from $dir/$n.md (routines.sh render)"; bad=1; fi
  done
  for w in .github/workflows/flow-*.yml; do
    [ -e "$w" ] && grep -q '^# Generated by flow-stack make-routines' "$w" || continue
    n="${w##*/flow-}"; n="${n%.yml}"
    [ -f "$dir/$n.md" ] || { echo "✗ $w: its routine $dir/$n.md is gone (delete the workflow)"; bad=1; }
  done
  return "$bad"
}

case "${1:-}" in
  list) list ;;
  add) shift; add "$@" ;;
  schedule) shift; schedule "$@" ;;
  render) render ;;
  check) check ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
