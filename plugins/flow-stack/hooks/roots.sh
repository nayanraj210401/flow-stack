# shellcheck shell=bash
# Where flow-stack state lives, for hooks and scripts alike. Source it, then call flow_roots.
#
#   FLOW_ROOT  this checkout's top level: files, fences, git diffs, running checks
#   FLOW_MAIN  the main checkout; equals FLOW_ROOT unless this is a linked git worktree
#   FLOW_DIR   $FLOW_MAIN/.flow, shared by every worktree (.flow/ is untracked, so a
#              worktree has none of its own)
#   FLOW_LANE  "" in the main checkout; in a worktree, its branch (/ → _). Each lane writes
#              its own evidence, trail, and circuit state, so parallel workers never share a file.

flow_roots() {
  local d="${1:-$PWD}" common
  FLOW_ROOT="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$d")"
  common="$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  FLOW_MAIN="$FLOW_ROOT"
  if [ "$(basename "${common:-x}")" = .git ]; then FLOW_MAIN="$(dirname "$common")"; fi
  FLOW_DIR="$FLOW_MAIN/.flow"
  FLOW_LANE=""
  if [ "$FLOW_MAIN" != "$FLOW_ROOT" ]; then
    FLOW_LANE="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '_' || true)"
    if [ -z "$FLOW_LANE" ] || [ "$FLOW_LANE" = HEAD ]; then FLOW_LANE="$(basename "$FLOW_ROOT")"; fi
  fi
}

# flow_state_dir <task-dir>: where this checkout writes EVIDENCE.md, trail.jsonl, .circuit, HANDOFF.auto.md.
flow_state_dir() {
  if [ -n "$FLOW_LANE" ]; then printf '%s/lanes/%s' "$1" "$FLOW_LANE"; else printf '%s' "$1"; fi
}
