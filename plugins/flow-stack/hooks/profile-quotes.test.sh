#!/usr/bin/env bash
# profile-quotes.test.sh: profile_fm strips one pair of matching quotes, so `rigor: "strict"` means strict
# instead of a value no hook recognises. Unmatched or inner quotes stay as written.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
PASSES=0
ok()  { PASSES=$((PASSES + 1)); }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/profile-quotes.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB"
printf -- '---\nrigor: "strict"\nreview_gate: '"'"'yolo'"'"'   # comment\nnotify_on: "all\nname: a "b" c\n---\n' >"$SB/profile.md"
. "$H/lib.sh"
is() { local got; got="$(profile_fm "$1")"; [ "$got" = "$2" ] && ok "$1 → $2" || bad "$1 → [$got], want [$2]"; }
is rigor strict
is review_gate yolo
is notify_on '"all'
is name 'a "b" c'
[ "$FAILS" -eq 0 ] && echo "== profile-quotes · PASS ($PASSES passed)" || { echo "== profile-quotes · FAIL ($FAILS)"; exit 1; }
