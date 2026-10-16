#!/usr/bin/env bash
# ecosystem.test.sh: nested manifests are listed relative to the root, whatever the root looks like
# (trailing slash, hidden directory name).
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/ecosystem.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
cd "$SB" || exit 1
mkdir -p e2/pkg .hid/sub
touch e2/go.mod e2/pkg/package.json .hid/package.json .hid/sub/package.json

nested() { "$H/ecosystem.sh" "$1" 2>/dev/null | grep '^nested' | awk '{print $2}' | tr '\n' ' '; }
check() { # <root> <want>
  local got; got="$(nested "$1")"
  if [ "$got" = "$2" ]; then ok "$1 → $got"; else bad "$1 → '$got', want '$2'"; fi
}
check e2/ "pkg/package.json "
check e2 "pkg/package.json "
check "$SB/.hid" "sub/package.json "

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL: $FAILS"; exit 1; }
