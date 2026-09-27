#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit|NotebookEdit): sealed checks need the
# human; edits outside the current slice's fence must be widened on purpose.
. "$(dirname "$0")/lib.sh"
flow_init edit-guard
[ -n "$FLOW_TASK_DIR" ] || exit 0

file="$(flow_field '.tool_input.file_path // .tool_input.notebook_path')"
[ -n "$file" ] || exit 0
rel="$(flow_rel "$file")"

case "$rel" in
  /*) exit 0 ;;          # outside the repo
  .flow/tasks/*/SEALS|.flow/tasks/*/INTENT.md)
    if flow_enabled seal && [ -f "$FLOW_TASK_DIR/SEALS" ]; then
      pre_decide ask "flow seal: task '$FLOW_TASK' is sealed; editing $(basename "$rel") changes the acceptance contract, so the human approves."
    fi
    exit 0 ;;
  .flow/tasks/*/SLICES.md)
    # "done" goes through the proof gate (task.sh slice <id> done), never a direct edit.
    count_done() { grep -c '^status: done' 2>/dev/null || true; }
    new_text="$(flow_field '.tool_input.new_string // .tool_input.content')"
    if [ "$(flow_field .tool_name)" = Write ]; then
      before="$(count_done <"$FLOW_ROOT/$rel")"
    else
      before="$(flow_field .tool_input.old_string | count_done)"
    fi
    after="$(printf '%s\n' "$new_text" | count_done)"
    if [ "${after:-0}" -gt "${before:-0}" ]; then
      pre_decide deny "flow gate: mark a slice done with '../flow/scripts/task.sh slice <id> done' (it checks red-first, green, teeth, and budget), not by editing SLICES.md. Missing proofs: 'task.sh proofs <id>'."
    fi
    exit 0 ;;
  .flow/*) exit 0 ;;     # bookkeeping is always allowed
esac

if flow_enabled seal && [ -f "$FLOW_TASK_DIR/SEALS" ]; then
  if awk -v p="$rel" '$2 == p {found=1} END {exit !found}' "$FLOW_TASK_DIR/SEALS"; then
    pre_decide ask "flow seal: '$rel' is a sealed acceptance check for task '$FLOW_TASK'. Changing it changes what 'done' means, so the human approves. If approved, re-seal afterwards."
  fi
fi

if flow_enabled fence && [ -f "$FLOW_TASK_DIR/SLICES.md" ]; then
  read -r slice fence <<<"$(awk '
    /^## / { h = $0; sub(/^## /, "", h); sub(/ .*/, "", h); f = ""; d = 0 }
    /^fence:/ { f = $0; sub(/^fence:[[:space:]]*/, "", f); sub(/[[:space:]]*#.*/, "", f) }
    /^status: doing/ { d = 1 }
    d && f != "" { print h, f; exit }' "$FLOW_TASK_DIR/SLICES.md")"
  if [ -n "$fence" ]; then
    inside=0
    set -f
    for g in $fence; do
      if glob_match "$rel" "$g"; then inside=1; break; fi
    done
    set +f
    if [ "$inside" = 0 ]; then
      pre_decide deny "flow fence: '$rel' is outside slice $slice's fence ($fence). If this edit is truly needed, add the path to the fence in .flow/tasks/$FLOW_TASK/SLICES.md, log why in DECISIONS.tsv, then retry. Otherwise stay in scope."
    fi
  fi
fi

exit 0
