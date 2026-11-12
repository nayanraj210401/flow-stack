#!/usr/bin/env bash
# diffstat.sh: how much code this change adds vs removes (uncommitted, vs HEAD).
#   diffstat.sh [glob ...]    limit to repo-relative globs (e.g. a slice's fence)
# Prints:  added=<n> removed=<n> net=<n> changed=<n> new_files=<n> deleted_files=<n>
# followed by per-file rows. .flow/ is always excluded.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "diffstat: needs a git repo" >&2; exit 2; }
cd "$root"
. "$here/../../../hooks/lib.sh"
specs=("." ":(exclude).flow")
# Fences match the way the fence hook does (glob_match: * crosses /), not as git pathspecs.
want() { local g; [ ${#globs[@]} -eq 0 ] && return 0; for g in "${globs[@]}"; do glob_match "$1" "$g" && return 0; done; return 1; }
globs=("$@")
keep() { local line; while IFS= read -r line; do [ -n "$line" ] && want "$(cut -f3 <<<"$line")" && printf '%s\n' "$line"; done; }

rows="$({
  git -c core.quotepath=off diff --numstat --no-renames HEAD -- "${specs[@]}" 2>/dev/null | awk -F'\t' '{a=($1=="-"?0:$1); r=($2=="-"?0:$2); print a "\t" r "\t" $3 "\tM"}'
  git -c core.quotepath=off ls-files --others --exclude-standard -- "${specs[@]}" 2>/dev/null | while IFS= read -r f; do
    n="$(git diff --numstat --no-index /dev/null "$f" 2>/dev/null | cut -f1)"   # numstat count, like tracked files; "-" = binary
    printf '%s\t0\t%s\tA\n' "$([ "${n:--}" = - ] && echo 0 || echo "$n")" "$f"
  done
} | keep)"
deleted="$(git -c core.quotepath=off diff --diff-filter=D --name-only --no-renames HEAD -- "${specs[@]}" 2>/dev/null | while IFS= read -r f; do want "$f" && echo x; done | wc -l | tr -d ' ')"

awk -F'\t' -v del="$deleted" '
  NF >= 3 { a += $1; r += $2; if ($4 == "A") n++; rows[++k] = sprintf("  %+5d %-5s %s%s", $1 - $2, "-" $2, $3, ($4 == "A" ? "  (new)" : "")) }
  END {
    printf "added=%d removed=%d net=%+d changed=%d new_files=%d deleted_files=%d\n", a, r, a - r, a + r, n, del
    for (i = 1; i <= k; i++) print rows[i]
  }' <<<"$rows"
