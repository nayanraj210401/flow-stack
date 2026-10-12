#!/usr/bin/env bash
# scan-repos.sh ignores npm's placeholder test script (#52).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
for n in ph real; do mkdir -p "$t/$n"; git -C "$t/$n" init -q; done
echo '{"scripts":{"test":"echo \"Error: no test specified\" && exit 1"}}' >"$t/ph/package.json"
echo '{"scripts":{"test":"jest"}}' >"$t/real/package.json"
out="$("$here/scan-repos.sh" "$t")"
grep -P "/ph\tnode\t-\t" <<<"$out" >/dev/null || { echo "FAIL: placeholder reported as a test"; echo "$out"; exit 1; }
grep -P "/real\tnode\tnpm test\t" <<<"$out" >/dev/null || { echo "FAIL: real test script lost"; echo "$out"; exit 1; }
echo ok
