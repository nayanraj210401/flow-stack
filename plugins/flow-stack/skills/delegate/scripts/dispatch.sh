#!/usr/bin/env bash
# dispatch.sh: start a slice's worker where the profile's "- delegate:" says.
#   dispatch.sh start <slug> <slice>   agent (default) → prints "use the Agent tool", exit 0
#                                      herdr-panes     → worktree + claude pane + worker brief; prints the lane
#   dispatch.sh wait <lane>            block until that pane's agent finishes (herdr agent wait)
#   dispatch.sh cleanup <lane>         after a successful `task.sh accept`: remove the worktree dispatch.sh
#                                      made (recorded in lanes/<lane>/HOST), only when it has no uncommitted changes
#   dispatch.sh gc                     clean every recorded, clean lane of the active task
# A worker pane joins the task as a lane, so evidence, accept and the lane registry work as for the Agent tool.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../../../hooks/lib.sh"; flow_roots; flow_task
die() { echo "dispatch.sh: $*" >&2; exit 1; }
provider() { profile_section Toolchain | sed -n 's/^- delegate:[[:space:]]*\([a-z-]*\).*/\1/p' | head -n1; }
hostf() { printf '%s/lanes/%s/HOST' "$FLOW_TASK_DIR" "$1"; }
hget() { sed -n "s/^$2=//p" "$(hostf "$1")" 2>/dev/null | head -n1; }

cleanup() { # cleanup <lane>
  local lane="$1" ws path
  [ -f "$(hostf "$lane")" ] || die "lane '$lane' has no HOST record; not created by dispatch.sh, left alone"
  ws="$(hget "$lane" workspace)"; path="$(hget "$lane" path)"
  [ -n "$ws" ] && [ -d "$path" ] || die "lane '$lane': HOST record has no live worktree"
  [ -z "$(git -C "$path" status --porcelain 2>/dev/null)" ] || die "lane '$lane': $path has uncommitted changes; kept"
  herdr worktree remove --workspace "$ws" >/dev/null && echo "removed: $lane ($ws)"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  start)
    slug="${1:-}"; slice="${2:-}"; [ -n "$slug" ] && [ -n "$slice" ] || die "usage: dispatch.sh start <slug> <slice>"
    case "$(provider)" in
      herdr-panes) ;;
      ""|agent) echo "delegate: agent → use the Agent tool"; exit 0 ;;
      *) die "unsupported delegate provider '$(provider)' (agent|herdr-panes)" ;;
    esac
    [ "$FLOW_TASK" = "$slug" ] || die "task '$slug' is not the active task here"
    command -v herdr >/dev/null && command -v jq >/dev/null || die "herdr-panes needs herdr and jq on PATH"
    branch="flow/$slug-$slice"; lane="${branch//\//_}"; name="flow-$slug-$slice"
    res="$(herdr worktree create --branch "$branch" --no-focus)" || die "herdr worktree create failed"
    path="$(jq -r '.result.worktree.path // empty' <<<"$res")"
    ws="$(jq -r '.result.workspace.workspace_id // empty' <<<"$res")"
    pane="$(jq -r '.result.root_pane.pane_id // empty' <<<"$res")"
    [ -n "$path" ] && [ -n "$ws" ] && [ -n "$pane" ] || die "unexpected herdr worktree create result: $res"
    mkdir -p "$FLOW_TASK_DIR/lanes/$lane"
    printf 'workspace=%s\npane=%s\npath=%s\nbranch=%s\nagent=%s\n' "$ws" "$pane" "$path" "$branch" "$name" >"$(hostf "$lane")"
    gd="$(git -C "$path" rev-parse --absolute-git-dir)"
    : >"$gd/flow-thread"                       # its prompts come from outside: irreversible gates queue, as under --auto
    (cd "$path" && "$here/../../flow/scripts/task.sh" join "$slug" >/dev/null) || die "worker worktree could not join '$slug'"
    model="$(profile_fm build_model)"
    herdr agent start "$name" --kind claude --pane "$pane" -- ${model:+--model "$model"} >/dev/null || die "herdr agent start failed (worktree kept: $path)"
    herdr agent prompt "$name" "You are the worker for task $slug, slice $slice. First run: task.sh join $slug (skip if task.sh active already prints it). Then follow flow-stack:loop for $slice only, as in the worker agent definition, and finish with the worker report." >/dev/null || die "herdr agent prompt failed"
    echo "$lane" ;;
  wait)
    lane="${1:-}"; [ -n "$lane" ] && [ -f "$(hostf "$lane")" ] || die "usage: dispatch.sh wait <lane> (a lane dispatch.sh started)"
    herdr agent wait "$(hget "$lane" agent)" ;;
  cleanup)
    [ -n "${1:-}" ] || die "usage: dispatch.sh cleanup <lane>"; cleanup "$1" ;;
  gc)
    for f in "$FLOW_TASK_DIR"/lanes/*/HOST; do
      [ -f "$f" ] || continue
      cleanup "$(basename "$(dirname "$f")")" 2>&1 || true
    done ;;
  *) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
