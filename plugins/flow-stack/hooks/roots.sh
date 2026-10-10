# shellcheck shell=bash
# Where flow-stack state lives, for hooks and scripts alike. Source it, then call flow_roots.
#
#   FLOW_ROOT  this checkout's top level: files, fences, git diffs, running checks
#   FLOW_MAIN  the main checkout; equals FLOW_ROOT unless this is a linked git worktree
#   FLOW_DIR   $FLOW_MAIN/.flow, shared by every worktree (.flow/ is untracked, so a
#              worktree has none of its own)
#   FLOW_ACTIVE the file naming the active task: $FLOW_DIR/ACTIVE, or a lead worktree's own
#              <git-dir>/flow-active (a worktree with one is a lead of its own task, not a lane)
#   FLOW_LANE  "" in the main checkout and in a lead worktree; in any other worktree, its branch
#              (/ → _). Each lane writes its own evidence, trail, and circuit state, so
#              parallel workers never share a file.
#
# flow_task then resolves the active task. .flow/ACTIVE holds "<slug>" (the task lives here) or
# "@<home-repo-path>:<slug>" (a multi-repo task whose folder lives in its home repo), then on line 2
# the pid of the Claude session that owns it. While that session lives, the task is its alone: every
# other session in the checkout has none (a lane's flow-lane pointer has no owner; workers share it).
#   FLOW_TASK, FLOW_TASK_DIR  the slug and its folder (empty when no task is active, or it isn't ours)
#   FLOW_FOREIGN, FLOW_OWNER  the slug and owner pid of the task here that another live session owns
#   FLOW_TASK_HOME            the repo that owns the task folder
#   FLOW_REPO                 this repo's name: its row in the task's REPOS, else the folder name
#   FLOW_REPO_KEY             "" in the home repo, else FLOW_REPO; it qualifies seal paths
#                             ("<repo>:<path>") and evidence so repos never collide

flow_roots() {
  local d="${1:-$PWD}" common gd
  FLOW_ROOT="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$d")"
  common="$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  FLOW_MAIN="$FLOW_ROOT"
  if [ "$(basename "${common:-x}")" = .git ]; then FLOW_MAIN="$(dirname "$common")"; fi
  FLOW_DIR="$FLOW_MAIN/.flow"
  FLOW_ACTIVE="$FLOW_DIR/ACTIVE"
  FLOW_LANE=""
  if [ "$FLOW_MAIN" != "$FLOW_ROOT" ]; then
    gd="$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null)"
    FLOW_ACTIVE="$gd/flow-active"
    [ -s "$FLOW_ACTIVE" ] && return 0
    FLOW_ACTIVE="$FLOW_DIR/ACTIVE"
    # flow-lane (slug, then the lead's root) makes this a worker lane of that lead's task
    [ -s "$gd/flow-lane" ] && FLOW_ACTIVE="$gd/flow-lane"
    FLOW_LANE="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '_' || true)"
    if [ -z "$FLOW_LANE" ] || [ "$FLOW_LANE" = HEAD ]; then FLOW_LANE="$(basename "$FLOW_ROOT")"; fi
  fi
}

# Claude Code keeps a row per live session: <config dir>/sessions/<pid>.json {pid, sessionId, cwd, name, status}.
flow_sessions() { printf '%s/sessions' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }

# flow_session: set FLOW_SESSION_PID to the Claude session this process runs under (a hook's parent,
# or an ancestor of a script it runs); "" outside Claude, where the human sees every task. A preset
# FLOW_SESSION_PID wins.
flow_session() {
  local p="$PPID" n=0 reg
  [ -z "${FLOW_SESSION_PID+x}" ] || return 0
  FLOW_SESSION_PID=""; reg="$(flow_sessions)"
  while [ -n "$p" ] && [ "$p" -gt 1 ] && [ $n -lt 8 ]; do
    [ -f "$reg/$p.json" ] && { FLOW_SESSION_PID="$p"; return 0; }
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ' || true)"; n=$((n + 1))
  done
}

# flow_live <pid>: that Claude session is running: its registry row exists, and the process with that
# pid is the one the row names (the same start time; a crashed session's row can outlive its pid).
# Only the digits are compared (day, time, year), since month and weekday names follow the locale.
# A row without procStart (older Claude Code) counts as live: the task stays refused, never taken.
flow_live() {
  local f st
  f="$(flow_sessions)/$1.json"
  [ -n "$1" ] && [ -f "$f" ] && kill -0 "$1" 2>/dev/null || return 1
  st="$(jq -r '.procStart // empty' "$f" 2>/dev/null | tr -cs '0-9:' ' ' || true)"
  [ -z "${st// /}" ] || [ "$(TZ=UTC ps -o lstart= -p "$1" 2>/dev/null | tr -cs '0-9:' ' ' || true)" = "$st" ]
}

# flow_owner_name <pid>: the session's name as ListAgents and SendMessage know it, else "pid <pid>".
flow_owner_name() { local n; n="$(jq -r '.name // empty' "$(flow_sessions)/$1.json" 2>/dev/null)"; printf '%s' "${n:-pid $1}"; }

# flow_point <file> <value>: write a task pointer this session owns.
flow_point() { flow_session; mkdir -p "$(dirname "$1")"; printf '%s\n%s\n' "$2" "$FLOW_SESSION_PID" >"$1"; }

# flow_claim: make an unowned pointer (no owner recorded, or the owner is gone) this session's.
flow_claim() {
  local o
  [ -z "$FLOW_LANE" ] && [ -s "$FLOW_ACTIVE" ] || return 0
  flow_session; [ -n "$FLOW_SESSION_PID" ] || return 0
  o="$(sed -n 2p "$FLOW_ACTIVE" | tr -d '[:space:]')"
  [ "$o" = "$FLOW_SESSION_PID" ] || flow_live "$o" || flow_point "$FLOW_ACTIVE" "$(head -n1 "$FLOW_ACTIVE")"
}

flow_task() {
  local a h o
  FLOW_TASK=""; FLOW_TASK_DIR=""; FLOW_TASK_HOME=""; FLOW_FOREIGN=""; FLOW_OWNER=""
  FLOW_REPO="$(basename "$FLOW_MAIN")"; FLOW_REPO_KEY=""
  a="$(head -n1 "$FLOW_ACTIVE" 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -n "$a" ] && [ "${FLOW_ACTIVE##*/}" != flow-lane ]; then
    o="$(sed -n 2p "$FLOW_ACTIVE" 2>/dev/null | tr -d '[:space:]' || true)"
    if [ -n "$o" ] && flow_session && [ -n "$FLOW_SESSION_PID" ] && [ "$o" != "$FLOW_SESSION_PID" ] && flow_live "$o"; then
      FLOW_FOREIGN="${a##*:}"; FLOW_OWNER="$o"; return 0
    fi
  fi
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

# flow_owners [main]: "slug<TAB>checkout<TAB>pointer<TAB>owner pid" for every local task some checkout
# leads: the main checkout's ACTIVE, then each lead worktree's flow-active. Multi-repo pointers
# (@home:slug) belong to their home repo. The pid is "" when unowned or its session is gone; it comes
# last because `read` with IFS=tab collapses an empty field in the middle.
flow_owners() {
  local m="${1:-$FLOW_MAIN}" f v o c
  for f in "$m/.flow/ACTIVE" "$m"/.git/worktrees/*/flow-active; do
    v="$(head -n1 "$f" 2>/dev/null | tr -d '[:space:]')"
    case "$v" in ""|@*) continue ;; esac
    o="$(sed -n 2p "$f" | tr -d '[:space:]')"; flow_live "$o" || o=""
    c="$m"; [ "$f" = "$m/.flow/ACTIVE" ] || c="$(dirname "$(cat "${f%/*}/gitdir")")"
    printf '%s\t%s\t%s\t%s\n' "$v" "$c" "$f" "$o"
  done
}

# flow_state_dir <task-dir>: where this checkout writes EVIDENCE.md, trail.jsonl, .circuit, HANDOFF.auto.md.
flow_state_dir() {
  if [ -n "$FLOW_LANE" ]; then printf '%s/lanes/%s%s' "$1" "${FLOW_REPO_KEY:+${FLOW_REPO_KEY}_}" "$FLOW_LANE"; else printf '%s' "$1"; fi
}
