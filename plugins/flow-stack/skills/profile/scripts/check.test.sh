#!/usr/bin/env bash
# check.test.sh: check.sh validates frontmatter values against the template's table (#193).
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/profile-check.XXXXXX")"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB"
P="$SB/profile.md"
run() { out="$("$D/check.sh" 2>&1)"; rc=$?; }
set_fm() { perl -pi -e "s/^$1:.*/$1: $2/" "$P"; }

"$D/init.sh" solo-hacker >/dev/null
run
[ "$rc" = 0 ] && ! grep -q 'unknown profile key\|✗ [a-z_]*: ' <<<"$out" && ok "a fresh profile passes with no warnings" || bad "fresh profile: rc=$rc $out"

set_fm rigor fast; run
[ "$rc" != 0 ] && grep -q '✗ rigor: fast.*lean | standard | strict' <<<"$out" && ok "rigor: fast fails with the valid list" || bad "rigor: fast: rc=$rc $out"
set_fm rigor strict

set_fm review_gate off; run
[ "$rc" != 0 ] && grep -q '✗ review_gate: off.*on | yolo' <<<"$out" && ok "review_gate: off fails" || bad "review_gate: off: rc=$rc $out"
set_fm review_gate yolo

set_fm notify ntfy:my-topic; set_fm dojo light; run
[ "$rc" = 0 ] && ok "notify: ntfy:<topic> and dojo: light pass" || bad "ntfy/dojo: rc=$rc $out"
set_fm notify ntfy:; run
[ "$rc" != 0 ] && grep -q '✗ notify: ntfy:' <<<"$out" && ok "notify: ntfy: without a topic fails" || bad "empty topic: rc=$rc $out"
set_fm notify off

perl -pi -e 's/^(digest|notify_on):.*\n//' "$P"
perl -pi -e 's/^(rigor:.*)/$1\nfuture_key: x/' "$P"; run
[ "$rc" = 0 ] && grep -q '? unknown profile key: future_key' <<<"$out" && ok "missing keys pass; an unknown key warns, not fails" || bad "missing/unknown: rc=$rc $out"

perl -pi -e 's/^(  build_model:).*/$1 gpt/' "$P"; run
[ "$rc" = 0 ] && ok "keys with no value list in the template stay free-form" || bad "free-form: rc=$rc $out"

[ "$FAILS" = 0 ] || { echo "== profile-check · FAIL ($FAILS)"; exit 1; }
echo "== profile-check · PASS"
