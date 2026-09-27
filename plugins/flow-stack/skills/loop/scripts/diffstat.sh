#!/usr/bin/env bash
# diffstat.sh: how much code this change adds vs removes (uncommitted, vs HEAD).
#   diffstat.sh [glob ...]    limit to repo-relative globs (e.g. a slice's fence)
# Prints:  added=<n> removed=<n> net=<n> changed=<n> new_files=<n> deleted_files=<n>
# followed by per-file rows. .flow/ is always excluded.
set -uo pipefail
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "diffstat: needs a git repo" >&2; exit 2; }
cd "$root"
specs=()
for g in "$@"; do specs+=(":(glob)$g"); done
[ ${#specs[@]} -gt 0 ] || specs=(".")
specs+=(":(exclude).flow")

rows="$(
  git diff --numstat HEAD -- "${specs[@]}" 2>/dev/null | awk -F'\t' '{a=($1=="-"?0:$1); r=($2=="-"?0:$2); print a "\t" r "\t" $3 "\tM"}'
  git ls-files --others --exclude-standard -- "${specs[@]}" 2>/dev/null | while IFS= read -r f; do
    printf '%s\t0\t%s\tA\n' "$(wc -l <"$f" | tr -d ' ')" "$f"
  done
)"
deleted="$(git diff --diff-filter=D --name-only HEAD -- "${specs[@]}" 2>/dev/null | wc -l | tr -d ' ')"

awk -F'\t' -v del="$deleted" '
  NF >= 3 { a += $1; r += $2; if ($4 == "A") n++; rows[++k] = sprintf("  %+5d %-5s %s%s", $1 - $2, "-" $2, $3, ($4 == "A" ? "  (new)" : "")) }
  END {
    printf "added=%d removed=%d net=%+d changed=%d new_files=%d deleted_files=%d\n", a, r, a - r, a + r, n, del
    for (i = 1; i <= k; i++) print rows[i]
  }' <<<"$rows"
