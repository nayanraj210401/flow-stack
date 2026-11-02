#!/usr/bin/env bash
# up.sh: flow-stack has no server. "Up" = the tools the plugin and this driver need are
# present, and the working-tree plugin parses. Idempotent. Prints the plugin root.
set -euo pipefail
REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
PLUGIN="$REPO/plugins/flow-stack"
miss=0
for t in bash git jq perl shasum python3 curl; do command -v "$t" >/dev/null || { echo "up: missing $t" >&2; miss=1; }; done
command -v claude >/dev/null || echo "up: claude CLI not found; plugin.install skips manifest validation" >&2
[ "$miss" = 0 ] || exit 1
find "$PLUGIN" -name '*.sh' -print0 | xargs -0 -n1 bash -n
jq empty "$PLUGIN/hooks/hooks.json" "$PLUGIN/.claude-plugin/plugin.json" "$REPO/.claude-plugin/marketplace.json"
FLOW_MAIN_DIR="$(dirname "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)")"
mkdir -p "$FLOW_MAIN_DIR/.flow/artifacts"
echo "$PLUGIN"
