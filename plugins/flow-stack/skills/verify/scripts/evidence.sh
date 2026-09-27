#!/usr/bin/env bash
# evidence.sh: run a check and record the result as evidence.
#   evidence.sh <label> <command string> [artifact-path ...]
#
# <label> is a slice or check id (S1, C2, blind, probe:S1 …).
# Appends a block to the active task's EVIDENCE.md, prints the output tail,
# and ends with one machine-readable line the circuit breaker reads:
#   flow-evidence: PASS
#   flow-evidence: FAIL sig=<hash>
# Exits with the command's exit code.
set -uo pipefail

[ $# -ge 2 ] || { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
label="$1"; check="$2"; shift 2

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
slug="$(head -n1 "$root/.flow/ACTIVE" 2>/dev/null | tr -d '[:space:]' || true)"
ev=""
[ -n "$slug" ] && [ -d "$root/.flow/tasks/$slug" ] && ev="$root/.flow/tasks/$slug/EVIDENCE.md"

out="$(mktemp)"
start=$(date +%s)
( cd "$root" && bash -c "$check" ) >"$out" 2>&1
code=$?
secs=$(( $(date +%s) - start ))

if [ "$code" -eq 0 ]; then
  verdict=PASS; sigpart=""
else
  verdict=FAIL
  # Signature: the failure's shape with volatile parts (numbers, hex, tmp paths) removed.
  sig="$(tail -n 30 "$out" | sed -E 's#/(tmp|var|private)/[^ ]*#TMP#g; s/0x[0-9a-f]+/HEX/g; s/[0-9]+(\.[0-9]+)?(ms|s)?/N/g' | shasum | cut -c1-10)"
  sigpart=" sig=$sig"
fi

if [ -n "$ev" ]; then
  head_sha="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo none)"
  dirty="$([ -n "$(git -C "$root" status --porcelain 2>/dev/null | grep -v '^?? .flow/' || true)" ] && echo yes || echo no)"
  {
    printf '### %s · %s · %s · exit=%s\n' "$(date -u +%FT%TZ)" "$label" "$verdict" "$code"
    printf -- '- cmd: `%s`\n' "$check"
    printf -- '- head: %s  dirty: %s  took: %ss\n' "$head_sha" "$dirty" "$secs"
    for a in "$@"; do printf -- '- artifact: %s\n' "$a"; done
    printf '<details><summary>output (last 40 lines)</summary>\n\n```\n'
    tail -n 40 "$out"
    printf '```\n</details>\n\n'
  } >>"$ev"
else
  echo "evidence.sh: no active task; result not recorded" >&2
fi

tail -n 15 "$out"
rm -f "$out"
echo "flow-evidence: ${verdict}${sigpart}"
exit "$code"
