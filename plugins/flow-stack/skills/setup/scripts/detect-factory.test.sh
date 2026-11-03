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
want triage missing 'make-routines: triage'
want spec ok intent
want implement missing make-routines
want verify missing 'make-verifier.*feature-map'
want review missing make-routines
want ship missing 'auto-merge.md'
want factory missing
[ "$(grep -n '^routines ' <<<"$out" | cut -d: -f1)" -lt "$(grep -n '^FACTORY ' <<<"$out" | cut -d: -f1)" ] \
  && ok "factory rows come after every existing row" || bad "factory rows interleave existing rows"

# Existing rows print as before: main's detect.sh output == this one's minus the FACTORY section.
# In CI, actions/checkout checks out the PR merge commit (HEAD^1 is main). Elsewhere use the merge-base
# with origin/main (then main).
if [ -n "${GITHUB_ACTIONS:-}" ] && git -C "$here" rev-parse HEAD^2 >/dev/null 2>&1; then base="$(git -C "$here" rev-parse HEAD^1)"; else base="$(git -C "$here" merge-base HEAD origin/main 2>/dev/null || git -C "$here" merge-base HEAD main 2>/dev/null)"; fi
if [ -n "${base:-}" ] && old="$(git -C "$here" show "$base:./detect.sh" 2>/dev/null)" && [ -n "$old" ]; then
  mkdir -p "$SB/old/skills/setup/scripts" && ln -s "$here/../../../hooks" "$SB/old/hooks" && printf '%s\n' "$old" >"$SB/old/skills/setup/scripts/detect.sh"
  old_out="$(bash "$SB/old/skills/setup/scripts/detect.sh" 2>&1 | sed '/^FACTORY /,$d')"
  new_out="$("$D" 2>&1 | sed '/^FACTORY /,$d')"
  if [ "$old_out" = "$new_out" ]; then ok "existing rows unchanged vs main"
  else bad "existing rows changed vs main"; diff <(printf '%s\n' "$old_out") <(printf '%s\n' "$new_out") | sed 's/^/    /'; fi
else echo "  - skip: no main to compare against (shallow clone)"; fi

echo "-- driver and feature map on disk, not committed"
mkdir -p .claude/skills/verify-toy .flow/features .github/routines
printf -- '---\nid: a\nscenario: bash x.sh\n---\n' >.flow/features/a.md
out="$("$D")"
want verify missing 'make-verifier.*feature-map'
want factory missing

echo "-- a routine file that isn't committed doesn't run"
mkdir -p .github/workflows && touch .github/routines/self-heal.md .github/workflows/flow-self-heal.yml
out="$("$D")"
want implement missing make-routines
rm .github/routines/self-heal.md .github/workflows/flow-self-heal.yml

echo "-- a committed mention routine serves implement"
mkdir -p .github/workflows && touch .github/workflows/flow-mention.yml && git add .github/workflows/flow-mention.yml && git commit -qm mention
out="$("$D")"
want implement ok mention
git rm -q .github/workflows/flow-mention.yml && git commit -qm unmention

echo "-- committed driver + scenario, all routines"
touch .claude/skills/verify-toy/SKILL.md
mkdir -p .github/workflows
for r in self-create self-heal review auto-merge; do touch ".github/routines/$r.md" ".github/workflows/flow-$r.yml"; done
git add -A && git commit -qm init
out="$("$D")"
want monitor ok self-create
want implement ok self-heal
want verify ok 'committed verify driver'
want review ok review
want ship ok auto-merge
want factory ok

echo "-- a committed feature without a scenario does not count"
printf -- '---\nid: a\nscenario: # later\n---\n' >.flow/features/a.md && git commit -qam noscen
out="$("$D")"
want verify missing feature-map

echo "-- matches the gate: a quoted or body-only scenario doesn't count"
printf -- '---\nid: a\nscenario: ""\n---\nscenario: bash x.sh\n' >.flow/features/a.md && git commit -qam quoted
out="$("$D")"
want verify missing feature-map
want factory missing

echo "-- README is not a feature; a worktree is judged by its own commits"
printf -- '---\nscenario: bash x.sh\n---\n' >.flow/features/README.md && git add -A && git commit -qm readme
out="$("$D")"
want verify missing feature-map
git worktree add -q "$SB/wt" -b wt && cd "$SB/wt"
printf -- '---\nid: a\nscenario: bash x.sh\n---\n' >.flow/features/a.md && git commit -qam wt
out="$("$D")"
want verify ok 'committed verify driver'
want factory ok
[ "$FAILS" = 0 ] || { echo "$FAILS failed"; exit 1; }
echo "all passed"
