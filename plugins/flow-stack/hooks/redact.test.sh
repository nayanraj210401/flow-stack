#!/usr/bin/env bash
# redact.test.sh: lib.sh redact() masks Basic auth, URL userinfo, `curl -u`, github_pat_ tokens and
# quoted values with spaces, and leaves ordinary text alone.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/redact.XXXXXX")"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
# shellcheck source=/dev/null
. "$H/lib.sh"

# hides <line> <secret>: the secret must not survive redact
hides() {
  local out; out="$(printf '%s\n' "$1" | redact)"
  case "$out" in *"$2"*) bad "leaked '$2': $out" ;; *) ok "$1 → $out" ;; esac
}
# keeps <line>: redact leaves it unchanged
keeps() {
  local out; out="$(printf '%s\n' "$1" | redact)"
  if [ "$out" = "$1" ]; then ok "unchanged: $1"; else bad "changed: $1 → $out"; fi
}

hides 'docker login -u me --password hunter2' hunter2
hides 'cli --token abc12345xyz run' abc12345xyz
hides 'cli --api-key "my secret value" run' 'secret value'
hides 'mysql -u root -phunter2 db' hunter2
keeps 'cli --password --verbose'
keeps 'mysql -u root -p db'
keeps 'grep --token-file x'
hides 'curl -H "Authorization: Basic dXNlcjpwYXNz" x' dXNlcjpwYXNz
hides 'psql postgres://u:p4ssw0rd@host/db' p4ssw0rd
hides 'curl -u admin:pass1234 http://x' pass1234
hides 'curl --user admin:pass1234 http://x' pass1234
hides 'github_pat_11ABCDEFG0123456789_abcdefghijklmnop' 11ABCDEFG0123456789
hides 'password: "my secret pw"' 'secret pw'
hides "token='two words'" 'words'
hides 'export API_KEY=abc123def' abc123def
hides 'Authorization: Bearer abcdefgh12345' abcdefgh12345
hides 'password: "my secret' secret
hides 'export PASSWORD="abc def' abc
hides 'psql postgres://u:p@ss@host/db' '@ss@'
hides 'curl -uadmin:pass1234 http://x' pass1234
keeps 'git clone https://github.com/a/b.git'
keeps 'ssh git@github.com'
keeps 'ls -u foo'
keeps 'git commit -m "Add basic validation for users"'
keeps 'docker run -u 1000:1000 img'

[ "$FAILS" -eq 0 ] && echo "PASS" || { echo "FAIL: $FAILS"; exit 1; }
