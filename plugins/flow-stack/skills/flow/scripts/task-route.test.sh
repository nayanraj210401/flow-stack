#!/usr/bin/env bash
# task-route.test.sh: `route "<request>"` picks one repo, a workspace, or asks one question (#190).
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd)/task.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/task-route.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions"
for r in api web docs; do
  mkdir -p "$SB/$r" && git -C "$SB/$r" init -q && git -C "$SB/$r" -c user.email=a@b -c user.name=a commit -q --allow-empty -m i
done
mkdir -p "$SB/web/.flow/features"
printf -- '---\nid: billing.invoice\ntitle: Billing\nowns: src/invoices/** src/export.ts\n---\n' >"$SB/web/.flow/features/billing.invoice.md"
cat >"$FLOW_STACK_HOME/profile.md" <<EOF
# Repos
## api
- path: $SB/api
- role: dep
- what: HTTP API server for customers, auth and rate limiting

## web
- path: $SB/web
- role: primary
- what: React dashboard for customers

## docs
- path: $SB/docs
- what: documentation site

# Workspaces
## wide
- repos: web, api, admin

## shop
- repos: api, web
EOF
cd "$SB/api"
route() { "$T" route "$1" 2>&1 | head -n1; }

[ "$(route "add rate limits to login")" = "repo	api	$SB/api" ] && ok "a what: match routes to that repo" || bad "rate limits: $(route "add rate limits to login")"
[ "$(route "fix the invoice export")" = "repo	web	$SB/web" ] && ok "a feature map owns: match routes to its repo" || bad "invoice: $(route "fix the invoice export")"
[ "$(route "show rate limits on the dashboard")" = "workspace	shop" ] && ok "a match across a workspace's repos routes to the smallest workspace holding them" || bad "workspace: $(route "show rate limits on the dashboard")"
out="$(route "documentation for the dashboard")"
case "$out" in *api*) bad "ambiguous lists an unmatched repo: $out" ;; ask*web*docs*) ok "repos in no shared workspace: one question naming them" ;; *) bad "ambiguous: $out" ;; esac
out="$(route "email customers")"
case "$out" in ask*api*web*docs*) ok "a word two repos share decides nothing" ;; *) bad "shared word: $out" ;; esac
out="$(route "tidy things up")"
case "$out" in ask*api*web*docs*) ok "no match: one question listing every repo" ;; *) bad "no match: $out" ;; esac
[ "$("$T" route "tidy things up" | wc -l | tr -d ' ')" = 1 ] && ok "the question is a single line" || bad "question spans lines"
"$T" route "add rate limits" >/dev/null
[ ! -e "$SB/api/.flow" ] && ok "routing creates no task" || bad "route touched $SB/api/.flow"
[ "$FAILS" = 0 ] || { echo "$FAILS failed"; exit 1; }
echo "all passed"
