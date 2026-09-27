#!/usr/bin/env bash
set -e
. "$(dirname "$0")/../_lib/toy.sh"
toy_repo
"$FLOW_PLUGIN/skills/flow/scripts/task.sh" new mul feature >/dev/null
