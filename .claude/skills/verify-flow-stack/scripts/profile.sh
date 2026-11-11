#!/usr/bin/env bash
# profile: init.sh writes ~/.flow-stack/profile.md from a preset (never clobbering
# silently); check.sh lints its structure.
. "$(dirname "$0")/lib.sh"; sandbox profile
I="$S/profile/scripts/init.sh"; C="$S/profile/scripts/check.sh"; P="$FLOW_STACK_HOME/profile.md"

sees "check with no profile says so" "no profile at" "$C"
fails "unknown preset refused" "$I" nope
for pre in senior-backend frontend-product data-ml learning-mode solo-hacker none; do
  rm -f "$P"
  if "$I" "$pre" >/dev/null 2>&1 && grep -q "^preset: $pre" "$P" && "$C" >/dev/null 2>&1; then ok "preset $pre → valid profile"
  else bad "preset $pre: $("$C" 2>&1 | tail -n 3)"; fi
done
"$I" solo-hacker --force >/dev/null
grep -qE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} · .+ · src: ' "$P" && ok "preset taste entries dated + sourced" || bad "no dated taste"
[ "$(awk '/^# Rules/{on=1;next} /^# /{on=0} on && /^- /' "$P" | wc -l | tr -d ' ')" -ge 2 ] && ok "preset rules merged" || bad "rules not merged"
fails "refuses to overwrite" "$I" solo-hacker
check "--force overwrites" "$I" none --force
ls "$P".bak.* >/dev/null 2>&1 && ok "backup kept" || bad "no backup"
echo "-- check catches problems"
perl -0pi -e 's/(# Rules\n(?:<!--.*?-->\n)?)(?:- [^\n]*\n)+/$1/s' "$P"
sees "empty Rules flagged" "Rules is empty" "$C"
fails "check exits non-zero" "$C"
"$I" none --force >/dev/null
perl -0pi -e 's/## Code\n/## Code\n- prefer tabs\n/' "$P"
sees "malformed taste flagged" "taste entry not in" "$C"
cp "$P" "$ART/profile.md"
finish
