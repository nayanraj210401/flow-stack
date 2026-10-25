#!/usr/bin/env bash
# routines.sh: scheduled flow-stack routines on GitHub Actions. Run from the target repo's root.
#   routines.sh add <name> [--preset <p>] [--force]   write .github/routines/<name>.md (from a template
#                                                     when one exists: self-create, self-heal) and render it
#   routines.sh render                                .github/routines/*.md → .github/workflows/flow-<name>.yml
#   routines.sh check                                 every routine's workflow matches a fresh render
# A routine file's frontmatter holds cron, timeout (minutes), labels, and auth (oauth | api-key); its body is the prompt.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tpl="$here/../templates"
dir=.github/routines
die() { echo "routines.sh: $*" >&2; exit 2; }

field() { # field <file> <key> <default>
  local v
  v="$(awk -v k="$2" 'NR==1&&/^---$/{on=1;next} on&&/^---$/{exit} on&&index($0,k":")==1{sub("^"k":[[:space:]]*","");print;exit}' "$1")"
  v="${v%\"}"; v="${v#\"}"
  printf '%s' "${v:-$3}"
}

render_one() { # render_one <name>: the workflow on stdout
  local f="$dir/$1.md" auth
  case "$(field "$f" auth oauth)" in
    oauth) auth='claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}' ;;
    api-key) auth='anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}' ;;
    *) die "$f: auth must be oauth or api-key" ;;
  esac
  NAME="$1" CRON="$(field "$f" cron "0 3 * * *")" TIMEOUT="$(field "$f" timeout 60)" \
  LABELS="$(field "$f" labels "$1")" AUTH="$auth" \
    perl -pe 's/\@(NAME|CRON|TIMEOUT|LABELS|AUTH)\@/$ENV{$1}/g' "$tpl/workflow.yml"
}

names() { for f in "$dir"/*.md; do [ -e "$f" ] || continue; f="${f##*/}"; [ "$f" = profile.md ] || echo "${f%.md}"; done; }

render() {
  mkdir -p .github/workflows
  local n
  for n in $(names); do render_one "$n" >".github/workflows/flow-$n.yml"; echo "rendered .github/workflows/flow-$n.yml"; done
}

profile() { # profile <preset>: a headless profile for CI runs, notifications off
  [ -f "$dir/profile.md" ] && return 0
  local h; h="$(mktemp -d)"
  FLOW_STACK_HOME="$h" "$here/../../profile/scripts/init.sh" "$1" >/dev/null
  perl -pi -e 's/^notify:\s*\S+/notify: off/' "$h/profile.md"
  cp "$h/profile.md" "$dir/profile.md" && rm -rf "$h"
  echo "wrote $dir/profile.md (preset $1; edit it: it is how the routines work)"
}

add() {
  local name="${1:-}" preset=solo-hacker force=""; shift || true
  [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "add <name>: lowercase letters, digits, dashes"
  while [ $# -gt 0 ]; do
    case "$1" in --preset) preset="$2"; shift 2 ;; --force) force=1; shift ;; *) die "unknown flag $1" ;; esac
  done
  local f="$dir/$name.md"
  [ ! -f "$f" ] || [ -n "$force" ] || die "$f exists (--force replaces it)"
  mkdir -p "$dir"
  if [ -f "$tpl/$name.md" ]; then cp "$tpl/$name.md" "$f"
  else printf -- '---\ncron: "0 3 * * *"\ntimeout: 60\nlabels: %s\n---\n# %s\n\nTODO: what this routine does, its caps, and what it must never do.\n' "$name" "$name" >"$f"
  fi
  echo "wrote $f"
  profile "$preset"
  mkdir -p .github/workflows
  render_one "$name" >".github/workflows/flow-$name.yml"; echo "rendered .github/workflows/flow-$name.yml"
}

check() {
  local n bad=0
  [ -f "$dir/profile.md" ] || { echo "✗ $dir/profile.md missing"; bad=1; }
  for n in $(names); do
    if diff -q <(render_one "$n") ".github/workflows/flow-$n.yml" >/dev/null 2>&1; then echo "✓ $n"
    else echo "✗ $n: .github/workflows/flow-$n.yml differs from $dir/$n.md (routines.sh render)"; bad=1; fi
  done
  return "$bad"
}

case "${1:-}" in
  add) shift; add "$@" ;;
  render) render ;;
  check) check ;;
  *) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
