# shellcheck shell=bash
# Where flow-stack state lives, for hooks and scripts alike. Source it, then call flow_roots.
#
#   FLOW_ROOT  this checkout's top level: files, fences, git diffs, running checks
#   FLOW_MAIN  the main checkout; equals FLOW_ROOT unless this is a linked git worktree
#   FLOW_DIR   $FLOW_MAIN/.flow, shared by every worktree (.flow/ is untracked, so a
#              worktree has none of its own)
#   FLOW_ACTIVE the file naming the active task: $FLOW_DIR/ACTIVE, or a lead worktree's own
#              <git-dir>/flow-active (a worktree with one is a lead of its own task, not a lane)
#   FLOW_LANE  "" in the main checkout and in a lead worktree; in a worktree, its branch (/ → _). Each lane writes
#              its own evidence, trail, and circuit state, so parallel workers never share a file.
#
# flow_task then resolves the active task. .flow/ACTIVE holds "<slug>" (the task lives here) or
# "@<home-repo-path>:<slug>" (a multi-repo task whose folder lives in its home repo):
#   FLOW_TASK, FLOW_TASK_DIR  the slug and its folder (empty when no task is active)
#   FLOW_TASK_HOME            the repo that owns the task folder
#   FLOW_REPO                 this repo's name: its row in the task's REPOS, else the folder name
#   FLOW_REPO_KEY             "" in the home repo, else FLOW_REPO; it qualifies seal paths
#                             ("<repo>:<path>") and evidence so repos never collide

flow_roots() {
  local d="${1:-$PWD}" common
  FLOW_ROOT="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$d")"
  common="$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  FLOW_MAIN="$FLOW_ROOT"
  if [ "$(basename "${common:-x}")" = .git ]; then FLOW_MAIN="$(dirname "$common")"; fi
  FLOW_DIR="$FLOW_MAIN/.flow"
  FLOW_ACTIVE="$FLOW_DIR/ACTIVE"
  FLOW_LANE=""
  if [ "$FLOW_MAIN" != "$FLOW_ROOT" ]; then
    # A worktree with its own pointer is a lead of that task, not a lane of the main checkout's.
    FLOW_ACTIVE="$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null)/flow-active"
    [ -s "$FLOW_ACTIVE" ] && return 0
    FLOW_ACTIVE="$FLOW_DIR/ACTIVE"
    FLOW_LANE="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '_' || true)"
    if [ -z "$FLOW_LANE" ] || [ "$FLOW_LANE" = HEAD ]; then FLOW_LANE="$(basename "$FLOW_ROOT")"; fi
  fi
}

flow_task() {
  local a h
  FLOW_TASK=""; FLOW_TASK_DIR=""; FLOW_TASK_HOME=""
  FLOW_REPO="$(basename "$FLOW_MAIN")"; FLOW_REPO_KEY=""
  a="$(head -n1 "$FLOW_ACTIVE" 2>/dev/null | tr -d '[:space:]' || true)"
  case "$a" in
    "") return 0 ;;
    @*) h="${a#@}"; h="${h%:*}"; FLOW_TASK="${a##*:}"; FLOW_TASK_HOME="${h/#\~/$HOME}" ;;
    *) FLOW_TASK="$a"; FLOW_TASK_HOME="$FLOW_MAIN" ;;
  esac
  if [ -n "$FLOW_TASK" ] && [ -d "$FLOW_TASK_HOME/.flow/tasks/$FLOW_TASK" ]; then
    FLOW_TASK_DIR="$FLOW_TASK_HOME/.flow/tasks/$FLOW_TASK"
    FLOW_REPO="$(flow_repo_name "$FLOW_MAIN")"
    [ "$FLOW_TASK_HOME" = "$FLOW_MAIN" ] || FLOW_REPO_KEY="$FLOW_REPO"
  else
    FLOW_TASK=""; FLOW_TASK_HOME=""
  fi
}

# flow_repo_name <path>: the task's name for the repo at <path> (REPOS), else its folder name.
flow_repo_name() {
  local n; n="$(awk -F'\t' -v p="$1" '$2 == p { print $1; exit }' "$FLOW_TASK_DIR/REPOS" 2>/dev/null || true)"
  printf '%s' "${n:-$(basename "$1")}"
}

# flow_qual <repo-relative path>: the path as SEALS and other task files name it.
flow_qual() { if [ -n "${FLOW_REPO_KEY:-}" ]; then printf '%s:%s' "$FLOW_REPO_KEY" "$1"; else printf '%s' "$1"; fi; }

# flow_repo_path <name>: a task repo's path from the task's REPOS file (the home repo if unnamed).
flow_repo_path() {
  if [ -z "$1" ] || [ "$1" = "$(flow_repo_name "${FLOW_TASK_HOME:-$FLOW_MAIN}")" ]; then printf '%s' "${FLOW_TASK_HOME:-$FLOW_MAIN}"; return; fi
  awk -F'\t' -v n="$1" '$1 == n { print $2; exit }' "$FLOW_TASK_DIR/REPOS" 2>/dev/null || true
}

# flow_state_dir <task-dir>: where this checkout writes EVIDENCE.md, trail.jsonl, .circuit, HANDOFF.auto.md.
flow_state_dir() {
  if [ -n "$FLOW_LANE" ]; then printf '%s/lanes/%s%s' "$1" "${FLOW_REPO_KEY:+${FLOW_REPO_KEY}_}" "$FLOW_LANE"; else printf '%s' "$1"; fi
}
