#!/usr/bin/env bash
# seal.sh: lock the acceptance checks of the active task.
#   seal.sh add <path> [path ...]   seal files (directories expand to their files)
#   seal.sh verify                  exit 1 if any sealed file changed or vanished
#   seal.sh list                    show sealed files
#   seal.sh reseal                  re-hash every sealed file (after an approved change)
#   seal.sh rm <path>               unseal one file (needs human approval)
#
# The edit-guard and guard hooks read SEALS and make any edit to a sealed
# file an explicit human decision.
set -euo pipefail

. "$(dirname "$0")/../../../hooks/roots.sh"; flow_roots; flow_task
root="$FLOW_ROOT"
[ -n "$FLOW_TASK" ] || { echo "seal.sh: no active task" >&2; exit 2; }
seals="$FLOW_TASK_DIR/SEALS"
# SEALS names a file repo-relative in the task's home repo, "<repo>:<path>" in any other task repo.
# This repo's own entries resolve in this checkout ($FLOW_ROOT, a lead worktree included), the file add hashed.
abs_of() {
  local q="$1" n="${1%%:*}" p
  if [ "$n" != "$q" ] && [ -n "$FLOW_REPO_KEY" ] && [ "$n" = "$FLOW_REPO_KEY" ]; then printf '%s/%s' "$FLOW_ROOT" "${q#*:}"
  elif [ "$n" != "$q" ] && p="$(flow_repo_path "$n")" && [ -n "$p" ]; then printf '%s/%s' "$p" "${q#*:}"
  elif [ -z "$FLOW_REPO_KEY" ]; then printf '%s/%s' "$FLOW_ROOT" "$q"
  else printf '%s/%s' "$FLOW_TASK_HOME" "$q"; fi
}
case "${1:-}" in add|reseal|rm) [ -z "$FLOW_LANE" ] || { echo "seal.sh: refused in worktree lane '$FLOW_LANE': the task plan is shared; return this to the delegate as a gate" >&2; exit 2; }
 ;; esac
cd "$root"

# Paths reach awk through ENVIRON, never -v, which unescapes backslashes.
# Hash from stdin: shasum prefixes "\" to the hash of a file whose name has a backslash.
sha() { shasum -a 256 <"$1" | cut -d' ' -f1; }
hash_file() { printf '%s  %s\n' "$(sha "$1")" "$(flow_qual "$1")"; }

expand() {
  local p="${1#./}"
  if [ -d "$p" ]; then
    { git ls-files -- "$p"; git ls-files --others --exclude-standard -- "$p"; } | sort -u
  elif [ -f "$p" ]; then
    printf '%s\n' "$p"
  else
    echo "seal.sh: not found: $p" >&2; return 1
  fi
}

case "${1:-}" in
  add)
    shift; [ $# -gt 0 ] || { echo "usage: seal.sh add <path> ..." >&2; exit 2; }
    touch "$seals"; rc=0
    for p in "$@"; do
      [ -e "${p#./}" ] || rc=1
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        q="$(flow_qual "$f")" awk 'substr($0, 67) != ENVIRON["q"]' "$seals" >"$seals.tmp"
        mv "$seals.tmp" "$seals"
        hash_file "$f" >>"$seals"
        echo "sealed: $(flow_qual "$f")"
      done < <(expand "$p")
    done
    exit "$rc"
    ;;
  verify)
    [ -f "$seals" ] || { echo "no seals"; exit 0; }
    bad=0
    while read -r h f; do
      [ -n "$f" ] || continue
      a="$(abs_of "$f")"
      if [ ! -f "$a" ]; then echo "MISSING  $f"; bad=1
      elif [ "$(sha "$a")" != "$h" ]; then echo "CHANGED  $f"; bad=1
      fi
    done <"$seals"
    [ "$bad" = 0 ] && echo "seals intact ($(wc -l <"$seals" | tr -d ' ') files)"
    exit "$bad"
    ;;
  list) [ -f "$seals" ] && awk '{print $2}' "$seals" || echo "no seals" ;;
  reseal)
    [ -f "$seals" ] || { echo "no seals"; exit 0; }
    awk '{print $2}' "$seals" >"$seals.list"
    : >"$seals"
    while IFS= read -r f; do a="$(abs_of "$f")"; [ -f "$a" ] && printf '%s  %s\n' "$(sha "$a")" "$f" >>"$seals"; done <"$seals.list"
    rm -f "$seals.list"
    echo "resealed"
    ;;
  rm)
    [ -n "${2:-}" ] || { echo "usage: seal.sh rm <path>" >&2; exit 2; }
    line="$(q="$(flow_qual "${2#./}")" awk '$2 == ENVIRON["q"] {print; exit}' "$seals" 2>/dev/null || true)"
    [ -n "$line" ] || { echo "seal.sh: $(flow_qual "${2#./}") is not sealed (seal.sh list)" >&2; exit 1; }
    grep -vxF "$line" "$seals" >"$seals.tmp" || true
    mv "$seals.tmp" "$seals"; echo "unsealed: $(flow_qual "${2#./}")"
    ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
