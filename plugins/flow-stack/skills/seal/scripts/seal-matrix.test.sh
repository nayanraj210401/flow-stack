#!/usr/bin/env bash
# seal-matrix.test.sh: `seal.sh add` refuses while an INTENT edge-case row maps to neither a check nor a non-goal (#187).
set -uo pipefail
S="$(cd "$(dirname "$0")" && pwd)/seal.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/seal-matrix.XXXXXX")"; SB="$(cd "$SB" && pwd -P)"
trap 'rm -rf "$SB"' EXIT
export FLOW_STACK_HOME="$SB/home" CLAUDE_CONFIG_DIR="$SB/claude" FLOW_CLAUDE_JSON="$SB/claude.json"
mkdir -p "$FLOW_STACK_HOME" "$CLAUDE_CONFIG_DIR/sessions" "$SB/repo"
cd "$SB/repo" && git init -q && git config user.email a@b && git config user.name a
mkdir -p .flow/tasks/x; echo x >.flow/ACTIVE; echo hi >t.sh
git add -A && git commit -qm i
I=.flow/tasks/x/INTENT.md
intent() { printf '# Intent · x\n\n## Acceptance checks\n- [ ] C1 · works · `bash t.sh`\n- [ ] C2 · empty input · `bash t.sh`\n\n## Edge cases\n<!-- example, not a row:\n     - empty → C1 -->\n%s\n\n## Open questions\n- huge?\n' "$1" >"$I"; }
seals() { rm -f .flow/tasks/x/SEALS; "$S" add t.sh >"$SB/out" 2>&1; }

printf '# Intent · x\n\n## Acceptance checks\n- [ ] C1 · works · `bash t.sh`\n' >"$I"
seals && ok "no matrix: seals as today" || bad "no matrix blocked: $(cat "$SB/out")"
rm -f "$I"; seals && ok "no INTENT.md: seals as today" || bad "no INTENT.md blocked"
intent ""; seals && ok "empty matrix (template comment only): seals" || bad "empty matrix blocked: $(cat "$SB/out")"

intent "- empty → C2
- huge → "
if seals; then bad "unmapped row sealed"; else ok "unmapped row blocks seal"; fi
grep -q 'huge' "$SB/out" && ok "refusal names the row" || bad "row not named: $(cat "$SB/out")"
grep -q 'empty' "$SB/out" && bad "mapped row reported as unmapped" || ok "mapped row not reported"
[ -s .flow/tasks/x/SEALS ] && bad "SEALS written despite refusal" || ok "nothing sealed on refusal"

intent "- empty → C2
- huge — 10k rows · ünicode → C1, C2"; seals && ok "adding a check lets it seal" || bad "check mapping blocked: $(cat "$SB/out")"
intent "- empty → C2
- huge → non-goal: inputs are capped upstream"; seals && ok "adding a non-goal lets it seal" || bad "non-goal blocked: $(cat "$SB/out")"

intent "- huge → non-goal:"; seals && bad "non-goal with no reason sealed" || ok "non-goal needs a reason"
intent "- huge → C9"; seals && bad "unknown check ID sealed" || ok "check ID must exist in Acceptance checks"
printf '## Acceptance checks\r\n- [ ] C1 · works\r\n## Edge cases  \r\n- huge → \r\n- empty → C1\r\n' >"$I"
if seals; then bad "CRLF matrix with an unmapped row sealed"; else ok "CRLF / trailing-space heading still enforced"; fi
grep -q 'empty' "$SB/out" && bad "CRLF mapped row reported" || ok "CRLF mapped row accepted"
intent "- huge"; seals && bad "row with no arrow sealed" || ok "row with no mapping at all blocks"

for row in '* huge' '+ huge' '1. huge' '2) huge' "$(printf -- '-\thuge')"; do
  intent "$row"; seals && bad "bullet style '$row' sealed unmapped" || ok "bullet style '$row' is a row"
done
printf '# Intent · x\n\n## Acceptance checks\n- [ ] C1 · works\n\n## Edge Cases\n- huge\n' >"$I"
seals && bad "'## Edge Cases' heading skipped" || ok "heading matched case-insensitively"
printf '# Intent · x\n\n## Acceptance checks\n- [ ] C1 · works\n\n## Edge cases\n```\n## Acceptance checks\n```\n- huge\n' >"$I"
seals && bad "fenced heading switched sections" || ok "headings inside code fences ignored"

[ "$FAILS" = 0 ] || { echo "== seal-matrix · FAIL ($FAILS)"; exit 1; }
echo "== seal-matrix · PASS"
