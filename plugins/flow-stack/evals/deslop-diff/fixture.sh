#!/usr/bin/env bash
set -e
. "$(dirname "$0")/../_lib/toy.sh"
toy_repo
cat > src/calc.sh <<'SH'
# This function adds two numbers together
add() { echo $(( $1 + $2 )); }

# mul: multiplies numbers
# This is a helper function that takes two arguments and multiplies them
mul() {
  # check that we have arguments (defensive)
  if [ -z "$1" ]; then
    echo "debug: first arg empty" >&2
  fi
  # compute the result
  local result
  result=$(( $1 * $2 ))
  # echo "result is $result"   # old debug line
  # return the result
  echo "$result"
}
SH
printf '. src/calc.sh\n[ "$(mul 2 3)" = 6 ] || exit 1\n[ "$(mul 4 5)" = 20 ] || exit 1\necho ok\n' > tests/test_mul.sh
