#!/usr/bin/env bash
# suites.test.sh: suites.sh runs only the sub-suites a change touches, falls back to the full
# suite when a change is unclaimed or scope is full, and records each run through evidence.sh.
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
S="$D/suites.sh"
FAILS=0
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/suites-test.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR"
R="$SB/repo"; mkdir -p "$R" && cd "$R"
git init -q; git config user.email t@t; git config user.name t
mkdir -p src/auth src/billing src/shared tests/auth tests/billing docs .flow
for f in src/auth/login.sh src/billing/pay.sh src/shared/util.sh tests/auth/t.sh tests/billing/t.sh docs/guide.txt; do echo "# $f" >"$f"; done
# each suite leaves a mark, so the test can see which ran
jq -n --arg m "$SB/ran" '{
  commands: {test: ("echo full >>" + $m)},
  tests: {
    suites: [
      {id: "auth", paths: ["src/auth/**", "tests/auth/**"], run: ("echo auth >>" + $m)},
      {id: "billing", paths: ["src/billing/**", "tests/billing/**"], run: ("echo billing >>" + $m)}
    ],
    ignore: ["docs/**"]
  }
}' >.flow/config.json
git add -A && git commit -qm init
ran() { sort -u "$SB/ran" 2>/dev/null | tr '\n' ' '; }
go() { rm -f "$SB/ran"; out="$("$S" run "$@" 2>&1)"; rc=$?; }

go; [ "$rc" = 0 ] && [ -z "$(ran)" ] || bad "clean tree → nothing runs (ran: $(ran); $out)"

echo x >>src/auth/login.sh
go; [ "$(ran)" = "auth " ] || bad "auth change → only auth (ran: $(ran); $out)"
grep -q 'src/auth/login.sh → auth' <<<"$out" || bad "says why auth ran: $out"
grep -q 'flow-evidence: PASS' <<<"$out" || bad "runs go through evidence.sh: $out"

echo x >>tests/billing/t.sh
go; [ "$(ran)" = "auth billing " ] || bad "auth + billing changes → both, once each (ran: $(ran))"
[ "$(grep -c . "$SB/ran")" = 2 ] || bad "each suite runs once: $(cat "$SB/ran")"
git checkout -q -- .

echo x >>docs/guide.txt; echo x >>README.md
go; [ -z "$(ran)" ] || bad "ignored + *.md changes → nothing runs (ran: $(ran))"
git checkout -q -- . 2>/dev/null; rm -f README.md

echo x >>src/shared/util.sh
go; [ "$(ran)" = "full " ] || bad "unclaimed file → full suite (ran: $(ran); $out)"
grep -q 'no suite claims src/shared/util.sh' <<<"$out" || bad "names the unclaimed file: $out"
echo '{"tests":{"unmatched":"skip"}}' >"$FLOW_STACK_HOME/settings.json"
go; [ -z "$(ran)" ] || bad "unmatched skip (settings.json) → nothing (ran: $(ran))"
git checkout -q -- .

echo x >>src/billing/pay.sh
echo '{"tests":{"scope":"full"}}' >"$FLOW_STACK_HOME/settings.json"
go; [ "$(ran)" = "full " ] || bad "settings.json scope full → full suite (ran: $(ran))"
jq '.tests.scope = "impacted"' .flow/config.json >c && mv c .flow/config.json && git commit -qm scope .flow/config.json
go; [ "$(ran)" = "billing " ] || bad "repo scope impacted beats settings.json full (ran: $(ran))"
rm -f "$FLOW_STACK_HOME/settings.json"
go --all; [ "$(ran)" = "full " ] || bad "--all → full suite (ran: $(ran))"
git checkout -q -- .

# --base: everything since a ref, committed or not
b="$(git rev-parse HEAD)"; echo x >>src/auth/login.sh; git commit -qam auth
go; [ -z "$(ran)" ] || bad "committed change, no --base → nothing (ran: $(ran))"
go --base "$b"; [ "$(ran)" = "auth " ] || bad "--base → the committed auth change (ran: $(ran))"
# explicit paths replace the diff
go src/billing/pay.sh; [ "$(ran)" = "billing " ] || bad "explicit path → billing (ran: $(ran))"

# edge cases that used to skip a suite silently (unmatched skip makes a miss visible)
c0="$(git rev-parse HEAD)"
echo '{"tests":{"unmatched":"skip"}}' >"$FLOW_STACK_HOME/settings.json"
go --base no-such-ref; [ "$(ran)" = "full " ] || bad "a bad --base → full suite, not nothing (ran: $(ran); $out)"
echo x >"src/auth/é.sh"
go; [ "$(ran)" = "auth " ] || bad "untracked non-ASCII path → auth (ran: $(ran); $out)"
git add -A && git commit -qm e
go --base "$c0"; [ "$(ran)" = "auth " ] || bad "committed non-ASCII path → auth (ran: $(ran); $out)"
c1="$(git rev-parse HEAD)"; git mv src/billing/pay.sh src/shared/pay.sh && git commit -qm mv
go --base "$c1"; [ "$(ran)" = "billing " ] || bad "file moved out of billing → billing (ran: $(ran); $out)"
jq --arg m "$SB/ran" '.tests.suites += [{id: "docs", paths: ["docs/**/*.md"], run: ("echo docs >>" + $m)}]' .flow/config.json >c && mv c .flow/config.json
git commit -qam docs-suite; c2="$(git rev-parse HEAD)"
echo x >docs/new.md
go; [ "$(ran)" = "docs " ] || bad "a suite claiming *.md beats the built-in ignore (ran: $(ran); $out)"
rm docs/new.md
jq '.tests.ignore += ["x/**"]' .flow/config.json >c && mv c .flow/config.json
go; [ "$(ran)" = "full " ] || bad ".flow/config.json change → full suite, even with unmatched skip (ran: $(ran); $out)"
rm -f "$FLOW_STACK_HOME/settings.json"
jq '.tests.unmatched = "ful"' .flow/config.json >c && mv c .flow/config.json
grep -q "tests.unmatched 'ful'" <<<"$("$S" check 2>&1)" || bad "check flags tests.unmatched 'ful'"
echo x >>src/shared/util.sh
go; [ "$(ran)" = "full " ] || bad "an unknown tests.unmatched acts as full (ran: $(ran))"
git reset -q --hard "$c0"; git clean -qfd

# a failing suite fails the run and records FAIL
jq --arg m "$SB/ran" '.tests.suites[1].run = "echo billing >>" + $m + "; exit 3"' .flow/config.json >c && mv c .flow/config.json
go src/billing/pay.sh src/auth/login.sh
[ "$rc" != 0 ] && [ "$(ran)" = "auth billing " ] || bad "a failing suite → non-zero, the others still run (rc=$rc ran: $(ran))"
grep -q 'flow-evidence: FAIL' <<<"$out" || bad "failure recorded: $out"

# pick prints id<TAB>command; no commands.test → full means every suite
p="$("$S" pick src/auth/login.sh 2>/dev/null)"
[ "$(cut -f1 <<<"$p")" = auth ] && grep -q 'echo auth' <<<"$p" || bad "pick: $p"
jq 'del(.commands.test)' .flow/config.json >c && mv c .flow/config.json
p="$("$S" pick src/shared/util.sh 2>/dev/null | cut -f1 | tr '\n' ' ')"
[ "$p" = "auth billing " ] || bad "no commands.test: full suite = every suite (got $p)"

# no suites declared: the full suite, as before
jq -n --arg m "$SB/ran" '{commands: {test: ("echo full >>" + $m)}}' >.flow/config.json
go src/auth/login.sh; [ "$(ran)" = "full " ] || bad "no suites → full suite (ran: $(ran))"

# check lints ids, commands, dead globs
jq -n '{tests: {suites: [{id: "a b", paths: ["src/**"], run: "x"}, {id: "ok", paths: ["nope/**"], run: "x"}, {id: "ok", paths: ["src/**"]}]}}' >.flow/config.json
out="$("$S" check 2>&1)" && bad "check passed bad suites"
grep -q "id 'a b'" <<<"$out" && grep -q "'nope/\*\*' matches no tracked file" <<<"$out" && grep -q 'declared twice' <<<"$out" && grep -q 'no run command' <<<"$out" \
  || bad "check: $out"
jq -n '{tests: {suites: [{id: "auth", paths: ["src/auth/**"], run: "x"}]}}' >.flow/config.json
"$S" check >/dev/null 2>&1 || bad "check: a good suite passes"

[ "$FAILS" -eq 0 ] && echo "suites.test: ok" || { echo "suites.test: $FAILS failed"; exit 1; }
