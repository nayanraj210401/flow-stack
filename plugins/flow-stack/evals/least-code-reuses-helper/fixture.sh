#!/usr/bin/env bash
set -e
. "$(dirname "$0")/../_lib/toy.sh"
toy_repo
mkdir -p lib
for h in dates numbers paths; do printf "# %s helpers\n%s_noop() { :; }\n" "$h" "$h" > lib/$h.sh; done
cat > lib/strings.sh <<'SH'
# slugify "Hello World!" -> hello-world
slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//'; }
SH
cat > src/export.sh <<'SH'
export_csv() { printf 'id,title\n'; }
SH
git add -A && git commit -qm "export"
