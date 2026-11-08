#!/usr/bin/env bash
# routines.sh: flow-stack routines on GitHub Actions. Run from the target repo's root.
#   routines.sh list                                  the catalog: each template routine and when to use it
#   routines.sh add <name> [--cron "<m h d M w>"] [--tz <zone>] [--preset <p>] [--force] [--local]
#                                                     write .github/routines/<name>.md (from the catalog when the
#                                                     name is in it, else a stub) and render it
#   routines.sh schedule <name> "<m h d M w>" [--tz <zone>]
#                                                     change a scheduled routine's cron (in its timezone) and re-render it
#   routines.sh render                                .github/routines/*.md → .github/workflows/flow-<name>.yml
#   routines.sh check [-v]                       every routine's workflow matches a fresh render; no orphans
#   routines.sh safety [-z] [--ref <ref>] [path ...]  the paths (args, else stdin lines, or NUL-separated with -z) on
#                                                     .github/routines/safety-paths.txt (at <ref> with --ref; the
#                                                     repo's own list without one, the plugin default only if it has none): exit 1 on any, 2 on an error
# Frontmatter: trigger (schedule | pull_request | mention: an @claude comment from a user with write access), cron and timezone (schedule only; an IANA zone, default UTC), timeout (minutes), labels (must exist;
# create_labels: true makes missing ones; .github/routines/labels.tsv renames catalog labels to yours on add), auth
# (oauth | api-key), grants (token scopes it may write: issues pull-requests contents; the rest are read),
# flow_ref (pin the plugin to a tag or branch; empty = the default branch, fresh each run). The body is the prompt.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
v=0; for a in "$@"; do { [ "$a" = -v ] || [ "$a" = --verbose ]; } && v=1; done
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

# ready.sh's stamp lives in .flow/ready.tsv on a runner that is thrown away. The self-heal routine carries it to the
# open self-heal PR whose head it stamped, as a flow/ready check run, then marks that draft ready. Events made with
# github.token start no workflows, so the undraft uses the Claude App token the agent step pushed with (when the action
# exposes it): ready_for_review then starts the review routine, whose verdict self-heal reads for its next rework round.
# The check says "this run's ready.sh passed on this SHA", not "an independent reviewer passed it": the guard keeps the
# agent's tools off the ledger, but code the agent runs in the same job could still write it. So nothing merges on it.
stamp_step() { # stamp_step <the label self-heal puts on its PRs>
  sed "s|@PR_LABEL@|$1|" <<'EOF'
      # ready.sh's stamp is on this runner's disk, which is thrown away: carry it to the self-heal PR it stamped
      - name: flow/ready
        if: always()
        env:
          GH_TOKEN: ${{ github.token }}
          APP_TOKEN: ${{ steps.claude.outputs.github_token }}
        run: |
          t=.flow/ready.tsv; [ -f "$t" ] || exit 0
          gh pr list --state open --label @PR_LABEL@ --json number,headRefOid,headRefName,isCrossRepository,isDraft,author \
            --jq '.[] | select((.isCrossRepository | not) and .author.is_bot and (.headRefName | startswith("self-heal/"))) | "\(.number) \(.headRefOid) \(.isDraft)"' |
          while read -r n sha draft; do
            awk -F'\t' -v s="$sha" '$2 == s && $3 == "ready" && $4 == "pass" { f = 1 } END { exit !f }' "$t" || continue
            awk -F'\t' -v s="$sha" '$2 == s { print $1, $3, $4 }' "$t" |
              jq -Rs --arg sha "$sha" '{name: "flow/ready", head_sha: $sha, status: "completed", conclusion: "success",
                output: {title: "ready.sh stamped this commit", summary: ("```\n" + . + "```")}}' |
              gh api "repos/$GITHUB_REPOSITORY/check-runs" --input - >/dev/null || { echo "::warning::flow/ready not posted on #$n"; continue; }
            [ "$draft" != true ] || GH_TOKEN="${APP_TOKEN:-$GH_TOKEN}" gh pr ready "$n" </dev/null || echo "::warning::#$n stays a draft"
            echo "flow/ready on #$n at ${sha:0:7}" >>"$GITHUB_STEP_SUMMARY"
          done
EOF
}
render_one() { # render_one <name>: the workflow on stdout
  local f="$dir/$1.md" auth trigger cron tz timeout labels grants ref g s on="" iff="" group="" cancel=false ctx="" guard="" mode="--auto"
  local stamp=""
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
    mention)
      on=$'  issue_comment:\n    types: [created]\n  pull_request_review_comment:\n    types: [created]'
      # author_association drops most strangers for free, and bots and apps never trigger a run (a factory can't
      # call itself in a loop); the step below asks GitHub for the commenter's real permission
      iff="    if: contains(github.event.comment.body, '@claude') && contains(fromJSON('[\"OWNER\",\"MEMBER\",\"COLLABORATOR\"]'), github.event.comment.author_association) && github.event.comment.user.type != 'Bot'"
      # every comment starts a run, even ones the job skips; a group per comment keeps a later comment from cancelling a queued request
      group='-${{ github.event.issue.number || github.event.pull_request.number }}-${{ github.event.comment.id }}'
      ctx=' The request is comment ${{ github.event.comment.id }} (${{ github.event_name }}) on #${{ github.event.issue.number || github.event.pull_request.number }}.'
      # a GitHub login is letters, digits and dashes (apps add [bot]), so it can't break out of the quotes
      guard='          COMMENTER='"'"'${{ github.event.comment.user.login }}'"'"
      guard+=$'\n''          case "$COMMENTER" in *"[bot]") echo "refused: $COMMENTER is an app, not a person" | tee -a "$GITHUB_STEP_SUMMARY"; exit 1 ;; esac'
      guard+=$'\n''          perm="$(gh api "repos/$GITHUB_REPOSITORY/collaborators/$COMMENTER/permission" --jq .permission)" || perm=none'
      guard+=$'\n''          case "$perm" in admin|maintain|write) ;; *) echo "refused: $COMMENTER has $perm access, not write" | tee -a "$GITHUB_STEP_SUMMARY"; exit 1 ;; esac'
      # the run holds write tokens, so a fork PR's code must never be checked out: refuse it here, not in the prompt
      guard+=$'\n''          PR='"'"'${{ github.event.pull_request.number || (github.event.issue.pull_request && github.event.issue.number) || '"''"' }}'"'"
      guard+=$'\n''          [ -z "$PR" ] || [ "$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR" --jq .head.repo.full_name)" = "$GITHUB_REPOSITORY" ] || { echo "refused: #$PR is from a fork or unreadable; a maintainer takes it over" | tee -a "$GITHUB_STEP_SUMMARY"; exit 1; }'
      # the thread's text is untrusted, so the hooks (not the prompt) hold this run to draft PRs: no merge, no ready
      guard+=$'\n''          echo "FLOW_SHIP_DRAFT=1" >>"$GITHUB_ENV"' ;;
    *) die "$f: trigger must be schedule, pull_request, or mention" ;;
  esac
  # one repo variable pauses every routine: FLOW_FACTORY=off
  if [ -n "$iff" ]; then iff+=" && vars.FLOW_FACTORY != 'off'"; else iff="    if: vars.FLOW_FACTORY != 'off'"; fi
  group="flow-$1$group"
  # routines that push (contents) take turns, so self-heal's rework and auto-merge never act on a PR at once.
  # GitHub keeps one pending run per group: a third queued run (a manual dispatch, say) cancels the pending one.
  [ "$trigger" = schedule ] && [[ " $grants " == *" contents "* ]] && group=flow-writers
  [[ "$timeout" =~ ^[0-9]+$ ]] || die "$f: timeout must be whole minutes, got '$timeout'"
  [[ "$labels" =~ ^([A-Za-z0-9:._-]+( [A-Za-z0-9:._-]+)*)?$ ]] || die "$f: labels are space-separated, no quotes, got '$labels'"
  case "$(field "$f" create_labels false)" in true|false) ;; *) die "$f: create_labels must be true or false" ;; esac
  for g in $grants; do case "$g" in issues|pull-requests|contents) ;; *) die "$f: grants takes issues pull-requests contents, got '$g'" ;; esac; done
  [[ "$ref" =~ ^[A-Za-z0-9._/-]*$ ]] || die "$f: flow_ref must be a tag or branch, got '$ref'"
  [[ ! "$ref" =~ ^[0-9a-f]{7,40}$ ]] || die "$f: flow_ref looks like a commit SHA; the clone takes a tag or branch (one that isn't 7-40 hex characters)"
  for s in contents issues pull-requests; do
    if [[ " $grants " == *" $s "* ]]; then export "R_PERM_${s//-/_}=write"; else export "R_PERM_${s//-/_}=read"; fi
  done
  # Only self-heal posts ready.sh's stamp as a flow/ready check run, which needs checks: write; the rest read it
  export R_PERM_checks=read
  if [ "$1" = self-heal ] && [[ " $grants " == *" contents "* ]]; then R_PERM_checks=write stamp="$(l="${labels%% *}"; stamp_step "${l:-self-heal}")"; fi
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
  # a placeholder alone on its line that renders empty (a step this routine has no use for) leaves no blank line
  R_NAME="$1" R_ON="$on" R_IF="$iff" R_GROUP="$group" R_CANCEL="$cancel" R_TIMEOUT="$timeout" R_LABELS="$labels" R_CREATE="$(field "$f" create_labels false)" \
  R_AUTH="$auth" R_TOKEN="$token" R_MARKET="$mkt" R_SETUP="${guard:+$guard${clone:+$'\n'}}$clone" R_MODE="$mode" R_CTX="$ctx" \
  R_STAMP="$stamp" \
    perl -pe '$w = /^\@[A-Za-z_]+\@$/; s/\@([A-Za-z_]+)\@/exists $ENV{"R_$1"} ? $ENV{"R_$1"} : die "unknown placeholder $1\n"/ge; $_ = "" if $w && $_ eq "\n"' "$tpl/workflow.yml"
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

relabel() { # stdin → stdout: a catalog template with its labels renamed to the repo's own, from $dir/labels.tsv
  # (lines "<catalog label> <yours>"). Only label spots change: the labels: line, `name`, and --label/--add-label name.
  local m="$dir/labels.tsv"
  [ -f "$m" ] || { cat; return; }
  awk 'NF && $1 !~ /^#/ && (NF != 2 || $0 ~ /[^A-Za-z0-9:._ \t-]/) { bad = 1 } END { exit bad }' "$m" \
    || die "$m: each line is '<catalog label> <yours>', no spaces inside a name"
  perl -e 'open M, $ARGV[0] or die; while (<M>) { next if /^\s*(#|$)/; my ($a, $b) = split; $m{$a} = $b }
    $r = join "|", map quotemeta, sort { length $b <=> length $a } keys %m;
    while (<STDIN>) { $fm++ if /^---$/;
      if ($r ne "" && $fm == 1 && /^labels:/) { s/(?<=[ :])($r)(?=\s|$)/$m{$1}/g }
      elsif ($r ne "") { s/`($r)`/`$m{$1}`/g; s/(--(?:add-|remove-)?label[ =])($r)(?=[\s`"\x27]|$)/$1$m{$2}/g }
      print }' "$m"
}

add() {
  local name="${1:-}" preset=solo-hacker force="" cron="" tz="" lcl=""; shift || true
  [[ "$name" =~ $name_re ]] || die "add <name>: lowercase letters, digits, dashes"
  while [ $# -gt 0 ]; do
    case "$1" in --preset) preset="$2"; shift 2 ;; --cron) cron="$2"; shift 2 ;; --tz) tz="$2"; shift 2 ;; --force) force=1; shift ;; --local) lcl=1; shift ;; *) die "unknown flag $1" ;; esac
  done
  # --local: the shift, on this machine's scheduler (shift.sh); nothing under .github
  [ -z "$lcl" ] || [ -z "$cron$tz" ] || die "--local takes its schedule from the profile's shift.when, not --cron/--tz"
  [ -z "$lcl" ] || exec "$here/shift.sh" install "$name" ${force:+--force}
  [ -z "$tz" ] || [ -n "$cron" ] || die "--tz needs --cron"
  [ -z "$cron" ] || valid_cron "$cron" || die "--cron must be five fields (minute hour day month weekday), got '$cron'"
  [ -z "$tz" ] || valid_tz "$tz" || die "--tz must be $tz_hint, got '$tz'"
  local f="$dir/$name.md" miss
  case "$name" in self-heal|auto-merge)
    miss="$(. "$here/../../../hooks/lib.sh"; factory_ready .)" || die "$name ships unattended, and this repo can't prove its changes yet. Missing: $miss. Commit them, then add $name." ;;
  esac
  [ ! -f "$f" ] || [ -n "$force" ] || die "$f exists (--force replaces it)"
  if [ -n "$cron" ] && [ -f "$tpl/$name.md" ] && [ "$(field "$tpl/$name.md" trigger schedule)" != schedule ]; then
    die "$name runs on $(field "$tpl/$name.md" trigger schedule), which takes no --cron"
  fi
  profile "$preset"
  [ -f "$dir/safety-paths.txt" ] || { cp "$tpl/safety-paths.txt" "$dir/"; echo "wrote $dir/safety-paths.txt (the paths no routine merges or builds unattended; add your own)"; }
  if [ -f "$tpl/$name.md" ]; then local body; body="$(relabel <"$tpl/$name.md")" || exit 2; printf '%s\n' "$body" >"$f"
  else printf -- '---\nabout: TODO one line: what it does and when to use it\ntrigger: schedule\ncron: "0 3 * * *"\ntimeout: 60\ngrants: issues\n---\n# %s\n\nTODO: what this routine does, its caps, and what it must never do.\n' "$name" >"$f"
  fi
  [ -z "$cron" ] || set_schedule "$name" "$cron" "$tz"
  echo "wrote $f"
  [ -z "$(field "$f" labels "")" ] || echo "it needs the labels $(field "$f" labels ""): a missing one stops the run (map yours in $dir/labels.tsv)"
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
  local n w ns bad=0 ok=0; ns="$(names)" || exit 2
  [ -f "$dir/profile.md" ] || { echo "✗ $dir/profile.md missing"; bad=1; }
  for n in $ns; do
    if diff -q <(render_one "$n") ".github/workflows/flow-$n.yml" >/dev/null 2>&1; then
      [ "$v" = 1 ] && echo "✓ $n"
      ok=$((ok + 1))
    else echo "✗ $n: .github/workflows/flow-$n.yml differs from $dir/$n.md (routines.sh render)"; bad=1; fi
  done
  for w in .github/workflows/flow-*.yml; do
    [ -e "$w" ] && grep -q '^# Generated by flow-stack make-routines' "$w" || continue
    n="${w##*/flow-}"; n="${n%.yml}"
    [ -f "$dir/$n.md" ] || { echo "✗ $w: its routine $dir/$n.md is gone (delete the workflow)"; bad=1; }
  done
  [ "$bad" = 0 ] && echo "$ok routines in sync"
  return "$bad"
}

safety() { # prints "<path><TAB><glob>" for each path on the list
  local z="" ref="" list p g pats=() hit=0 n=0
  while [ $# -gt 0 ]; do
    case "$1" in -z) z=1; shift ;; --ref) [ -n "${2:-}" ] || die "--ref needs a ref"; ref="$2"; shift 2 ;; --) shift; break ;; *) break ;; esac
  done
  # With --ref the list comes from that commit, so a PR checked out in the working tree can't shorten its own list
  if [ -n "$ref" ]; then
    git rev-parse -q --verify "$ref^{commit}" >/dev/null || die "--ref $ref is not a commit"
    # a base without the list fails closed: the generic default lacks this repo's own machinery
    list="$(git show "$ref:$dir/safety-paths.txt" 2>/dev/null)" || die "$ref has no $dir/safety-paths.txt"
  else
    # the repo's own list, wherever in the checkout this runs; the plugin default only outside a repo with one
    local own; own="$(git rev-parse --show-toplevel 2>/dev/null || echo .)/$dir/safety-paths.txt"
    if [ -f "$own" ]; then list="$(cat "$own")"; else list="$(cat "$tpl/safety-paths.txt")"; fi
  fi
  while read -r g _; do case "$g" in ''|'#'*) ;; *) pats+=("$g") ;; esac; done < <(tr -d '\r' <<<"$list")
  [ ${#pats[@]} -gt 0 ] || die "the safety list has no globs"
  on_list() {
    # git quotes a path with unusual bytes unless -z; a quoted path can't be matched, so it counts as a hit
    [[ "$1" != \"* ]] || { printf '%s\tquoted path: list it with git -z and pass -z\n' "$1"; return 0; }
    for g in "${pats[@]}"; do [[ "/${1#./}" == $g ]] && { printf '%s\t%s\n' "$1" "$g"; return 0; }; done
    return 1
  }
  if [ $# -gt 0 ]; then for p; do n=$((n + 1)); on_list "$p" && hit=1; done
  # `|| [ -n "$p" ]` keeps a last path that has no trailing separator; an empty -z entry means a broken feed
  elif [ -n "$z" ]; then while IFS= read -r -d '' p || [ -n "$p" ]; do [ -n "$p" ] || die "an empty path in -z input"; n=$((n + 1)); on_list "$p" && hit=1; done
  else while IFS= read -r p || [ -n "$p" ]; do [ -z "$p" ] && continue; n=$((n + 1)); on_list "$p" && hit=1; done; fi
  # a change always has a path, so none means the command feeding this failed: that must not read as clean
  [ "$n" -gt 0 ] || die "no paths to check"
  return "$hit"
}

case "${1:-}" in
  list) list ;;
  safety) shift; safety "$@" ;;
  add) shift; add "$@" ;;
  schedule) shift; schedule "$@" ;;
  render) render ;;
  check) check ;;
  *) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
