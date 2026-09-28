#!/usr/bin/env bash
# probe.sh: does the check have teeth?
#   probe.sh <label> "<check command>" [--keep <path> ...]
#
# Temporarily reverts the uncommitted SOURCE changes (vs HEAD), runs the
# check, then restores everything. A check that still passes without the
# change proves nothing about the change: TOOTHLESS.
#
# Kept (not reverted): sealed files, .flow/, --keep paths, and test-looking
# paths (tests/, test/, spec/, __tests__/, *.test.*, *.spec.*, *_test.*, test_*.py).
# Restoration runs on EXIT, including Ctrl-C.
set -uo pipefail

[ $# -ge 2 ] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
label="$1"; check="$2"; shift 2
keep=()
while [ $# -gt 0 ]; do
  case "$1" in --keep) keep+=("${2#./}"); shift 2 ;; *) echo "probe: unknown arg $1" >&2; exit 2 ;; esac
done

git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "probe: needs a git repo" >&2; exit 2; }
. "$(dirname "$0")/../../../hooks/roots.sh"; flow_roots
cd "$FLOW_ROOT"
slug="$(head -n1 "$FLOW_DIR/ACTIVE" 2>/dev/null | tr -d '[:space:]' || true)"
seals="$FLOW_DIR/tasks/$slug/SEALS"
ev=""
[ -n "$slug" ] && [ -d "$FLOW_DIR/tasks/$slug" ] && ev="$(flow_state_dir "$FLOW_DIR/tasks/$slug")/EVIDENCE.md"

is_kept() {
  local f="$1" k
  case "$f" in .flow/*|.gitignore) return 0 ;; esac
  [[ "$f" =~ (^|/)(tests?|spec|__tests__)/|[._-](test|spec)\.[a-z]+$|_test\.[a-z]+$|(^|/)test_[^/]*\.py$ ]] && return 0
  [ -f "$seals" ] && awk -v p="$f" '$2 == p {found=1} END {exit !found}' "$seals" && return 0
  for k in "${keep[@]:-}"; do [ -n "$k" ] && [[ "$f" == "$k" || "$f" == "$k"/* ]] && return 0; done
  return 1
}

stash="$(mktemp -d)"
reverted=()   # entries: "<kind> <path>"  kind = M (tracked modified), A (untracked/new), D (deleted)
restore() {
  for e in "${reverted[@]:-}"; do
    [ -n "$e" ] || continue
    kind="${e%% *}"; f="${e#* }"; saved="$stash/${f//\//__}"
    case "$kind" in
      M) cp "$saved" "$f" ;;
      A) mkdir -p "$(dirname "$f")"; mv "$saved" "$f" ;;
      D) rm -f "$f" ;;
    esac
  done
  rm -rf "$stash"
}
trap restore EXIT INT TERM

while IFS=$'\t' read -r status f; do
  [ -n "$f" ] || continue
  is_kept "$f" && continue
  case "$status" in
    D) git show "HEAD:$f" >"$f" 2>/dev/null && reverted+=("D $f") ;;
    A) cp "$f" "$stash/${f//\//__}" && rm -f "$f" && reverted+=("A $f") ;;
    *) cp "$f" "$stash/${f//\//__}" && git show "HEAD:$f" >"$f" && reverted+=("M $f") ;;
  esac
done < <(git diff --name-status --no-renames HEAD; git ls-files --others --exclude-standard | awk '{print "A\t" $0}')

if [ "${#reverted[@]}" -eq 0 ]; then
  echo "probe: no uncommitted source changes to revert; nothing to probe."
  echo "flow-probe: SKIPPED"
  exit 0
fi

echo "probe: reverted ${#reverted[@]} source file(s); running check without the change…"
out="$(mktemp)"
bash -c "$check" >"$out" 2>&1
code=$?

if [ "$code" -ne 0 ]; then verdict=TEETH; else verdict=TOOTHLESS; fi
if [ -n "$ev" ]; then
  mkdir -p "$(dirname "$ev")"
  {
    printf '### %s · probe:%s · %s · exit=%s\n' "$(date -u +%FT%TZ)" "$label" "$verdict" "$code"
    printf -- '- cmd (on reverted source): `%s`\n' "$check"
    printf -- '- reverted: %s\n' "$(printf '%s ' "${reverted[@]#* }")"
    printf '\n'
  } >>"$ev"
fi
tail -n 8 "$out"; rm -f "$out"
echo "flow-probe: $verdict"
[ "$verdict" = TEETH ]
