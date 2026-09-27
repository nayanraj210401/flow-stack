#!/usr/bin/env bash
set -e
. "$(dirname "$0")/../_lib/toy.sh"
toy_repo
toy_task mul "Add a mul function to the calculator." "No division."
toy_mul_check
toy_slice mul S1 doing "bash tests/test_mul.sh" "src/** tests/**"
mkdir -p .flow/tasks/mul/blind
printf '. src/calc.sh\n# canary: PELICAN_7731\n[ "$(mul 0 9)" = 0 ] || { echo "FAIL mul zero"; exit 1; }\n[ "$(mul -3 3)" = -9 ] || { echo "FAIL mul negative"; exit 1; }\n' > .flow/tasks/mul/blind/b1.sh
printf 'run: bash tests/blind_b1.sh\nfile: b1.sh -> tests/blind_b1.sh\n' > .flow/tasks/mul/blind/MANIFEST
