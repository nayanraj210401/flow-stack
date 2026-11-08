#!/usr/bin/env bash
# scripts.quiet: a passing *.test.sh prints one short summary line and exits 0; a failing one shows
# its ✗ lines and exits non-zero. Driven on redact.test.sh, then on a copy whose redact() is broken.
. "$(dirname "$0")/lib.sh"; sandbox scripts.quiet
H="$PWD/plugins/flow-stack/hooks"; [ -d "$H" ] || H="$S/../hooks"

rc=0; out="$(bash "$H/redact.test.sh" 2>&1)" || rc=$?
[ "$rc" = 0 ] && ok "passing suite exits 0" || bad "passing suite exit $rc: $out"
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -le 3 ] && ok "passing suite prints ≤ 3 lines" || bad "too chatty: $out"
grep -qE '^redact: [0-9]+ passed$' <<<"$out" && ok "summary is '<suite>: N passed'" || bad "summary line: $out"

cp -R "$H" "$SB/hooks"; printf '\nredact() { cat; }\n' >>"$SB/hooks/lib.sh"
rc=0; out="$(bash "$SB/hooks/redact.test.sh" 2>&1)" || rc=$?
[ "$rc" != 0 ] && ok "broken suite exits non-zero" || bad "broken suite still exits 0: $out"
grep -q '✗' <<<"$out" && ok "broken suite shows its ✗ lines" || bad "no ✗ line on failure: $out"
finish
