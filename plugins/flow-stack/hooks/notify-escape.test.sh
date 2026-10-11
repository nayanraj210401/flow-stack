#!/usr/bin/env bash
# notify-escape.test.sh: with notify: osascript, the notification shows the message verbatim;
# a backslash before a quote can't end the AppleScript string and run the rest as script (#65).
# A stub osascript swaps "display notification X with title Y" for "return X" and runs the real
# one, so nothing pops up and the test sees the text the notification would show. macOS only.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
command -v osascript >/dev/null || { echo "== notify-escape · SKIP (no osascript)"; exit 0; }
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/notify-escape.XXXXXX")"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" OUT="$SB/out" REAL="$(command -v osascript)"
mkdir -p "$FLOW_STACK_HOME" "$SB/bin"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID
printf -- '---\nnotify: osascript\n---\n' >"$FLOW_STACK_HOME/profile.md"
cat >"$SB/bin/osascript" <<'EOF'
#!/usr/bin/env bash
args=()
for a in "$@"; do args+=("$(sed -E 's/display notification (.*) with title .*/return \1/' <<<"$a")"); done
"$REAL" "${args[@]}" >"$OUT" 2>&1
EOF
chmod +x "$SB/bin/osascript"

shown() { rm -f "$OUT"; PATH="$SB/bin:$PATH" "$H/notify.sh" "$1"; cat "$OUT" 2>/dev/null; }
expect() { local got; got="$(shown "$1")"; [ "$got" = "$1" ] && ok "verbatim: $1" || bad "$1 → shown as: $got"; }

expect 'Claude needs you'
expect 'say "hi"'
expect 'x\" & (ASCII character 33) --'
expect 'trailing \'

[ "$FAILS" -eq 0 ] && { echo "== notify-escape · PASS"; exit 0; }
echo "== notify-escape · FAIL ($FAILS)"; exit 1
