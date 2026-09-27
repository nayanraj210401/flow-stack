#!/usr/bin/env bash
# blind-run.sh: run the active task's blind checks without showing them.
#   blind-run.sh
#
# blind/MANIFEST lines:
#   run: <command that runs the blind checks once installed>
#   file: <name in blind/> -> <repo-relative target path>
#
# Each file is copied into place, the run command executes, and every copy
# is removed again (pre-existing targets are restored). Only the verdict and
# failing test names are reported and recorded; assertion details are not,
# so the builder cannot fit the code to the expected values.
set -uo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
slug="$(head -n1 "$root/.flow/ACTIVE" 2>/dev/null | tr -d '[:space:]' || true)"
[ -n "$slug" ] || { echo "blind-run: no active task" >&2; exit 2; }
blind="$root/.flow/tasks/$slug/blind"
manifest="$blind/MANIFEST"
[ -f "$manifest" ] || { echo "blind-run: no blind checks for $slug (nothing to run)"; exit 0; }

run_cmd="$(sed -n 's/^run:[[:space:]]*//p' "$manifest" | head -n1)"
[ -n "$run_cmd" ] || { echo "blind-run: MANIFEST has no run: line" >&2; exit 2; }

backup="$(mktemp -d)"
installed=()
cleanup() {
  for t in "${installed[@]:-}"; do
    [ -n "$t" ] || continue
    if [ -f "$backup/${t//\//__}" ]; then mv "$backup/${t//\//__}" "$root/$t"; else rm -f "$root/$t"; fi
  done
  rm -rf "$backup"
}
trap cleanup EXIT

while IFS= read -r line; do
  src="$(sed -E 's/^file:[[:space:]]*(.*)[[:space:]]+->[[:space:]]+.*$/\1/' <<<"$line")"
  dst="$(sed -E 's/^.*->[[:space:]]+//' <<<"$line")"
  [ -f "$blind/$src" ] || { echo "blind-run: missing blind/$src" >&2; exit 2; }
  mkdir -p "$(dirname "$root/$dst")"
  [ -f "$root/$dst" ] && cp "$root/$dst" "$backup/${dst//\//__}"
  cp "$blind/$src" "$root/$dst"
  installed+=("$dst")
done < <(grep -E '^file:' "$manifest")

out="$(mktemp)"
( cd "$root" && bash -c "$run_cmd" ) >"$out" 2>&1
code=$?

failing="$(grep -E '(✕|✗|×|FAIL|FAILED|failed|Error:)' "$out" | grep -viE '^(tests?|suites?):|[0-9]+ (failed|passed)' | cut -c1-100 | sort -u | head -n 10 || true)"
rm -f "$out"
verdict=$([ "$code" -eq 0 ] && echo PASS || echo FAIL)

{
  printf '### %s · blind · %s · exit=%s\n' "$(date -u +%FT%TZ)" "$verdict" "$code"
  printf -- '- held-out checks: %s file(s); details withheld by design\n' "${#installed[@]}"
  [ -n "$failing" ] && printf -- '- failing (names only):\n%s\n' "$(sed 's/^/  - /' <<<"$failing")"
  printf '\n'
} >>"$root/.flow/tasks/$slug/EVIDENCE.md"

echo "blind checks: $verdict (${#installed[@]} file(s))"
[ -n "$failing" ] && printf 'failing (names only):\n%s\n' "$failing"
if [ "$code" -eq 0 ]; then echo "flow-evidence: PASS"; else echo "flow-evidence: FAIL sig=blind$(printf '%s' "$failing" | shasum | cut -c1-5)"; fi
exit "$code"
