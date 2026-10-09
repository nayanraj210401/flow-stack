#!/usr/bin/env bash
# probe.sh: does the check have teeth?
#   probe.sh <label> "<check command>" [--keep <path> ...]
#   probe.sh <label> "<check command>" --hollow <file> "<old text>" "<new text>" [--hollow ...]
#
# Temporarily reverts the uncommitted SOURCE changes (vs HEAD), runs the
# check, then restores everything. A check that still passes without the
# change proves nothing about the change: TOOTHLESS.
# --hollow instead swaps <old text> (must occur exactly once) for <new text>,
# e.g. a return value for an empty one ([], '', {}), and records probe:<label>:hollow.
# A check that passes when the output is empty has no teeth either.
#
# Kept (not reverted): sealed files, .flow/, --keep paths, and test-looking
# paths (tests/, test/, spec/, __tests__/, *.test.*, *.spec.*, *_test.*, test_*.py).
# Restoration runs on EXIT, including Ctrl-C.
set -uo pipefail

[ $# -ge 2 ] || { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
label="$1"; check="$2"; shift 2
keep=(); hollow=()
while [ $# -gt 0 ]; do
  case "$1" in
    --keep) keep+=("${2#./}"); shift 2 ;;
    --hollow) [ $# -ge 4 ] || { echo "probe: --hollow needs <file> <old text> <new text>" >&2; exit 2; }
      hollow+=("${2#./}" "$3" "$4"); shift 4 ;;
    *) echo "probe: unknown arg $1" >&2; exit 2 ;;
  esac
done

git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "probe: needs a git repo" >&2; exit 2; }
. "$(dirname "$0")/../../../hooks/roots.sh"; flow_roots; flow_task
cd "$FLOW_ROOT"
slug="$FLOW_TASK"
seals="$FLOW_TASK_DIR/SEALS"
ev=""
[ -n "$FLOW_TASK_DIR" ] && ev="$(flow_state_dir "$FLOW_TASK_DIR")/EVIDENCE.md"

is_kept() {
  local f="$1" k
  case "$f" in .flow/*|.gitignore) return 0 ;; esac
  [[ "$f" =~ (^|/)(tests?|spec|__tests__)/|[._-](test|spec)\.[a-z]+$|_test\.[a-z]+$|(^|/)test_[^/]*\.py$ ]] && return 0
  [ -f "$seals" ] && awk -v p="$(flow_qual "$f")" '$2 == p {found=1} END {exit !found}' "$seals" && return 0
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
trap restore EXIT; trap 'exit 130' INT TERM

if [ "${#hollow[@]}" -gt 0 ]; then
  mode=hollowed; label="$label:hollow"
  for ((i = 0; i < ${#hollow[@]}; i += 3)); do
    f="${hollow[i]}"; old="${hollow[i+1]}"; new="${hollow[i+2]}"
    c="$(cat "$f" 2>/dev/null; printf x)"; c="${c%x}"
    [[ -n "$old" && "$c" == *"$old"* ]] || { echo "probe: --hollow text not found in $f" >&2; exit 2; }
    rest="${c#*"$old"}"
    [[ "$rest" != *"$old"* ]] || { echo "probe: --hollow text occurs more than once in $f; quote more of it" >&2; exit 2; }
    [ -e "$stash/${f//\//__}" ] || { cp "$f" "$stash/${f//\//__}"; reverted+=("M $f"); }
    printf '%s' "${c%%"$old"*}$new$rest" >"$f"
  done
else
mode=reverted
while IFS=$'\t' read -r status f; do
  [ -n "$f" ] || continue
  is_kept "$f" && continue
  case "$status" in
    D) git show "HEAD:$f" >"$f" 2>/dev/null && reverted+=("D $f") ;;
    A) cp "$f" "$stash/${f//\//__}" && rm -f "$f" && reverted+=("A $f") ;;
    *) cp "$f" "$stash/${f//\//__}" && git show "HEAD:$f" >"$f" && reverted+=("M $f") ;;
  esac
done < <(git diff --name-status --no-renames HEAD; git ls-files --others --exclude-standard | awk '{print "A\t" $0}')
fi

if [ "${#reverted[@]}" -eq 0 ]; then
  echo "probe: no uncommitted source changes to revert; nothing to probe."
  echo "flow-probe: SKIPPED"
  exit 0
fi

note=""
if [ "$mode" = hollowed ]; then
  echo "probe: hollowed ${#reverted[@]} file(s); running check with the output emptied…"
else
  echo "probe: reverted ${#reverted[@]} source file(s); running check without the change…"
  if ! printf '%s\n' "${reverted[@]}" | grep -qv '^A '; then
    note="only new files were reverted, so TEETH proves the check imports them, not that its assertions bite; also run --hollow"
    echo "probe: $note"
  fi
fi
out="$(mktemp)"
bash -c "$check" >"$out" 2>&1
code=$?

if [ "$code" -ne 0 ]; then verdict=TEETH; else verdict=TOOTHLESS; fi
if [ -n "$ev" ]; then
  mkdir -p "$(dirname "$ev")"
  {
    printf '### %s · probe:%s · %s · exit=%s\n' "$(date -u +%FT%TZ)" "$label" "$verdict" "$code"
    printf -- '- cmd (on %s source): `%s`\n' "$mode" "$check"
    printf -- '- %s: %s\n' "$mode" "$(printf '%s ' "${reverted[@]#* }")"
    [ -z "$note" ] || printf -- '- note: %s\n' "$note"
    printf '\n'
  } >>"$ev"
fi
tail -n 8 "$out"; rm -f "$out"
echo "flow-probe: $verdict"
[ "$verdict" = TEETH ]
