#!/usr/bin/env bash
# scan-repos.sh [dir ...]: list git repos (depth ≤ 3) with a guess at their test/run commands.
# Default dirs: ~/Project ~/Projects ~/code ~/src ~/dev ~/work
set -uo pipefail
dirs=("$@"); [ ${#dirs[@]} -gt 0 ] || dirs=("$HOME/Project" "$HOME/Projects" "$HOME/code" "$HOME/src" "$HOME/dev" "$HOME/work")
for base in "${dirs[@]}"; do
  [ -d "$base" ] || continue
  find "$base" -maxdepth 3 -name .git -type d -prune 2>/dev/null | while read -r g; do
    r="$(dirname "$g")"
    last="$(git -C "$r" log -1 --format=%cs 2>/dev/null || echo '-')"
    kind=""; test=""; run=""
    if [ -f "$r/package.json" ]; then kind=node
      test="$(jq -r '.scripts.test // empty' "$r/package.json" 2>/dev/null | cut -c1-40)"; [ -n "$test" ] && test="npm test"
      jq -e '.scripts.dev' "$r/package.json" >/dev/null 2>&1 && run="npm run dev"
    elif [ -f "$r/pyproject.toml" ] || [ -f "$r/requirements.txt" ]; then kind=python; test="pytest"
    elif [ -f "$r/go.mod" ]; then kind=go; test="go test ./..."
    elif [ -f "$r/Cargo.toml" ]; then kind=rust; test="cargo test"
    elif [ -f "$r/Makefile" ]; then kind=make; grep -q '^test:' "$r/Makefile" && test="make test"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$last" "${r/#$HOME/~}" "${kind:--}" "${test:--}" "${run:--}"
  done
done | sort -r | awk -F'\t' 'BEGIN{print "last-commit\tpath\tkind\ttest\trun"} {print}'
