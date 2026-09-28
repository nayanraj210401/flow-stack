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

. "$(dirname "$0")/../../../hooks/roots.sh"; flow_roots
root="$FLOW_ROOT"
slug="$(head -n1 "$FLOW_DIR/ACTIVE" 2>/dev/null | tr -d '[:space:]' || true)"
[ -n "$slug" ] || { echo "seal.sh: no active task" >&2; exit 2; }
seals="$FLOW_DIR/tasks/$slug/SEALS"
case "${1:-}" in add|reseal|rm) [ -z "$FLOW_LANE" ] || { echo "seal.sh: refused in worktree lane '$FLOW_LANE': the task plan is shared; return this to the delegate as a gate" >&2; exit 2; }
 ;; esac
cd "$root"

hash_file() { shasum -a 256 "$1" | awk -v p="$1" '{print $1 "  " p}'; }

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
    touch "$seals"
    for p in "$@"; do
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        grep -v "  $f\$" "$seals" >"$seals.tmp" || true
        mv "$seals.tmp" "$seals"
        hash_file "$f" >>"$seals"
        echo "sealed: $f"
      done < <(expand "$p")
    done
    ;;
  verify)
    [ -f "$seals" ] || { echo "no seals"; exit 0; }
    bad=0
    while read -r h f; do
      [ -n "$f" ] || continue
      if [ ! -f "$f" ]; then echo "MISSING  $f"; bad=1
      elif [ "$(shasum -a 256 "$f" | awk '{print $1}')" != "$h" ]; then echo "CHANGED  $f"; bad=1
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
    while IFS= read -r f; do [ -f "$f" ] && hash_file "$f" >>"$seals"; done <"$seals.list"
    rm -f "$seals.list"
    echo "resealed"
    ;;
  rm)
    [ -n "${2:-}" ] || { echo "usage: seal.sh rm <path>" >&2; exit 2; }
    grep -v "  ${2#./}\$" "$seals" >"$seals.tmp" || true
    mv "$seals.tmp" "$seals"; echo "unsealed: $2"
    ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
