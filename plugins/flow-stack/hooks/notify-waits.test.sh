#!/usr/bin/env bash
# notify-waits.test.sh: notify.sh logs permission waits to waits.jsonl, even with notify: off.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
SB="$(mktemp -d "${TMPDIR:-/tmp}/notify-waits.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" HOME="$SB/hm"; mkdir -p "$HOME" "$FLOW_STACK_HOME"
printf -- '---\nnotify: off\n---\n' >"$FLOW_STACK_HOME/profile.md"
W="$FLOW_STACK_HOME/waits.jsonl"; fail=0
send() { printf '%s' "$1" | bash "$H/notify.sh"; }
send '{"notification_type":"permission_prompt","session_id":"s1","message":"m"}'; rc1=$?
send '{"notification_type":"elicitation_dialog","session_id":"s2"}'
send '{"notification_type":"idle_prompt","session_id":"s3"}'
bash "$H/notify.sh" "Stop msg" </dev/null
[ "$(wc -l <"$W" 2>/dev/null | tr -d ' ')" = 2 ] || { echo "  ✗ want 2 lines, got: $(cat "$W" 2>/dev/null)"; fail=1; }
l1="$(sed -n 1p "$W" 2>/dev/null)"
jq -e '.sid=="s1" and .kind=="permission_prompt" and (.ts|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$"))' <<<"$l1" >/dev/null 2>&1 || { echo "  ✗ bad line 1: $l1"; fail=1; }
jq -e '.sid=="s2" and .kind=="elicitation_dialog"' <<<"$(sed -n 2p "$W" 2>/dev/null)" >/dev/null 2>&1 || { echo "  ✗ bad line 2"; fail=1; }
[ "$rc1" = 0 ] || { echo "  ✗ exit $rc1"; fail=1; }
rm -rf "$W"; mkdir "$W"   # unwritable target: must fail open
send '{"notification_type":"permission_prompt","session_id":"s4"}'; rc=$?
[ "$rc" = 0 ] || { echo "  ✗ failed write changed exit to $rc"; fail=1; }
[ "$fail" = 0 ] && { echo "  ✓ waits logged, idle/Stop skipped, fail open"; echo PASS; } || exit 1
