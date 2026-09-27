#!/usr/bin/env bash
set -e
. "$(dirname "$0")/../_lib/toy.sh"
toy_repo
"$FLOW_PLUGIN/skills/flow/scripts/task.sh" new sub feature >/dev/null
printf 'sub() { echo $(( $1 - $2 )); }\n' >> src/calc.sh
printf '. src/calc.sh\n[ "$(add 1 1)" = 2 ] || exit 1\necho ok\n' > tests/test_sub.sh
