#!/usr/bin/env bash
# down.sh: remove sandboxes a killed scenario left behind. Artifacts in .flow/artifacts/ stay.
set -euo pipefail
rm -rf "${TMPDIR:-/tmp}"/verify-flow-stack.* 2>/dev/null || true
echo "down: sandboxes removed"
