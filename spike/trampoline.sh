#!/usr/bin/env bash
# Spike #194: run flow-stack's guard from a pinned clone, from a committed hook.
sha=6ade0f4b2a5b21dea459ca62125558a3d0603f40
d="${TMPDIR:-/tmp}/flow-stack@$sha"
mkdir -p /tmp/spike; log=/tmp/spike/hook.log
in="$(cat)"
if [ ! -d "$d/.git" ]; then
  git clone -q https://github.com/nayanraj210401/flow-stack "$d" >>"$log" 2>&1 && git -C "$d" checkout -q "$sha" >>"$log" 2>&1
fi
home="$(mktemp -d)"
out="$(printf '%s' "$in" | FLOW_STACK_HOME="$home" bash "$d/plugins/flow-stack/hooks/guard.sh" 2>>"$log")"; rc=$?
{ echo "--- $(date -u +%FT%TZ) rc=$rc env FLOW_STACK_HOME(seen by hook)=${FLOW_STACK_HOME:-<unset>}"
  printf '%s\n' "$in" | head -c 400; echo; echo "guard out: $out"; } >>"$log"
printf '%s' "$out"; exit $rc
