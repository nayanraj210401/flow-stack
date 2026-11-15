#!/usr/bin/env bash
# suites.sh: run the part of the test suite a change touches, not all of it.
#   suites.sh list                              id · paths · command, as declared
#   suites.sh pick [--base REF] [--all] [path ...]
#                                               the suites to run, one "id<TAB>command" per line; why, on stderr
#   suites.sh run  [--base REF] [--all] [path ...]
#                                               run them through evidence.sh (label test:<id>, or test for the
#                                               full suite); exits non-zero when any fails
#   suites.sh check                             lint the declarations: ids, commands, globs that match no file
#
# Declared in <repo>/.flow/config.json:
#   "tests": {
#     "suites": [{"id": "auth", "paths": ["src/auth/**", "test/auth/**"], "run": "npm test -- test/auth"}],
#     "ignore": ["docs/**"],        changed files that need no test (beyond *.md, LICENSE, .gitignore, .flow/)
#     "scope": "impacted",          impacted (default) | full: always run the full suite (any other value: full)
#     "unmatched": "full"           a changed file no suite claims: full (default) runs the full suite, skip ignores it
#                                   (any other value: full)
#   }
# scope and unmatched may also be set for every repo in ~/.flow-stack/settings.json "tests"; the repo wins.
# The full suite is commands.test, or every suite when there is none. Changed files: uncommitted and
# untracked vs HEAD, or with --base everything since REF (a ref git can't diff → full suite). Explicit
# paths replace both. A suite's paths win over the ignores; a change to a tracked .flow/config.json runs
# the full suite.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../../../hooks/lib.sh"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "suites.sh: needs a git repo" >&2; exit 2; }
cd "$root"; flow_roots "$root"
cfg="$FLOW_DIR/config.json"; [ -f "$FLOW_ROOT/.flow/config.json" ] && cfg="$FLOW_ROOT/.flow/config.json"
settings="$FLOW_HOME/settings.json"
evidence="$here/evidence.sh"

die() { echo "suites.sh: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "needs jq"
setting() { # setting <key> <default>: repo config, then settings.json, then the default
  local v f
  for f in "$cfg" "$settings"; do
    [ -f "$f" ] || continue
    v="$(jq -r --arg k "$1" '.tests[$k] // empty | tostring' "$f" 2>/dev/null)"
    [ -n "$v" ] && { printf '%s' "$v"; return; }
  done
  printf '%s' "$2"
}
suites() { jq -r '.tests.suites // [] | to_entries[] | [.key, (.value.id // ""), (.value.paths // [] | join(" "))] | @tsv' "$cfg" 2>/dev/null; }
suite_run() { jq -r --argjson i "$1" '.tests.suites[$i].run // ""' "$cfg" 2>/dev/null; }  # by index: @tsv mangles backslashes
full_cmd() { jq -r '.commands.test // empty' "$cfg" 2>/dev/null; }
ignored() { # checked after the suites' claims, so a suite can claim *.md
  local p="$1" g
  case "$p" in .flow/*|*.md|LICENSE*|.gitignore|.gitattributes|.editorconfig) return 0 ;; esac
  while IFS= read -r g; do
    [ -n "$g" ] && glob_match "$p" "$g" && return 0
  done < <(jq -r '.tests.ignore // [] | .[]' "$cfg" 2>/dev/null)
  return 1
}

base=""; all=0; paths=()
parse() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --base) [ $# -ge 2 ] || die "--base needs a ref"; base="$2"; shift ;;
      --all) all=1 ;;
      -*) die "unknown flag $1" ;;
      *) paths+=("$1") ;;
    esac
    shift
  done
}
git_() { git -c core.quotePath=false "$@"; }  # unquoted non-ASCII paths, so globs match them
changed() { # fails when the diff can't be computed (a bad --base)
  if [ "${#paths[@]}" -gt 0 ]; then printf '%s\n' "${paths[@]}"; return; fi
  local d; d="$(git_ diff --name-only --no-renames "${base:-HEAD}" -- 2>/dev/null)" || return 1
  { [ -z "$d" ] || printf '%s\n' "$d"; git_ ls-files --others --exclude-standard; } | sort -u
}
full() { # the full suite as id<TAB>index-or-command lines
  local c; c="$(full_cmd)"
  if [ -n "$c" ]; then printf 'test\t-\n'; return; fi
  suites | while IFS=$'\t' read -r i id _; do [ -n "$id" ] && printf '%s\t%s\n' "$id" "$i"; done
}

# pick_raw: "id<TAB>index" (index - means commands.test), reasons on stderr
pick_raw() {
  local n; n="$(jq -r '.tests.suites // [] | length' "$cfg" 2>/dev/null || echo 0)"
  if [ "$all" = 1 ]; then echo "suites: --all → full suite" >&2; full; return; fi
  local scope; scope="$(setting scope impacted)"
  if [ "$scope" != impacted ]; then echo "suites: tests.scope $scope → full suite" >&2; full; return; fi
  if [ "${n:-0}" -eq 0 ]; then echo "suites: no tests.suites in .flow/config.json → full suite" >&2; full; return; fi
  local files f hit i id globs unmatched="" picked=""
  files="$(changed)" || { echo "suites: can't diff against '$base' → full suite" >&2; full; return; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ "$f" = .flow/config.json ] && git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
      echo "suites: .flow/config.json changed → full suite" >&2; full; return
    fi
    hit=""
    while IFS=$'\t' read -r i id globs; do
      [ -n "$id" ] && [ -n "$globs" ] || continue
      if flow_is_test "$f" "$globs"; then
        hit=1
        case " $picked " in *" $i "*) ;; *) picked="$picked $i"; echo "suites: $f → $id" >&2 ;; esac
      fi
    done < <(suites)
    [ -n "$hit" ] || ignored "$f" || unmatched="$unmatched $f"
  done <<<"$files"
  if [ -n "$unmatched" ]; then
    if [ "$(setting unmatched full)" != skip ]; then
      echo "suites: no suite claims$unmatched → full suite (tests.unmatched skip ignores such files)" >&2
      full; return
    fi
    echo "suites: no suite claims$unmatched; skipped (tests.unmatched skip)" >&2
  fi
  [ -n "$picked" ] || { echo "suites: nothing changed that a suite covers" >&2; return; }
  for i in $picked; do printf '%s\t%s\n' "$(jq -r --argjson i "$i" '.tests.suites[$i].id' "$cfg")" "$i"; done
}
cmd_of() { if [ "$1" = - ]; then full_cmd; else suite_run "$1"; fi; }

case "${1:-}" in
  list)
    suites | while IFS=$'\t' read -r i id globs; do printf '%s · %s · %s\n' "${id:-?}" "${globs:-(no paths)}" "$(suite_run "$i")"; done
    [ -z "$(full_cmd)" ] || printf 'test (full) · * · %s\n' "$(full_cmd)" ;;
  pick)
    shift; parse "$@"
    pick_raw | while IFS=$'\t' read -r id i; do printf '%s\t%s\n' "$id" "$(cmd_of "$i")"; done ;;
  run)
    shift; parse "$@"
    rows="$(pick_raw)"
    [ -n "$rows" ] || { echo "suites: no tests to run"; exit 0; }
    fails=0
    while IFS=$'\t' read -r id i; do
      c="$(cmd_of "$i")"
      [ -n "$c" ] || { echo "suites: $id has no run command" >&2; fails=$((fails + 1)); continue; }
      label="test:$id"; [ "$i" = - ] && label=test
      "$evidence" "$label" "$c" </dev/null || fails=$((fails + 1))
    done <<<"$rows"
    [ "$fails" -eq 0 ] || { echo "suites: $fails failed"; exit 1; } ;;
  check)
    bad=0; seen=" "
    while IFS=$'\t' read -r i id globs; do
      if ! [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]]; then echo "✗ suite #$i: id '$id' must match [A-Za-z0-9._-]+"; bad=1; continue; fi
      case "$seen" in *" $id "*) echo "✗ $id: declared twice"; bad=1 ;; esac; seen="$seen$id "
      [ -n "$(suite_run "$i")" ] || { echo "✗ $id: no run command"; bad=1; }
      [ -n "$globs" ] || { echo "✗ $id: no paths"; bad=1; }
      set -f
      for g in $globs; do
        git_ ls-files | while IFS= read -r f; do glob_match "$f" "$g" && { echo y; break; }; done | grep -q y || { echo "✗ $id: '$g' matches no tracked file"; bad=1; }
      done
      set +f
    done < <(suites)
    for k in scope:impacted:full unmatched:full:skip; do
      IFS=: read -r key a b <<<"$k"; v="$(setting "$key" "$a")"
      [ "$v" = "$a" ] || [ "$v" = "$b" ] || { echo "✗ tests.$key '$v' must be $a or $b"; bad=1; }
    done
    [ "$bad" = 0 ] && echo "suites: $(jq -r '.tests.suites // [] | length' "$cfg" 2>/dev/null || echo 0) ok"
    exit "$bad" ;;
  -h|--help|help|"") sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; [ -n "${1:-}" ] || exit 2 ;;
  *) die "unknown command '$1' (list | pick | run | check)" ;;
esac
