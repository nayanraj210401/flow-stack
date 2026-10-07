#!/usr/bin/env bash
# PreToolUse(Edit|Write|MultiEdit|NotebookEdit): sealed checks need the
# human; edits outside the current slice's fence must be widened on purpose;
# under an opt-in TDD lock, red edits only tests and green edits only code.
. "$(dirname "$0")/lib.sh"
flow_init edit-guard
[ -n "$FLOW_TASK_DIR" ] || exit 0

file="$(flow_field '.tool_input.file_path // .tool_input.notebook_path')"
[ -n "$file" ] || exit 0
rel="$(flow_rel "$file")"
# The repo the file belongs to. In a multi-repo task a file in another task repo (or the
# task's home .flow/) is judged as that repo's file, not waved through as "outside".
erepo="$FLOW_REPO"; ekey="$FLOW_REPO_KEY"; epath="$FLOW_MAIN"
case "$rel" in
  /*) while IFS=$'\t' read -r n p; do
        [ -n "$p" ] || continue
        case "$file" in "$p"/*)
          rel="${file#"$p"/}"; erepo="$n"; epath="$p"
          if [ "$p" = "$FLOW_TASK_HOME" ]; then ekey=""; else ekey="$n"; fi
          break ;;
        esac
      done < <({ cat "$FLOW_TASK_DIR/REPOS" 2>/dev/null; printf '%s\t%s\n' "$(flow_repo_name "$FLOW_TASK_HOME")" "$FLOW_TASK_HOME"; } |
               awk -F'\t' '{ print length($2) "\t" $0 }' | sort -rn | cut -f2-) ;;   # longest path first: nested checkouts
esac
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
      before="$(count_done <"$epath/$rel")"
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
  if awk -v p="${ekey:+$ekey:}$rel" '$2 == p {found=1} END {exit !found}' "$FLOW_TASK_DIR/SEALS"; then
    pre_decide ask "flow seal: '$rel' is a sealed acceptance check for task '$FLOW_TASK'. Changing it changes what 'done' means, so the human approves. If approved, re-seal afterwards."
  fi
fi

if flow_enabled tdd && flow_tdd; then
  if flow_is_test "$rel" "$TDD_TESTS"; then
    [ "$TDD_PHASE" = green ] && pre_decide deny "flow tdd: '$rel' is a test, and slice $TDD_ID is in green, so tests are locked. Make the code pass the test as written. If the test itself is wrong, go back to red (task.sh tdd $TDD_ID red); green then needs a fresh failing run."
  else
    [ "$TDD_PHASE" = red ] && pre_decide deny "flow tdd: slice $TDD_ID is in red, so only tests are editable, and '$rel' is not a test (the slice's tests: globs set what counts). Run the test until it fails for the right reason (evidence.sh $TDD_ID:red), then task.sh tdd $TDD_ID green."
  fi
fi

if flow_enabled fence && [ -f "$FLOW_TASK_DIR/SLICES.md" ]; then
  IFS=$'\t' read -r slice srepo fence <<<"$(awk '
    function out() { if (d && f != "") { printf "%s\t%s\t%s\n", h, (r == "" ? "-" : r), f; exit } }
    /^## / { out(); h = $0; sub(/^## /, "", h); sub(/ .*/, "", h); f = ""; r = ""; d = 0 }
    /^fence:/ { f = $0; sub(/^fence:[[:space:]]*/, "", f); sub(/[[:space:]]*#.*/, "", f) }
    /^repo:/ { r = $0; sub(/^repo:[[:space:]]*/, "", r); sub(/[[:space:]]*#.*/, "", r) }
    /^status: doing/ { d = 1 }
    END { out() }' "$FLOW_TASK_DIR/SLICES.md")"
  if [ -n "$fence" ]; then
    [ "$srepo" = - ] && srepo=""   # "-" keeps read from collapsing an empty field
    want="${srepo:-$(flow_repo_name "$FLOW_TASK_HOME")}"
    if [ "$erepo" != "$want" ]; then
      pre_decide deny "flow fence: slice $slice works in repo '$want'; '$rel' is in '$erepo'. If this repo needs a change, give it its own slice (repo: $erepo) in .flow/tasks/$FLOW_TASK/SLICES.md."
    fi
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
