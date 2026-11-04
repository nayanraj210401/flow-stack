#!/usr/bin/env bash
# pkgcheck-args.test.sh: the package-existence check looks at package names only, not redirects,
# requirement files or archives (#62). A stub curl knows only left-pad and @scope/pkg; any other name is a 404.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/pkgcheck.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo" "$SB/bin"
cat >"$SB/bin/curl" <<'S'
#!/usr/bin/env bash
case "$*" in */left-pad*|*/%2Fpkg*|*/@scope%2Fpkg*|*/pkg/json) printf 200 ;; *) printf 404 ;; esac
S
chmod +x "$SB/bin/curl"; export PATH="$SB/bin:$PATH"
unset HERDR_ENV ORCA_PANE_KEY CMUX_WORKSPACE_ID
cd "$SB/repo" && git init -q

decide() {
  local out
  out="$(jq -nc --arg c "$PWD" --arg cmd "$1" '{hook_event_name:"PreToolUse",session_id:"s",cwd:$c,tool_name:"Bash",tool_input:{command:$cmd}}' | "$H/guard.sh")"
  [ -n "$out" ] || { echo allow; return; }
  jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out"
}
expect() { local got; got="$(decide "$2")"; [ "$got" = "$1" ] && ok "$1: $2" || bad "$2 → $got, want $1"; }

expect allow 'npm install left-pad'
expect allow 'npm install left-pad > install.log'
expect allow 'npm install left-pad 2>&1 | tail -3'
expect allow 'pip install -r requirements/dev.in'
expect allow 'uv pip install -r requirements.in'
expect allow 'pip install dist/foo-1.0.tar.gz'
expect allow 'pip install --target vendor left-pad'
expect allow 'pip install -t vendor left-pad'
expect allow 'npm install @scope/pkg'
expect allow 'npm install foo.tgz'
expect allow 'npm install foo.tar.gz left-pad'
expect allow 'npm i foo.tar'
expect allow 'pip install foo.tgz'
expect deny  'npm install foo.tgz notreal-pkg'
expect deny  'npm install notreal-pkg'
expect deny  'npm install notreal-pkg > install.log'
expect deny  'pip install -r reqs.txt notreal-pkg'
expect deny  'pip install left-pad notreal-pkg 2>&1'
expect allow 'npm install left-pad &>install.log'
expect deny  'pnpm add -r notreal-pkg'
expect deny  'npm install -t notreal-pkg'
expect deny  'pip install -t vendor notreal-pkg'

# Text that only mentions an install is not looked up (#159): heredoc bodies, -m/--body, echo.
expect allow $'cat > notes.md <<\'EOF\'\nTo try it: npm install notreal-pkg\nEOF'
expect allow 'git commit -m "docs: explain npm install notreal-pkg"'
expect allow 'gh pr create --draft --title x --body "run pip install notreal-pkg"'
expect allow "echo 'npm install notreal-pkg'"
expect deny  'git commit -m "x" && npm install notreal-pkg'

[ "$FAILS" -eq 0 ] && echo ok || { echo "$FAILS failed"; exit 1; }
