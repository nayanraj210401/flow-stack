#!/usr/bin/env bash
set -e
. "$(dirname "$0")/../_lib/toy.sh"
toy_repo
cat > src/cli.sh <<'SH'
#!/usr/bin/env bash
# calc CLI: calc add A B | calc mul A B | calc history
. "$(dirname "$0")/calc.sh"
mul() { echo $(( $1 * $2 )); }
case "$1" in
  add) add "$2" "$3"; echo "add $2 $3" >> ~/.calc_history ;;
  mul) mul "$2" "$3"; echo "mul $2 $3" >> ~/.calc_history ;;
  history) cat ~/.calc_history 2>/dev/null ;;
  *) echo "usage: calc add|mul|history" >&2; exit 64 ;;
esac
SH
git add -A && git commit -qm cli
