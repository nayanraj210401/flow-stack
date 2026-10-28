#!/usr/bin/env bash
set -e
. "$(dirname "$0")/../_lib/toy.sh"
toy_repo
printf 'div() { echo $(( $1 / $2 )); }\n' >>src/calc.sh
git add -A && git commit -qm "div"
toy_task mul "mul multiplies two integers from the shell" "no input validation: callers pass integers"
toy_mul_check
git add -A && git commit -qm "mul task and sealed check"
printf 'mul() { echo $(( $1 * $2 )); }\n' >>src/calc.sh
