#!/usr/bin/env bash
# settings.test.sh: ~/.flow-stack/settings.json turns default hooks on and off, below the repo's
# .flow/config.json and above the older global config.json; settings.sh reads and writes the layers.
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
H="$D/../../../hooks"
S="$D/settings.sh"
FAILS=0
ok()  { :; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/settings-test.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR" "$SB/repo/.flow"
cd "$SB/repo" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

# enabled <hook>: what a hook sees (lib.sh's flow_enabled), in this repo
enabled() { ( . "$H/lib.sh"; flow_roots "$SB/repo"; flow_enabled "$1" ) && echo on || echo off; }
# the guard hook, as Claude Code runs it, on a command it always asks about
guard_says() {
  jq -nc --arg cwd "$SB/repo" '{cwd:$cwd, hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:"git push --force origin main"}}' \
    | "$H/guard.sh" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null | grep . || echo allow
}

[ "$(enabled claims)" = on ] && ok || bad "no settings → claims on"
[ "$(guard_says)" != allow ] || bad "guard: force push to main should not be allowed by default"

out="$("$S" hook claims off)"; grep -q 'claims: off (settings.json)' <<<"$out" || bad "hook claims off: $out"
[ "$(jq -r .hooks.claims "$FLOW_STACK_HOME/settings.json")" = false ] || bad "settings.json not written: $(cat "$FLOW_STACK_HOME/settings.json")"
[ "$(enabled claims)" = off ] || bad "settings.json claims false → hook sees off"

"$S" hook guard off >/dev/null
[ "$(guard_says)" = allow ] || bad "settings.json guard false → guard.sh stays quiet"
"$S" hook guard default >/dev/null
[ "$(guard_says)" != allow ] || bad "hook guard default → guard back on"
jq -e '.hooks | has("guard") | not' "$FLOW_STACK_HOME/settings.json" >/dev/null || bad "default should drop the key"

# precedence: repo config.json > settings.json > legacy config.json
echo '{"hooks":{"trail":false,"fence":false}}' >"$FLOW_STACK_HOME/config.json"
[ "$(enabled trail)" = off ] || bad "legacy config.json still honored"
"$S" hook trail on >/dev/null
[ "$(enabled trail)" = on ] || bad "settings.json beats legacy config.json"
echo '{"hooks":{"trail":false}}' >.flow/config.json
[ "$(enabled trail)" = off ] || bad "repo .flow/config.json beats settings.json"
out="$("$S" hook trail on)"; grep -q 'wins here' <<<"$out" || bad "a shadowed global write should say the repo wins: $out"
"$S" hook trail on --repo >/dev/null
[ "$(enabled trail)" = on ] || bad "--repo writes .flow/config.json"
show="$("$S" show)"
grep -Eq '^  trail +on +repo .flow/config.json' <<<"$show" || bad "show: trail on from repo: $show"
grep -Eq '^  fence +off +config.json \(global\)' <<<"$show" || bad "show: fence off from legacy: $show"
grep -Eq '^  claims +off +settings.json' <<<"$show" || bad "show: claims off from settings.json"
grep -Eq '^  anchor +on +default' <<<"$show" || bad "show: anchor default on"

# unknown names are refused; 'evidence' points at claims
out="$("$S" hook evidence off 2>&1)" && bad "unknown hook accepted"
grep -q "'claims'" <<<"$out" || bad "unknown hook message names claims: $out"
"$S" hook claims maybe >/dev/null 2>&1 && bad "bad value accepted"

# tests settings
"$S" tests scope full >/dev/null || bad "tests scope full"
[ "$(jq -r .tests.scope "$FLOW_STACK_HOME/settings.json")" = full ] || bad "tests.scope not written"
"$S" tests scope sometimes >/dev/null 2>&1 && bad "bad scope accepted"
grep -Eq '^  scope +full +settings.json' <<<"$("$S" show)" || bad "show: scope full"

# init carries legacy toggles over, and never overwrites
rm -f "$FLOW_STACK_HOME/settings.json"
"$S" init >/dev/null
[ "$(jq -r .hooks.fence "$FLOW_STACK_HOME/settings.json")" = false ] || bad "init carries over legacy hooks"
[ "$(jq -r .tests.scope "$FLOW_STACK_HOME/settings.json")" = impacted ] || bad "init sets scope impacted"
"$S" hook fence on >/dev/null; "$S" init >/dev/null
[ "$(jq -r .hooks.fence "$FLOW_STACK_HOME/settings.json")" = true ] || bad "init must not overwrite"

# invalid JSON is never clobbered, and a hook reading it fails open (on)
echo '{nope' >"$FLOW_STACK_HOME/settings.json"
"$S" hook claims off >/dev/null 2>&1 && bad "wrote over invalid JSON"
[ "$(cat "$FLOW_STACK_HOME/settings.json")" = '{nope' ] || bad "invalid settings.json changed"
rm -f "$FLOW_STACK_HOME/config.json" .flow/config.json
[ "$(enabled claims)" = on ] || bad "invalid settings.json → default on"

# every name a hook checks is in the catalog, so show lists every toggle there is
cat_names="$(sed -n '/^catalog()/,/^}/p' "$S" | awk -F'\t' 'NF > 1 { print $1 }' | sort -u)"
hook_names="$(grep -ho 'flow_enabled [a-z-]*' "$H"/*.sh | awk '{ print $2 }' | sort -u)"
[ "$(grep -c . <<<"$hook_names")" -ge 10 ] || bad "found only $(grep -c . <<<"$hook_names") flow_enabled names in $H"
for n in $hook_names; do
  grep -qx "$n" <<<"$cat_names" || bad "hook name '$n' is missing from settings.sh's catalog"
done

# a symlinked settings.json (dotfiles repo) stays a symlink
rm -f "$FLOW_STACK_HOME/settings.json"; echo '{}' >"$FLOW_STACK_HOME/real.json"; ln -s real.json "$FLOW_STACK_HOME/settings.json"
"$S" hook claims off >/dev/null 2>&1
[ -L "$FLOW_STACK_HOME/settings.json" ] && [ "$(jq -r .hooks.claims "$FLOW_STACK_HOME/real.json")" = false ] || bad "write replaced the settings.json symlink"

[ "$FAILS" -eq 0 ] && echo "settings.test: ok" || { echo "settings.test: $FAILS failed"; exit 1; }
