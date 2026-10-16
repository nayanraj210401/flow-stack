#!/usr/bin/env bash
# collect-quality.test.sh: quality counts include tracked files whose names are not ASCII.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
SB="$(mktemp -d "${TMPDIR:-/tmp}/collect-quality.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"; trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" HOME="$SB/hm"; mkdir -p "$HOME" "$FLOW_STACK_HOME" "$SB/r/tests"
cd "$SB/r" && git init -q && git config user.email t@e.x && git config user.name t
printf 'a() { :; }\n' >a.sh; printf '# TODO x\n' >'é.sh'; printf 'ok\n' >'tests/t_ü.sh'
git add -A && git commit -qm init
out="$("$H/collect.sh" --no-cost --no-prs "$SB/r" 2>/dev/null | jq -r '.repos[0].quality.dims[]|select(.id=="tests" or .id=="markers")|.detail' 2>/dev/null)"
want="1 test files for 2 source files
1 TODO/FIXME/HACK/XXX in 3 lines"
if [ "$out" = "$want" ]; then echo "  ✓ non-ASCII files counted"; echo PASS
else echo "  ✗ quality: want [$want] got [$out]"; exit 1; fi
