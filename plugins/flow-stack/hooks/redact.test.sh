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
# becomes <line> <expected>: redact output is exactly expected
becomes() {
  local out; out="$(printf '%s\n' "$1" | redact)"
  if [ "$out" = "$2" ]; then ok "$1 → $out"; else bad "$1 → $out (want $2)"; fi
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
hides 'mysql -u root -p"my pass" db' 'pass'
hides "mysql -u root -p'my pass' db" 'pass'
hides 'mysqladmin -u root -pS3cr3t status' S3cr3t
hides 'mariadb-admin -u root -pS3cr3t status' S3cr3t
keeps 'psql -h db -p 5432 app'
keeps 'ssh -p 2222 host'
keeps 'find . -name "*.sh" -print'
# the -p rule fires only when mysql/mariadb is the command, never inside quoted SQL
keeps 'cat mysql-notes.txt -print'
keeps 'grep -r mysql src -print0'
keeps 'mysql -u root -e "SELECT a -price FROM t"'
becomes 'mysql -pS3cr3t -e "SELECT 1; SELECT a -price"' 'mysql -pREDACTED -e "SELECT 1; SELECT a -price"'
hides 'mysql -e "SELECT 1" -pS3cr3t' S3cr3t
hides 'mysqldump -pS3cr3t db' S3cr3t
hides 'sudo mysql -pS3cr3t' S3cr3t
hides 'env MYSQL_HOST=db mysql -pS3cr3t' S3cr3t
hides 'cd /srv && mysql -pS3cr3t' S3cr3t
hides 'cat dump.sql | mysql -u root -pS3cr3t db' S3cr3t
hides 'ls; /usr/bin/mysql -pS3cr3t' S3cr3t
hides 'cli --client-secret s3cr3tval run' s3cr3tval
hides 'cli --access-token abc12345xyz run' abc12345xyz
hides 'cli --private-key k3yvalue99 run' k3yvalue99
hides 'cli --private-key=k3yvalue99 run' k3yvalue99
keeps 'cli --access-token-file x'
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
