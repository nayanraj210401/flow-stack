#!/usr/bin/env bash
# features.sh: the repo's feature map (.flow/features/<id>.md), in bash.
#
#   features.sh list                          id · status · verified · entries · owns
#   features.sh impact [--base REF] [--ids] [path ...]
#                                             features touched by a change (default: uncommitted
#                                             changes vs HEAD, incl. untracked) + unowned files
#   features.sh run <id ...> | --impacted [--base REF] | --all
#                                             run each feature's scenario through evidence.sh
#                                             (label feat:<id>); PASS marks it verified
#   features.sh mark <id> <verified|unverified|stale|broken>
#   features.sh stale [--write]               features whose owned code changed since verified
#   features.sh coverage                      unowned code, features without scenarios, dead globs
#   features.sh check                         lint every feature file (fields, sections, globs)
#   features.sh subs <id>                     sub-feature IDs of a feature
#   features.sh index                         regenerate .flow/features/README.md
#   features.sh new <id> "<title>"            scaffold a feature file from the template
#
# Feature file frontmatter (see references/feature-template.md):
#   id, title, owns (space-separated globs), entries (" | "-separated),
#   scenario (command), status, verified ("<date> <sha>")
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "features.sh: needs a git repo" >&2; exit 2; }
cd "$root"
. "$here/../../../hooks/roots.sh"; flow_roots
dir="$FLOW_DIR/features"
evidence="$here/../../verify/scripts/evidence.sh"

die() { echo "features.sh: $*" >&2; exit 2; }
files() { ls "$dir"/*.md 2>/dev/null | grep -v '/README\.md$'; }
fm() { # fm <file> <key>
  awk -v k="$2" 'NR==1 && $0=="---" {on=1; next} on && $0=="---" {exit}
    on && index($0, k ":") == 1 {v = substr($0, length(k) + 2); sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v); print v; exit}' "$1"
}
file_of() { local f="$dir/$1.md"; [ -f "$f" ] || die "no feature '$1' ($f)"; printf '%s' "$f"; }
specs_of() { # pathspecs for a feature's owns globs
  local g; set -f
  for g in $(fm "$1" owns); do printf '%s\n' ":(glob)$g"; done
  set +f
}
set_fm() { # set_fm <file> <key> <value>
  local f="$1" k="$2" v="$3" tmp
  tmp="$(mktemp)"
  awk -v k="$k" -v v="$v" 'NR==1 && $0=="---" {on=1; print; next}
    on && $0=="---" { if (!done) print k ": " v; on=0; print; next }
    on && index($0, k ":") == 1 { print k ": " v; done=1; next } { print }' "$f" >"$tmp" && mv "$tmp" "$f"
}
changed_files() { # changed_files <base>
  { git diff --name-only "$1" -- 2>/dev/null; git ls-files --others --exclude-standard; } | grep -v '^\.flow/' | sort -u
}
matches() { # matches <path> <feature-file>: does path fall under any owns glob?
  local p="$1" g gg; set -f
  for g in $(fm "$2" owns); do
    gg="${g//\*\*/*}"
    # shellcheck disable=SC2053
    if [[ "$p" == $gg ]]; then set +f; return 0; fi
  done
  set +f; return 1
}

# Paths that are never features: docs, lockfiles, repo plumbing, .flow/, plus .flow/features/.ignore globs.
not_feature() {
  local p="$1" g
  case "$p" in
    .flow/*|*.md|.github/*|*.lock|*/package-lock.json|package-lock.json|LICENSE*|.gitignore|.gitattributes|.editorconfig) return 0 ;;
  esac
  if [ -f "$dir/.ignore" ]; then
    set -f
    while IFS= read -r g; do
      [ -n "$g" ] && [ "${g#\#}" = "$g" ] || continue
      # shellcheck disable=SC2053
      if [[ "$p" == ${g//\*\*/*} ]]; then set +f; return 0; fi
    done <"$dir/.ignore"
    set +f
  fi
  return 1
}

cmd="${1:-}"; shift || true
case "$cmd" in
  list)
    printf '%-28s %-10s %-22s %-7s %s\n' ID STATUS VERIFIED ENTRIES OWNS
    for f in $(files); do
      n="$(fm "$f" entries | awk -F' \\| ' '{print NF}')"
      printf '%-28s %-10s %-22s %-7s %s\n' "$(fm "$f" id)" "$(fm "$f" status)" "$(fm "$f" verified)" "${n:-0}" "$(fm "$f" owns)"
    done
    ;;

  impact)
    base=HEAD; ids_only=0; paths=()
    while [ $# -gt 0 ]; do
      case "$1" in --base) base="$2"; shift 2 ;; --ids) ids_only=1; shift ;; *) paths+=("$1"); shift ;; esac
    done
    if [ ${#paths[@]} -eq 0 ]; then
      while IFS= read -r p; do [ -n "$p" ] && paths+=("$p"); done < <(changed_files "$base")
    fi
    [ ${#paths[@]} -gt 0 ] || { [ "$ids_only" = 1 ] || echo "no changes"; exit 0; }
    hit=""; owned=""
    for f in $(files); do
      id="$(fm "$f" id)"
      for p in "${paths[@]}"; do
        if matches "$p" "$f"; then
          hit="$hit$id"$'\n'
          owned="$owned$p"$'\n'
          [ "$ids_only" = 1 ] || printf '%s\t%s\n' "$id" "$p"
        fi
      done
    done
    if [ "$ids_only" = 1 ]; then
      printf '%s' "$hit" | sort -u
    else
      for p in "${paths[@]}"; do grep -qxF -- "$p" <<<"$owned" || not_feature "$p" || printf 'unowned\t%s\n' "$p"; done
    fi
    ;;

  run)
    [ -x "$evidence" ] || die "evidence.sh not found at $evidence"
    ids=()
    case "${1:-}" in
      --impacted) shift; while IFS= read -r i; do [ -n "$i" ] && ids+=("$i"); done < <("$0" impact --ids "$@") ;;
      --all) for f in $(files); do ids+=("$(fm "$f" id)"); done ;;
      "") die "usage: features.sh run <id ...> | --impacted [--base REF] | --all" ;;
      *) ids=("$@") ;;
    esac
    [ ${#ids[@]} -gt 0 ] || { echo "no features to run"; exit 0; }
    rc=0
    for id in "${ids[@]}"; do
      f="$(file_of "$id")"; sc="$(fm "$f" scenario)"
      if [ -z "$sc" ]; then echo "feat:$id · NO SCENARIO (add one, or run /flow-stack:make-verifier)"; rc=1; continue; fi
      if "$evidence" "feat:$id" "$sc" >/tmp/feat.$$ 2>&1; then
        set_fm "$f" status verified
        set_fm "$f" verified "$(date +%F) $(git rev-parse --short HEAD)"
        echo "feat:$id · PASS"
      else
        set_fm "$f" status broken
        echo "feat:$id · FAIL"; tail -n 8 /tmp/feat.$$ | sed 's/^/    /'; rc=1
      fi
    done
    rm -f /tmp/feat.$$
    exit $rc
    ;;

  mark)
    [[ "${2:-}" =~ ^(verified|unverified|stale|broken)$ ]] || die "usage: features.sh mark <id> <verified|unverified|stale|broken>"
    f="$(file_of "$1")"; set_fm "$f" status "$2"
    [ "$2" = verified ] && set_fm "$f" verified "$(date +%F) $(git rev-parse --short HEAD)"
    echo "$1 → $2"
    ;;

  stale)
    write=0; [ "${1:-}" = --write ] && write=1
    for f in $(files); do
      id="$(fm "$f" id)"; sha="$(fm "$f" verified | awk '{print $2}')"
      [ -n "$sha" ] || { echo "$id · never verified"; continue; }
      git cat-file -e "$sha^{commit}" 2>/dev/null || { echo "$id · verified at unknown commit $sha"; continue; }
      specs=(); while IFS= read -r s_; do specs+=("$s_"); done < <(specs_of "$f")
      [ ${#specs[@]} -gt 0 ] || continue
      n="$(git diff --name-only "$sha" -- "${specs[@]}" | wc -l | tr -d ' ')"
      if [ "$n" -gt 0 ]; then
        echo "$id · STALE · $n owned file(s) changed since $sha"
        [ "$write" = 1 ] && set_fm "$f" status stale
      fi
    done
    ;;

  coverage)
    ign="$dir/.ignore"
    ignore_specs=(":(exclude).flow" ":(exclude)*.md" ":(exclude)**/*.md" ":(exclude).github" ":(exclude)**/*.lock" ":(exclude)*.lock" ":(exclude)**/package-lock.json" ":(exclude)LICENSE*" ":(exclude).gitignore")
    if [ -f "$ign" ]; then while IFS= read -r g; do [ -n "$g" ] && [ "${g#\#}" = "$g" ] && ignore_specs+=(":(exclude,glob)$g"); done <"$ign"; fi
    all="$(git ls-files -- . "${ignore_specs[@]}" | sort -u)"
    owned=""; dead=""; noscen=""
    for f in $(files); do
      id="$(fm "$f" id)"
      specs=(); while IFS= read -r s_; do specs+=("$s_"); done < <(specs_of "$f")
      if [ ${#specs[@]} -gt 0 ]; then
        o="$(git ls-files -- "${specs[@]}")"
        [ -n "$o" ] && owned="$owned$o"$'\n' || dead="$dead  $id: owns matches no file ($(fm "$f" owns))"$'\n'
      else dead="$dead  $id: no owns"$'\n'; fi
      [ -n "$(fm "$f" scenario)" ] || noscen="$noscen  $id"$'\n'
    done
    unowned="$(comm -23 <(printf '%s\n' "$all" | sed '/^$/d') <(printf '%s' "$owned" | sed '/^$/d' | sort -u))"
    total="$(printf '%s\n' "$all" | sed '/^$/d' | wc -l | tr -d ' ')"
    nun="$(printf '%s\n' "$unowned" | sed '/^$/d' | wc -l | tr -d ' ')"
    echo "coverage: $((total - nun))/$total code files owned by a feature"
    [ "$nun" -gt 0 ] && { echo "unowned (top 30; add to a feature's owns or to $ign):"; printf '%s\n' "$unowned" | sed '/^$/d' | head -n 30 | sed 's/^/  /'; }
    [ -n "$noscen" ] && { echo "features without a scenario:"; printf '%s' "$noscen"; }
    [ -n "$dead" ] && { echo "dead owns:"; printf '%s' "$dead"; }
    exit 0
    ;;

  check)
    [ -d "$dir" ] || die "no feature map at $dir (run /flow-stack:feature-map)"
    bad=0; seen=""
    for f in $(files); do
      id="$(fm "$f" id)"; base="$(basename "$f" .md)"
      err() { echo "✗ $base: $*"; bad=1; }
      [ -n "$id" ] || err "missing id"
      [ "$id" = "$base" ] || err "id '$id' ≠ file name '$base'"
      [[ "$id" =~ ^[a-z0-9]+([.-][a-z0-9]+)*$ ]] || err "id must be lowercase dotted (e.g. auth.login)"
      grep -qxF -- "$id" <<<"$seen" && err "duplicate id"; seen="$seen$id"$'\n'
      for k in title owns entries status; do [ -n "$(fm "$f" "$k")" ] || err "missing $k"; done
      grep -qE '^entries:.*(METHOD /path|web /path)' "$f" && err "entries still the template placeholder"
      grep -qE '^- [a-z0-9.-]+ · *$' "$f" && err "a sub-feature has no behavior text"
      [[ "$(fm "$f" status)" =~ ^(verified|unverified|stale|broken)$ ]] || err "status must be verified|unverified|stale|broken"
      for h in "Sub-features" "How to get to it" "Driving it" "Proof" "Gotchas"; do grep -q "^## $h" "$f" || err "missing section '## $h'"; done
      specs=(); while IFS= read -r s_; do specs+=("$s_"); done < <(specs_of "$f")
      [ ${#specs[@]} -eq 0 ] || [ -n "$(git ls-files -- "${specs[@]}" | head -n1)" ] || err "owns matches no tracked file"
      grep -E '^- [a-z0-9.-]+ · ' "$f" | awk '{print $2}' | while read -r sub; do
        [[ "$sub" == "$id".* ]] || echo "✗ $base: sub-feature '$sub' should start with '$id.'"
      done
    done
    [ "$bad" = 0 ] && echo "feature map ok ($(files | wc -l | tr -d ' ') features)"
    exit $bad
    ;;

  subs)
    grep -E '^- [a-z0-9.-]+ · ' "$(file_of "${1:-}")" | sed 's/^- //'
    ;;

  index)
    mkdir -p "$dir"; out="$dir/README.md"
    {
      echo "# Feature map"
      echo
      echo "The maintained, user-facing source for what this repo does and how to prove each part works."
      echo "One file per feature. Regenerate this table with \`features.sh index\`; edit the feature files, not this table."
      echo
      echo "| Feature | Status | Verified | Entry points | Owns |"
      echo "|---|---|---|---|---|"
      for f in $(files); do
        printf '| [%s](%s) · %s | %s | %s | %s | `%s` |\n' "$(fm "$f" id)" "$(basename "$f")" "$(fm "$f" title)" \
          "$(fm "$f" status)" "$(fm "$f" verified)" "$(fm "$f" entries | sed 's/ | /<br>/g')" "$(fm "$f" owns)"
      done
      echo
      echo "Status: \`verified\` (scenario passed at the recorded commit) · \`stale\` (owned code changed since) · \`broken\` (scenario failed) · \`unverified\`."
    } >"$out"
    echo "$out"
    ;;

  new)
    id="${1:-}"; title="${2:-}"
    [ -n "$id" ] && [ -n "$title" ] || die 'usage: features.sh new <id> "<title>"'
    mkdir -p "$dir"; f="$dir/$id.md"
    [ -e "$f" ] && die "exists: $f"
    sed -e "s/{{id}}/$id/g" -e "s/{{title}}/$title/g" "$here/../references/feature-template.md" >"$f"
    echo "$f"
    ;;

  -h|--help|"") sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command: $cmd (try -h)" ;;
esac
