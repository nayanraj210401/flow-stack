# shellcheck shell=bash
# Shared scaffold helpers for flow-stack evals. Source from a case's fixture.sh:
#   . "$(dirname "$0")/../_lib/toy.sh"
# Every function works in the current directory (the eval workspace).

FLOW_PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

toy_repo() {
  git init -q
  git config user.email eval@example.com
  git config user.name eval
  mkdir -p src tests
  printf 'add() { echo $(( $1 + $2 )); }\n' > src/calc.sh
  printf '. src/calc.sh\n[ "$(add 2 3)" = 5 ] || { echo "FAIL add: expected 5"; exit 1; }\necho "ok add"\n' > tests/test_add.sh
  printf '# calc\nA tiny bash calculator. Run tests with: bash tests/test_add.sh\n' > README.md
  git add -A && git commit -qm "initial calculator"
}

# toy_task <slug> <goal> <non-goal>: an active flow task with intent filled in
toy_task() {
  local slug="$1" goal="$2" nongoal="$3" d
  "$FLOW_PLUGIN/skills/flow/scripts/task.sh" new "$slug" feature >/dev/null
  d=".flow/tasks/$slug"
  cat > "$d/INTENT.md" <<INTENT
# Intent · $slug

## Goal
$goal

## Non-goals
- $nongoal

## Acceptance checks
- [ ] C1 · mul multiplies two integers · \`bash tests/test_mul.sh\`
INTENT
}

# toy_mul_check: the sealed acceptance check for mul (fails until mul exists)
toy_mul_check() {
  printf '. src/calc.sh\n[ "$(mul 2 3)" = 6 ] || { echo "FAIL mul: expected 6"; exit 1; }\n[ "$(mul 4 5)" = 20 ] || { echo "FAIL mul: expected 20"; exit 1; }\necho "ok mul"\n' > tests/test_mul.sh
  "$FLOW_PLUGIN/skills/seal/scripts/seal.sh" add tests/test_mul.sh >/dev/null
}

# toy_slice <slug> <id> <status> <check> <fence>
toy_slice() {
  cat > ".flow/tasks/$1/SLICES.md" <<SLICES
# Slices · $1

## $2 · mul
status: $3
check: $4
fence: $5
budget: 40
SLICES
}
