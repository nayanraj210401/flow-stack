#!/usr/bin/env bash
# init.sh: create ~/.flow-stack/profile.md from the template and a preset.
#   init.sh <preset|none>        refuses to overwrite an existing profile
#   init.sh <preset> --force     overwrite (a timestamped backup is kept)
# Presets: senior-backend frontend-product data-ml learning-mode solo-hacker none
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tpl="$here/../../../templates"
home="${FLOW_STACK_HOME:-$HOME/.flow-stack}"
out="$home/profile.md"
preset="${1:-}"; force="${2:-}"
[ -n "$preset" ] || { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
if [ "$preset" != none ] && [ ! -f "$tpl/presets/$preset.md" ]; then
  echo "init.sh: unknown preset '$preset'" >&2; ls "$tpl/presets" | sed 's/\.md$//' >&2; exit 2
fi
mkdir -p "$home"
if [ -f "$out" ]; then
  [ "$force" = --force ] || { echo "init.sh: $out exists (use --force to replace; a backup is kept)" >&2; exit 1; }
  cp "$out" "$out.bak.$(date +%Y%m%d%H%M%S)"
fi
cp "$tpl/profile.md" "$out"
if [ "$preset" != none ]; then
  p="$tpl/presets/$preset.md"; today="$(date +%F)"
  perl -pi -e "s/^preset: none(\s+#.*)?\$/preset: $preset\$1/" "$out"
  # frontmatter overrides from the preset's yaml block
  rev="$(sed -n '/^```yaml/,/^```/p' "$p")"
  rmin="$(grep -Eo 'review_minutes_per_day: *[0-9]+' <<<"$rev" | grep -Eo '[0-9]+' || true)"
  maxa="$(grep -Eo 'max_parallel_agents: *[0-9]+' <<<"$rev" | grep -Eo '[0-9]+' || true)"
  dojo="$(grep -Eo '^dojo: *[a-z]+' <<<"$rev" | awk '{print $2}' || true)"
  [ -n "$rmin" ] && perl -pi -e "s/(review_minutes_per_day:\s*)\d+/\${1}$rmin/" "$out"
  [ -n "$maxa" ] && perl -pi -e "s/(max_parallel_agents:\s*)\d+/\${1}$maxa/" "$out"
  [ -n "$dojo" ] && perl -pi -e "s/^dojo:\s*\w+/dojo: $dojo/" "$out"
  rigor="$(grep -Eo '^rigor: *[a-z]+' <<<"$rev" | awk '{print $2}' || true)"
  [ -n "$rigor" ] && perl -pi -e "s/^rigor:\s*\w+/rigor: $rigor/" "$out"
  # rules
  rules="$(awk '/^# Rules/{on=1;next} /^# /{on=0} on && /^- /' "$p")"
  if [ -n "$rules" ]; then
    RULES="$rules" perl -0pi -e 's/(# Rules\n(?:<!--.*?-->\n)?(?:- [^\n]*\n)*)/$1$ENV{RULES}\n/s' "$out"
  fi
  # taste, per area
  for area in Code Prose UI Naming Testing; do
    entries="$(awk -v a="## $area" '$0==a{on=1;next} /^#/{on=0} on && /^- /' "$p" | sed "s/{{today}}/$today/g")"
    [ -n "$entries" ] || continue
    ENTRIES="$entries" AREA="$area" perl -0pi -e 's/(# Taste\n.*?## $ENV{AREA}\n)/$1$ENV{ENTRIES}\n/s' "$out"
  done
fi
echo "$out"
