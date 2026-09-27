#!/usr/bin/env bash
set -e
. "$(dirname "$0")/../_lib/toy.sh"
toy_repo
toy_features
"$FLOW_PLUGIN/skills/flow/scripts/task.sh" new tweak feature >/dev/null
printf '# add: sum of two integers\n' >> src/calc.sh
