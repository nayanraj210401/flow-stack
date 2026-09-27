#!/usr/bin/env bash
# check.sh: lint ~/.flow-stack/profile.md
#   - Rules ≤ 20 lines; Taste entries dated and sourced; repo paths exist;
#   - stale taste: entries older than 60 days are listed as retirement candidates.
set -uo pipefail
f="${FLOW_STACK_HOME:-$HOME/.flow-stack}/profile.md"
[ -f "$f" ] || { echo "no profile at $f (run /flow-stack:setup)"; exit 1; }
clean="$(perl -0pe 's/<!--.*?-->\n?//gs' "$f")"
section() { awk -v h="# $1" '$0==h{on=1;next} on && /^# /{exit} on' <<<"$clean"; }
problems=0
warn() { echo "✗ $*"; problems=$((problems+1)); }

head -n1 "$f" | grep -qx -- '---' || warn "frontmatter missing"
n="$(section Rules | grep -c '^- ' || true)"
[ "$n" -le 20 ] || warn "Rules has $n lines (max 20); move preferences to Taste"
[ "$n" -ge 1 ] || warn "Rules is empty; add at least your push/deploy rule"

section Taste | grep '^- ' | while IFS= read -r l; do
  [[ "$l" =~ ^-\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ ·\ .+\ ·\ src:\ .+ ]] || echo "✗ taste entry not in '- YYYY-MM-DD · <pref> · src: <source>' form: $l"
done

section Repos | awk '/^- path:/{sub(/^- path:[[:space:]]*/,""); print}' | while IFS= read -r p; do
  p="${p/#\~/$HOME}"
  [ -d "$p" ] || echo "✗ repo path does not exist: $p"
done

cutoff="$(date -v-60d +%F 2>/dev/null || date -d '60 days ago' +%F)"
stale="$(section Taste | grep -Eo '^- [0-9]{4}-[0-9]{2}-[0-9]{2} · [^·]+' | awk -v c="$cutoff" '$2 < c' || true)"
[ -n "$stale" ] && { echo "? taste older than 60 days; still true? (reflect can retire)"; sed 's/^/  /' <<<"$stale"; }

total="$(perl -0pe 's/<!--.*?-->\n?//gs' "$f" | wc -l | tr -d ' ')"
echo "profile: $f · $total lines (without comments) · $problems structural problem(s)"
[ "$problems" -eq 0 ]
