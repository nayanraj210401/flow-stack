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

intent "  - huge"; seals && bad "indented row sealed" || ok "row indented up to 3 spaces is a row"
intent "$(printf '```\n- empty → C1')"; seals && bad "unclosed fence hid rows" || ok "unclosed fence under Edge cases refused"
intent "$(printf '```\n~~~\n```\n- huge')"; seals && bad "~~~ closed a \`\`\` fence" || ok "fence closes only on its own marker"
printf '# Intent · x\n\n## Acceptance checks\n- [ ] C1 · works\n<!--\n- [ ] C3 · not real\n-->\n\n## Edge cases\n- huge → C3\n' >"$I"
seals && bad "check ID inside a comment counted" || ok "check IDs inside <!-- --> ignored"
printf '# Intent · x\n\n## Acceptance checks\n- [ ] C1 · works\n\n## Edge cases\n<!--\n- example\n-->\n- empty → C1\n' >"$I"
seals && ok "example row inside <!-- --> not a row" || bad "commented example refused: $(cat "$SB/out")"
for h in '##  Edge cases' '## Edge cases:'; do
  printf '# Intent · x\n\n## Acceptance checks\n- [ ] C1 · works\n\n%s\n- huge\n' "$h" >"$I"
  seals && bad "heading '$h' turned the gate off" || ok "heading '$h' normalised"
done

head='# Intent · x\n\n## Acceptance checks\n- [ ] C1 · works\n\n'
blocks() { printf "$head$1\n" >"$I"; seals && bad "$2 sealed" || ok "$2 refused"; }
blocks '## Edge cases\n- huge <!-- TODO -->' "row with a trailing comment"
blocks '## Edge cases\n- body "<!--" → C1\n- huge' "unclosed comment hiding later rows"
blocks '## Goal\n```sh\n## Edge cases\n- huge' "fence from an earlier section hiding the matrix"
blocks '## Edge cases ##\n- huge' "heading with closing hashes"
blocks '## Edge cases <!-- #187 -->\n- huge' "heading with a trailing comment"
blocks "## Edge cases\n- empty → C1\n\t- huge" "tab-indented nested row"
blocks '## Edge cases\n- empty → C1\n        - huge' "8-space nested row"
blocks '## Edge cases\nsome prose, not a row' "prose line in the matrix"
for h in '### Edge cases' ' ## Edge cases' '## Edge cases (v2)' '## Edge cases and limits'; do
  blocks "$h\n- huge" "heading variant '$h'"
done
blocks '## Edge cases\n- empty → C1 <!-- note\n- huge\n-->' "mid-line comment opener hiding rows"
blocks '## Edge cases\n    ```\n- huge' "4-space-indented fence hiding rows"
blocks '## Edge cases\n- empty → C1\n#huge' "#-prefixed paragraph in the matrix"
for h in '## Edge case' '## Edge-cases' '## Edgecases'; do
  blocks "$h\n- huge" "near-miss heading '$h'"
done
blocks '## Edge cases\n<!-- a --> <!--\n- huge\n-->' "comment opener after a closed comment"
blocks '## Edge cases\n- → C1' "row with no case text"
blocks '## Edge cases\n<!-->\n- huge →\n-->' "<!--> closes on its own line"
blocks '## Edge cases\n<!--->\n- huge →\n-->' "<!---> closes on its own line"
printf '# Intent · x\n\n## Acceptance checks\n- [ ] C1 · works\n\n## Goal\n<!-->\n\n# Edge cases\n- huge →\n<!-- end -->\n' >"$I"
seals && bad "<!--> outside the matrix hid an H1 matrix" || ok "<!--> outside the matrix closes on its own line"
printf "$head"'## Goal\n<!-->\n\n## Edge cases\n- huge → C1\n' >"$I"
seals && ok "<!--> before the matrix leaves a mapped row sealable" || bad "<!--> swallowed the heading: $(cat "$SB/out")"
blocks '## Edge  cases\n- huge' "double-spaced heading"
blocks '## Edge cases\n- empty → C1\n\n## Notes\nEdge cases\n----------\n- huge' "setext Edge cases heading"
blocks '## Edge cases\n- empty → C1\n\n## Notes\n<h2>Edge cases</h2>\n- huge' "html h2 Edge cases heading"
printf '# Intent · x\n\n## Non-goals\n- other edge cases in the lexer\n\n---\n\n## Acceptance checks\n- [ ] C1 · works\n' >"$I"
seals && ok "a --- rule after a list item that mentions edge cases is not a heading" || bad "rule refused: $(cat "$SB/out")"
printf "$head"'## Edge cases\n- huge → C1\n\n## Notes\nsee edge cases\n\n---\n' >"$I"
seals && ok "a --- rule after a blank line is not a heading" || bad "rule after blank refused: $(cat "$SB/out")"
for h in '## Edge cases:' '## Edge cases ##'; do
  printf "$head$h"'\n- huge → C1\n' >"$I"
  seals && ok "'$h' is the matrix: a mapped row seals" || bad "'$h' with a mapped row refused: $(cat "$SB/out")"
done
blocks '## Edge cases\n- empty → C1\n\n## Edge cases (security)\n- unauthorized →' "decorated second heading next to the exact one"
blocks '## Edge cases\n- empty → C1\n\n## Goal\n### Edge cases\n- huge' "### Edge cases inside another section"
blocks '## Edge cases\n<!-- note --> - huge →' "text after a one-line comment"
blocks '## Edge cases\n<!-- note\nmore --> - huge →' "text after a closing -->"
printf "$head"'## Edge cases\n- ≥10k rows → C1\n- “quoted” → C1\n' >"$I"
seals && ok "case text starting with a multi-byte character maps" || bad "multi-byte case refused: $(cat "$SB/out")"
printf '# Intent · fix edge case in parser\n\n## Acceptance checks\n- [ ] C1 · works\n' >"$I"
seals && ok "an H1 title mentioning an edge case seals as before" || bad "legacy title refused: $(cat "$SB/out")"
blocks '## Edge cases\n- empty → C1\n  ```\n- huge\n  ```' "fence indented under a row"
blocks '## Edge cases\n- empty → C1\n```x``` note\n- huge\n```' "backtick line that is not a fence"
for h in '## 3. Edge cases' '## **Edge cases**' '## `Edge cases`' '## The edge cases'; do
  blocks "$h\n- huge" "decorated heading '$h'"
done
printf "$head"'## Edge cases\n<!--\n```\n-->\n- empty → C1\n' >"$I"
seals && ok "fence marker inside a comment opens nothing" || bad "comment fence refused: $(cat "$SB/out")"
printf "$head"'## Edge cases\n- a→b transition → C1\n' >"$I"
seals && ok "arrow inside case text still maps" || bad "inner arrow refused: $(cat "$SB/out")"
printf '# Intent · x\n\n## Goal\n```sh\nno matrix here\n' >"$I"
seals && ok "unclosed fence without a matrix seals as before" || bad "no-matrix INTENT blocked: $(cat "$SB/out")"

[ "$FAILS" = 0 ] || { echo "== seal-matrix · FAIL ($FAILS)"; exit 1; }
echo "== seal-matrix · PASS"
