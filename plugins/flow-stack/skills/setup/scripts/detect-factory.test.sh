#!/usr/bin/env bash
# detect-factory.test.sh: detect.sh's factory rows say which loop stages a repo has wired (#192).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; D="$here/detect.sh"
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
want factory missing
[ "$(grep -n '^routines ' <<<"$out" | cut -d: -f1)" -lt "$(grep -n '^FACTORY ' <<<"$out" | cut -d: -f1)" ] \
  && ok "factory rows come after every existing row" || bad "factory rows interleave existing rows"

# Existing rows print as before: main's detect.sh output == this one's minus the FACTORY section.
if old="$(git -C "$here" show "$(git -C "$here" merge-base HEAD origin/main 2>/dev/null || git -C "$here" merge-base HEAD main 2>/dev/null):./detect.sh" 2>/dev/null)" && [ -n "$old" ]; then
  mkdir -p "$SB/old/skills/setup/scripts" && ln -s "$here/../../../hooks" "$SB/old/hooks" && printf '%s\n' "$old" >"$SB/old/skills/setup/scripts/detect.sh"
  [ "$(bash "$SB/old/skills/setup/scripts/detect.sh" 2>&1)" = "$(sed '/^FACTORY /,$d' <<<"$out")" ] && ok "existing rows unchanged vs main" || bad "existing rows changed vs main"
else echo "  - skip: no main to compare against (shallow clone)"; fi

echo "-- driver and feature map on disk, not committed"
mkdir -p .claude/skills/verify-toy .flow/features .github/routines
printf -- '---\nid: a\nscenario: bash x.sh\n---\n' >.flow/features/a.md
out="$("$D")"
want verify missing 'commit .claude/skills/verify-toy.*commit .flow/features'
want factory missing

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
want factory ok

echo "-- a committed feature without a scenario does not count"
printf -- '---\nid: a\nscenario: # later\n---\n' >.flow/features/a.md && git commit -qam noscen
out="$("$D")"
want verify missing feature-map

echo "-- README is not a feature; a worktree is judged by its own commits"
printf -- '---\nscenario: bash x.sh\n---\n' >.flow/features/README.md && git add -A && git commit -qm readme
out="$("$D")"
want verify missing feature-map
git worktree add -q "$SB/wt" -b wt && cd "$SB/wt"
printf -- '---\nid: a\nscenario: bash x.sh\n---\n' >.flow/features/a.md && git commit -qam wt
out="$("$D")"
want verify ok 'verify-toy.*1 feature'
want factory ok
[ "$FAILS" = 0 ] || { echo "$FAILS failed"; exit 1; }
echo "all passed"
