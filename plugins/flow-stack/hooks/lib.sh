# shellcheck shell=bash
# Shared helpers for flow-stack hooks. Every hook fails open: any error
# logs a warning and exits 0 so the stack can never lock the user out.

. "$(dirname "${BASH_SOURCE[0]}")/roots.sh"

FLOW_HOME="${FLOW_STACK_HOME:-$HOME/.flow-stack}"
FLOW_LOG="$FLOW_HOME/hooks.log"

flow_warn() {
  mkdir -p "$FLOW_HOME" 2>/dev/null
  printf '%s %s %s\n' "$(date -u +%FT%TZ)" "${FLOW_HOOK:-hook}" "$*" >>"$FLOW_LOG" 2>/dev/null
}

flow_fail_open() {
  flow_warn "error at line ${1:-?}; allowing"
  exit 0
}

# flow_join: a subagent in an unpointed worktree joins the task of the lead worktree that spawned it
# (the lead registry, by session id), writing <git-dir>/flow-lane = slug, lead root. A main-spawned one writes nothing.
flow_join() {
  local sid aid lroot lgd slug gd
  [ -n "$FLOW_LANE" ] || return 0
  aid="$(flow_field .agent_id)"; sid="$(flow_field .session_id)"
  [ -n "$aid" ] && [ -n "$sid" ] || return 0
  gd="$(git -C "$FLOW_ROOT" rev-parse --absolute-git-dir)"
  [ -s "$gd/flow-lane" ] && return 0
  lroot="$(jq -r '.root // empty' "$FLOW_HOME/leads/${sid//\//_}.json" 2>/dev/null || true)"
  [ -n "$lroot" ] && [ "$lroot" != "$FLOW_MAIN" ] && [ "$lroot" != "$FLOW_ROOT" ] || return 0
  [ "$(git -C "$lroot" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" = "$FLOW_MAIN/.git" ] || return 0
  lgd="$(git -C "$lroot" rev-parse --absolute-git-dir 2>/dev/null)" || return 0
  slug="$(head -n1 "$lgd/flow-active" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$slug" ] || return 0
  printf '%s\n%s\n' "$slug" "$lroot" >"$gd/flow-lane"
  flow_roots "$FLOW_CWD"
}

flow_init() {
  FLOW_HOOK="$1"
  trap 'flow_fail_open $LINENO' ERR
  if ! command -v jq >/dev/null 2>&1; then
    flow_warn "jq not found; hook disabled"
    exit 0
  fi
  [ -n "${FLOW_INPUT:-}" ] || FLOW_INPUT="$(cat)"   # a hook may read stdin first for a fast exit
  FLOW_CWD="$(jq -r '.cwd // empty' <<<"$FLOW_INPUT")"
  [ -n "$FLOW_CWD" ] || FLOW_CWD="$PWD"
  flow_roots "$FLOW_CWD"
  flow_join
  flow_task
  FLOW_STATE_DIR=""
  if [ -n "$FLOW_TASK_DIR" ]; then
    FLOW_STATE_DIR="$(flow_state_dir "$FLOW_TASK_DIR")"
    mkdir -p "$FLOW_STATE_DIR"
  fi
}

# flow_enabled <hook-name>: repo .flow/config.json wins, then ~/.flow-stack/config.json, default on.
flow_enabled() {
  local v cfg
  for cfg in "$FLOW_DIR/config.json" "$FLOW_HOME/config.json"; do
    [ -f "$cfg" ] || continue
    v="$(jq -r --arg h "$1" 'if (.hooks // {} | has($h)) then .hooks[$h] | tostring else empty end' "$cfg" 2>/dev/null)"
    [ -n "$v" ] && { [ "$v" != false ]; return; }
  done
  return 0
}

flow_field() {
  jq -r "$1 // empty" <<<"$FLOW_INPUT"
}

# Path relative to the repo root; absolute input outside the repo is returned as-is.
flow_rel() {
  local p="$1"
  case "$p" in
    "$FLOW_DIR"/*) printf '.flow/%s' "${p#"$FLOW_DIR"/}" ;;
    "$FLOW_ROOT"/*) printf '%s' "${p#"$FLOW_ROOT"/}" ;;
    /*) printf '%s' "$p" ;;
    *) printf '%s' "${p#./}" ;;
  esac
}

# glob_match <path> <glob>: ** and * both cross directories; good enough for fences.
glob_match() {
  local path="$1" glob="${2//\*\*/*}"
  # shellcheck disable=SC2053
  [[ "$path" == $glob ]]
}

# TDD lock (task.sh tdd <id> red|green): $FLOW_STATE_DIR/TDD holds "<id> <phase> <red-FAIL count>".
# flow_tdd sets TDD_ID, TDD_PHASE, and TDD_TESTS (the slice's tests: globs, empty = default patterns).
flow_tdd() {
  local f="$FLOW_STATE_DIR/TDD"
  [ -n "$FLOW_STATE_DIR" ] && [ -s "$f" ] || return 1
  read -r TDD_ID TDD_PHASE _ <"$f" || true
  TDD_TESTS="$(awk -v id="$TDD_ID" '/^## /{cur=$2} cur==id && /^tests:/{sub(/^tests:[[:space:]]*/,""); sub(/[[:space:]]+#.*/,""); print; exit}' "$FLOW_TASK_DIR/SLICES.md" 2>/dev/null || true)"
  [ -n "$TDD_PHASE" ]
}

# flow_is_test <repo-relative path> [globs]: the globs when given, else common test locations and names.
flow_is_test() {
  local g b="${1##*/}"
  if [ -n "${2:-}" ]; then
    set -f; for g in $2; do glob_match "$1" "$g" && { set +f; return 0; }; done; set +f; return 1
  fi
  case "/$1" in */test/*|*/tests/*|*/__tests__/*|*/spec/*) return 0 ;; esac
  case "$b" in test_*|*_test.*|*.test.*|*-test.*|*.spec.*|*_spec.*|*Test.*|*Tests.*) return 0 ;; esac
  return 1
}

# Auto mode (--auto in a prompt): the human is away for this session. Flag: $FLOW_HOME/auto/<session_id>.
flow_auto_flag() { local s; s="$(flow_field .session_id)"; [ -n "$s" ] && printf '%s/auto/%s' "$FLOW_HOME" "${s//\//_}"; }
# A pane that delegate's dispatch.sh started (<git-dir>/flow-thread) is driven by prompts the lead
# types, not the human's, so it runs like --auto: outward-facing actions wait in GATES.md.
flow_auto() {
  local f; f="$(flow_auto_flag)" && [ -f "$f" ] && return 0
  [ -f "$(git -C "${FLOW_ROOT:-.}" rev-parse --absolute-git-dir 2>/dev/null)/flow-thread" ]
}

# flow_host: the agent host this session runs in: herdr | orca | cmux | conductor | none.
# Host env leaks through tmux, ssh and nested shells, so it counts only while the host answers:
# herdr and cmux by their socket, Orca by its agent-hook port (bare `orca` on Linux is a screen reader).
flow_host() {
  if [ "${HERDR_ENV:-}" = 1 ] && [ -S "${HERDR_SOCKET_PATH:-}" ] && [ -x "${HERDR_BIN_PATH:-}" ]; then echo herdr
  elif [ -n "${ORCA_PANE_KEY:-}" ] && [ -n "${ORCA_AGENT_HOOK_PORT:-}" ] && (exec 3<>"/dev/tcp/127.0.0.1/$ORCA_AGENT_HOOK_PORT") 2>/dev/null \
    && command -v "${ORCA_CLI_COMMAND:-orca}" >/dev/null 2>&1; then echo orca
  elif [ -n "${CMUX_WORKSPACE_ID:-}" ] && [ -S "${CMUX_SOCKET_PATH:-/tmp/cmux.sock}" ] && command -v cmux >/dev/null 2>&1; then echo cmux
  elif [ -n "${CONDUCTOR_WORKSPACE_PATH:-}" ]; then echo conductor
  else echo none; fi
}
flow_auto_ship() { local f; f="$(flow_auto_flag)" && [ "$(cat "$f" 2>/dev/null)" = ship ]; }
FLOW_AUTO_QUEUE="Add it to .flow/tasks/<slug>/GATES.md (question, options, recommendation), keep going on work it doesn't block, and list GATES.md first in the handoff."

pre_decide() {
  # pre_decide <allow|deny|ask> <reason>. In auto mode nobody can answer an ask, so it is queued instead.
  if [ "$1" = ask ] && flow_auto; then
    set -- deny "flow auto: the human is away, so this waits. $2 $FLOW_AUTO_QUEUE"
  fi
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

redact() {
  perl -pe '
    s/(sk-[A-Za-z0-9_-]{4})[A-Za-z0-9_-]{8,}/$1-REDACTED/g;
    s/(gh[pousr]_)[A-Za-z0-9]{10,}/$1REDACTED/g;
    s/AKIA[0-9A-Z]{16}/AKIA-REDACTED/g;
    s/(xox[abpr]-)[A-Za-z0-9-]+/$1REDACTED/g;
    s/(Bearer\s+)[A-Za-z0-9._~+\/=-]{8,}/$1REDACTED/gi;
    s/(\w*(?:api[_-]?key|token|secret|passw(?:or)?d|pwd)\w*["\x27]?\s*[:=]\s*["\x27]?)[^"\x27\s&]+/$1REDACTED/gi;
  '
}

# The profile, with HTML comments stripped.
profile_clean() {
  local f="$FLOW_HOME/profile.md"
  [ -f "$f" ] || return 1
  perl -0pe 's/<!--.*?-->\n?//gs' "$f"
}

# profile_section <Heading>: body of a top-level "# Heading" section.
profile_section() {
  profile_clean | awk -v h="# $1" '
    $0 == h { on = 1; next }
    on && /^# / { exit }
    on { print }'
}

profile_fm() {
  # profile_fm <key>: value of a top-level or nested "key:" line in frontmatter
  profile_clean | awk -v k="$1" '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm {
      line = $0; sub(/^[[:space:]]+/, "", line)
      if (index(line, k ":") == 1) {
        v = substr(line, length(k) + 2); sub(/#.*/, "", v)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); print v; exit
      }
    }'
}
