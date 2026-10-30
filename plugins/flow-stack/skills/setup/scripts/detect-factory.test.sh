#!/usr/bin/env bash
# detect-factory.test.sh: detect.sh's factory rows say which loop stages a repo has wired (#192).
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)/detect.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/detect-factory.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json" FLOW_STACK_HOME="$SB/home" HOME="$SB/hm"
mkdir -p "$SB/repo" "$SB/hm" && cd "$SB/repo" && git init -q && git config user.email t@t && git config user.name t
want() { local p="${3:-}"; grep -qE "^$1 +$2( |$).*$p" <<<"$out" && ok "$1 $2 $p" || bad "$1: want $2 /$p/, got: $(grep -E "^$1 " <<<"$out")"; }

echo "-- empty repo"
out="$("$D")"
want FACTORY STATUS
want monitor missing make-routines
want triage planned '#185'
want spec ok intent
want implement missing make-routines
want verify missing 'make-verifier.*feature-map'
want review missing make-routines
want ship missing '#184'
want factory-ready missing
[ "$(grep -n '^routines ' <<<"$out" | cut -d: -f1)" -lt "$(grep -n '^FACTORY ' <<<"$out" | cut -d: -f1)" ] \
  && ok "factory rows come after every existing row" || bad "factory rows interleave existing rows"

echo "-- driver and feature map on disk, not committed"
mkdir -p .claude/skills/verify-toy .flow/features .github/routines
printf -- '---\nid: a\nscenario: bash x.sh\n---\n' >.flow/features/a.md
out="$("$D")"
want verify missing 'commit .claude/skills/verify-toy.*commit .flow/features'
want factory-ready missing

echo "-- committed driver + scenario, all routines"
touch .claude/skills/verify-toy/SKILL.md
for r in self-create self-heal review auto-merge; do touch ".github/routines/$r.md"; done
git add -A && git commit -qm init
out="$("$D")"
want monitor ok self-create
want implement ok self-heal
want verify ok 'verify-toy.*1 feature'
want review ok review
want ship ok auto-merge
want factory-ready ok

echo "-- a committed feature without a scenario does not count"
printf -- '---\nid: a\nscenario: # later\n---\n' >.flow/features/a.md && git commit -qam noscen
out="$("$D")"
want verify missing feature-map
[ "$FAILS" = 0 ] || { echo "$FAILS failed"; exit 1; }
echo "all passed"
