#!/usr/bin/env bash
# slice.todo: task.sh todo turns SLICES.md into todo-list lines; the doing slice expands into its loop steps.
. "$(dirname "$0")/lib.sh"; sandbox slice.todo
T="$S/flow/scripts/task.sh"
toy_task demo "mul multiplies" "no division"
cat > .flow/tasks/demo/SLICES.md <<'SL'
# Slices · demo

## S1 · delete dead helper
status: done
check: bash tests/test_add.sh
fence: src/**
red: n/a behavior-preserving
teeth: n/a behavior-preserving

## S2 · mul
status: doing
check: bash tests/test_mul.sh
fence: src/calc.sh tests/**

## S3 · div guard
status: todo
check: bash tests/test_div.sh
fence: src/calc.sh
teeth: n/a guard only
SL
out="$("$T" todo 2>&1)" || bad "task.sh todo exited non-zero: $out"
echo "$out" | sed 's/^/    /'
has "$out" "[x] S1 · delete dead helper" && ok "done slice is checked" || bad "S1 line"
has "$out" "[>] S2 · mul" && ok "doing slice is marked in progress" || bad "S2 line"
has "$out" "[ ] S3 · div guard" && ok "todo slice is open" || bad "S3 line"
has "$out" "S2:before" && ok "doing slice expands: red run" || bad "no red step"
has "$out" "probe.sh S2" && ok "doing slice expands: probe" || bad "no probe step"
has "$out" "task.sh slice S2 done" && ok "doing slice expands: gated done" || bad "no done step"
[ "$(grep -c 'S3:before\|probe.sh S3' <<<"$out")" = 0 ] && ok "only the doing slice expands" || bad "S3 expanded"
echo "-- no slices yet → says so"
printf '# Slices · demo\n' > .flow/tasks/demo/SLICES.md
sees "empty SLICES.md is reported" "no slices" "$T" todo
finish
