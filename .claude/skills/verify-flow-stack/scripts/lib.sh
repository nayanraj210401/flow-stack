# shellcheck shell=bash
# Shared helpers for verify-flow-stack scenarios. Source it first:
#   . "$(dirname "$0")/lib.sh"; sandbox <feature-id>
# Every scenario runs the WORKING TREE's plugin (not the installed cache) inside a
# throwaway toy repo with a throwaway FLOW_STACK_HOME, so nothing real is touched.
set -euo pipefail

REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
PLUGIN="$REPO/plugins/flow-stack"
H="$PLUGIN/hooks"
S="$PLUGIN/skills"
FAILS=0
# .flow/ belongs to the main checkout: from a linked worktree, artifacts still land there
FLOW_MAIN_DIR="$(dirname "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)")"

# sandbox <feature-id>: cd into a fresh toy repo (evals/_lib/toy.sh), isolated home, artifacts dir.
sandbox() {
  FEATURE="$1"
  ART="${FLOW_ARTIFACTS:-$FLOW_MAIN_DIR/.flow/artifacts}/$FEATURE"
  mkdir -p "$ART"; : >"$ART/decisions.tsv"; : >"$ART/stderr.log"
  SB="$(mktemp -d "${TMPDIR:-/tmp}/verify-flow-stack.XXXXXX")"
  SB="$(cd "$SB" && pwd -P)"
  trap 'rm -rf "$SB"' EXIT
  export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
  mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR"
  mkdir -p "$SB/repo" && cd "$SB/repo"
  # shellcheck source=/dev/null
  . "$PLUGIN/evals/_lib/toy.sh"
  toy_repo
  echo "== $FEATURE · sandbox $SB/repo"
}

ok()   { echo "  ✓ $*"; }
bad()  { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
check() { # check "<label>" <cmd...>: pass when the command exits 0
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label"; fi
}
fails() { # fails "<label>" <cmd...>: pass when the command exits non-zero
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then bad "$label (exited 0)"; else ok "$label"; fi
}
has() { grep -Fq -- "$2" <<<"$1"; } # has "<text>" "<needle>"
sees() { # sees "<label>" "<needle>" <cmd...>: the command's stdout+stderr contains needle
  local label="$1" n="$2" o; shift 2
  o="$("$@" 2>&1)" || true
  if has "$o" "$n"; then ok "$label"; else bad "$label: no '$n' in: $(tail -n 3 <<<"$o" | tr '\n' ' ')"; fi
}

# hook <script> <json>: run a hook the way Claude Code does (JSON on stdin). OUT = its stdout.
hook() { OUT="$(printf '%s' "$2" | "$H/$1" 2>>"$ART/stderr.log")" || true; }
# pre <tool> <tool_input-json>: PreToolUse payload for this sandbox
pre() { jq -nc --arg cwd "$PWD" --arg t "$1" --argjson i "$2" '{cwd:$cwd, hook_event_name:"PreToolUse", tool_name:$t, tool_input:$i}'; }
# edit <path> [Edit|Write]: an Edit/Write PreToolUse payload for <path>
edit() { pre "${2:-Edit}" "$(jq -nc --arg f "$1" '{file_path:$f, old_string:"a", new_string:"b", content:"x"}')"; }
bashcmd() { pre Bash "$(jq -nc --arg c "$1" '{command:$c}')"; }
decision() { [ -n "$OUT" ] || { echo allow; return; }; jq -r '.hookSpecificOutput.permissionDecision // .decision // "allow"' <<<"$OUT" 2>/dev/null || echo allow; }
# expect <hook> <json> <allow|deny|ask|block> <label>
expect() {
  hook "$1" "$2"
  local d; d="$(decision)"
  if [ "$d" = "$3" ]; then ok "$4 → $3"; else bad "$4 → got $d, want $3 ($OUT)"; fi
  printf '%s\t%s\t%s\n' "$4" "$d" "$(tr '\n' ' ' <<<"$OUT" | cut -c1-200)" >>"$ART/decisions.tsv"
}

# finish: exit with the verdict
finish() {
  if [ "$FAILS" -eq 0 ]; then echo "== $FEATURE · PASS (artifacts: $ART)"; exit 0; fi
  echo "== $FEATURE · FAIL ($FAILS assertion(s))"; exit 1
}
