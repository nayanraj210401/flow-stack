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

# Frontmatter values: the template's comments are the table ("key: default  # a | b | c: note").
# Unknown keys warn (newer plugin, typo); missing keys keep their defaults.
fm() { awk 'NR==1 && $0=="---" {on=1; next} on && $0=="---" {exit} on && /^[[:space:]]*[a-z_]+:/' "$1"; }
tpl="$(dirname "$0")/../../../templates/profile.md"
table="$(fm "$tpl" | awk '{
  k = $1; sub(/:.*/, "", k); c = ""
  if (match($0, / #/)) { c = substr($0, RSTART + 2); sub(/: .*/, "", c) }
  n = (c ~ /\|/) ? split(c, a, "|") : 0; c = ""
  for (i = 1; i <= n; i++) { v = a[i]; sub(/^[[:space:]]+/, "", v); sub(/[[:space:](].*/, "", v); c = c (i > 1 ? " | " : "") v }
  print k "\t" c }')"
trim() { local s="${1#"${1%%[![:space:]]*}"}"; printf %s "${s%"${s##*[![:space:]]}"}"; }
while IFS= read -r line; do
  k="$(trim "${line%%:*}")"
  v="${line#*:}"; v="$(trim "${v%%#*}")"
  row="$(grep -m1 "^$k"$'\t' <<<"$table")" || { echo "? unknown profile key: $k (not in the template; typo or newer plugin?)"; continue; }
  allowed="${row#*$'\t'}"
  [ -n "$allowed" ] && [ -n "$v" ] || continue
  match=0
  IFS='|' read -ra alts <<<"$allowed"
  for a in "${alts[@]}"; do a="$(trim "$a")"; a="${a/<*>/?*}"; [[ "$v" == $a ]] && match=1; done
  [ "$match" = 1 ] || warn "$k: $v is not one of: $allowed"
done < <(fm "$f")

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
