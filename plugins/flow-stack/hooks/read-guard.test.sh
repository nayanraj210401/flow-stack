#!/usr/bin/env bash
# read-guard.test.sh: Grep/Glob may not read .env files or recurse into the held-out check dir
# through an ancestor path; ordinary and repo-wide searches stay allowed.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }

SB="$(mktemp -d "${TMPDIR:-/tmp}/read-guard.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR" "$SB/repo/.flow/tasks/x/blind"
cd "$SB/repo" && git init -q .

# check <want> <label> <tool> <tool_input json>
check() {
  local out got
  out="$(jq -nc --arg cwd "${CWD_OVERRIDE:-$PWD}" --arg t "$3" --argjson i "$4" \
    '{cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$t, tool_input:$i}' | bash "$H/read-guard.sh" 2>/dev/null)"
  got="allow"
  [ -z "$out" ] || got="$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$out")"
  if [ "$got" = "$1" ]; then ok "$2 → $1"; else bad "$2 → got $got, want $1"; fi
}

echo "-- .env"
check deny  "Grep path=.env"          Grep '{"pattern":"K","path":".env"}'
check deny  "Grep path=.env.local"    Grep '{"pattern":"K","path":".env.local"}'
check deny  "Grep absolute .env"      Grep "$(jq -nc --arg p "$PWD/.env" '{pattern:"K",path:$p}')"
check deny  "Grep glob=.env*"         Grep '{"pattern":"K","path":".","glob":".env*"}'
check deny  "Read .env"               Read '{"file_path":".env"}'
check allow "Grep path=.env.example"  Grep '{"pattern":"K","path":".env.example"}'
check allow "Grep path=.env.sample"   Grep '{"pattern":"K","path":".env.sample"}'

echo "-- held-out checks"
check deny  "Grep held-out dir"       Grep '{"pattern":"m","path":".flow/tasks/x/blind"}'
check deny  "Grep task dir"           Grep '{"pattern":"m","path":".flow/tasks/x"}'
check deny  "Grep task dir slash"     Grep '{"pattern":"m","path":".flow/tasks/x/"}'
check deny  "Grep .flow/tasks"        Grep '{"pattern":"m","path":".flow/tasks"}'
check deny  "Grep .flow"              Grep '{"pattern":"m","path":".flow"}'
check deny  "Grep absolute .flow"     Grep "$(jq -nc --arg p "$PWD/.flow" '{pattern:"m",path:$p}')"
check deny  "Grep glob .flow/**"      Grep '{"pattern":"m","path":".","glob":".flow/**"}'
check deny  "Glob .flow/**"           Glob '{"pattern":".flow/**/*"}'
check allow "Grep path=."             Grep '{"pattern":"m","path":"."}'
check allow "Grep no path"            Grep '{"pattern":"m"}'
check allow "Grep .flow/features"     Grep '{"pattern":"m","path":".flow/features"}'
check allow "Grep task INTENT.md"     Grep '{"pattern":"m","path":".flow/tasks/x/INTENT.md"}'
check allow "Glob src"                Glob '{"pattern":"src/**/*.sh"}'

echo "-- dot segments, cwd, globs"
check deny  "Grep .flow/tasks/x/../x"   Grep '{"pattern":"m","path":".flow/tasks/x/../x"}'
check deny  "Grep .flow/./tasks"        Grep '{"pattern":"m","path":".flow/./tasks"}'
check deny  "Grep .flow//tasks"         Grep '{"pattern":"m","path":".flow//tasks"}'
check deny  "Grep x/../.flow"           Grep '{"pattern":"m","path":"src/../.flow"}'
check deny  "Grep glob **/blind/**"     Grep '{"pattern":"m","path":".","glob":"**/blind/**"}'
check deny  "Glob **/blind/**"          Glob '{"pattern":"**/blind/**"}'
check deny  "Glob */blind/*"            Glob '{"pattern":"*/blind/*"}'
check deny  "Glob **/MANIFEST"          Glob '{"pattern":"**/MANIFEST"}'
check deny  "Glob base .flow/tasks"     Glob '{"pattern":"*/*","path":".flow/tasks"}'
check allow "Glob src/**/MANIFEST_utils.ts" Glob '{"pattern":"src/**/MANIFEST_utils.ts"}'
check allow "Grep regex mentioning .flow/**" Grep '{"pattern":"see .flow/** docs","path":"."}'
check allow "Grep regex mentioning blind"    Grep '{"pattern":"tasks/x/blind"}'
CWD_OVERRIDE="$PWD/.flow"
check deny  "cwd=.flow path=tasks"      Grep '{"pattern":"m","path":"tasks"}'
check deny  "cwd=.flow no path"         Grep '{"pattern":"m"}'
CWD_OVERRIDE=""

[ "$FAILS" -eq 0 ] && { echo "read-guard: all ok"; exit 0; }
echo "read-guard: $FAILS failed"; exit 1
