#!/usr/bin/env bash
# some.sh [<feature>...]: run these scenarios (none = every one); print PASS/FAIL each with its failed
# assertions. Exit 1 on any FAIL.
here="$(cd "$(dirname "$0")" && pwd)"; rc=0
if [ $# -eq 0 ]; then
  for f in "$here"/*.sh; do f="$(basename "$f" .sh)"; case "$f" in lib|up|down|some) ;; *) set -- "$@" "$f" ;; esac; done
fi
for f in "$@"; do
  out="$(bash "$here/$f.sh" 2>&1)"
  if [ $? -eq 0 ]; then echo "$f: PASS"; else echo "$f: FAIL"; grep "✗" <<<"$out" | head -8; rc=1; fi
done
exit $rc
