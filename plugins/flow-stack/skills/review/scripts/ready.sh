#!/usr/bin/env bash
# ready.sh: the "ready for review" bar. Human review is the most expensive step in the loop,
# so a PR reaches a human only after this passes for its exact HEAD.
#   ready.sh [--base <ref>]                  run the bar; on pass, stamp HEAD in .flow/ready.tsv
#   ready.sh record <kind> <result> [note]   record a model-judged step for HEAD:
#                                            review ship|fix-first|rethink · deslop done · tour done
#                                            · <id> done for a repo `do` step (below)
#   ready.sh stamped [<sha>]                 exit 0 if <sha> (default HEAD) has a pass stamp
#   ready.sh mode                            on | yolo  (repo .flow/config.json > profile > on)
# Live checks: clean tree, lint + typecheck (config commands), impacted feature scenarios,
# and with an active flow task: acceptance checks, seals, blind checks.
# Repo quality gates: .flow/config.json "ready": [{"id","run":"<cmd>"} | {"id","do":"<step>"}].
# A run entry is a live check; a do entry (an MCP scan, a manual script) needs `record <id> done`.
# The guard hook denies a non-draft `gh pr create` and `gh pr ready` without a stamp.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../../../hooks/roots.sh"; flow_roots; flow_task
sk="$here/../.."
ledger="$FLOW_DIR/ready.tsv"
profile="${FLOW_STACK_HOME:-$HOME/.flow-stack}/profile.md"
sha() { git -C "$FLOW_ROOT" rev-parse "${1:-HEAD}" 2>/dev/null; }

mode() {
  local v; v="$(jq -r '.review_gate // empty' "$FLOW_DIR/config.json" 2>/dev/null)"
  [ -n "$v" ] || v="$(sed -n 's/^review_gate:[[:space:]]*\([a-z]*\).*/\1/p' "$profile" 2>/dev/null | head -n1)"
  printf '%s\n' "${v:-on}"
}
custom() { # custom [<do-id>]: the repo's ready entries as id<TAB>run|do<TAB>body, or test one do id
  if [ -n "${1:-}" ]; then jq -e --arg k "$1" '.ready // [] | any(.id == $k and has("do"))' "$FLOW_DIR/config.json" >/dev/null 2>&1; return; fi
  jq -r '.ready // [] | .[] | select(.id) | [.id, (if .run then "run" else "do" end), (.run // .do // "")] | @tsv' "$FLOW_DIR/config.json" 2>/dev/null
}
latest() { awk -F'\t' -v s="$1" -v k="$2" '$2 == s && $3 == k { r = $4 } END { print r }' "$ledger" 2>/dev/null; }

case "${1:-}" in
  mode) mode; exit 0 ;;
  stamped) [ "$(latest "$(sha "${2:-HEAD}")" ready)" = pass ]; exit ;;
  record)
    kind="${2:-}"; res="${3:-}"
    case "$kind:$res" in
      review:ship|review:fix-first|review:rethink|deslop:done|tour:done) ;;
      *:done) custom "$kind" || { echo "ready.sh: '$kind' is not a do entry in .flow/config.json ready[]" >&2; exit 2; } ;;
      *) echo "usage: ready.sh record review ship|fix-first|rethink | deslop done | tour done | <do-id> done [note]" >&2; exit 2 ;;
    esac
    mkdir -p "$FLOW_DIR"
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$(sha)" "$kind" "$res" "$(printf '%s' "${4:-}" | tr '\t\n' '  ')" >>"$ledger"
    echo "recorded $kind=$res for $(sha | cut -c1-7)"; exit 0 ;;
esac

base=""; [ "${1:-}" = --base ] && base="${2:-}"
if [ "$(mode)" = yolo ]; then echo "review gate: yolo; nothing to check, PRs go straight to review"; exit 0; fi
if [ -z "$base" ]; then
  for ref in origin/HEAD origin/main origin/master main master; do
    git -C "$FLOW_ROOT" rev-parse -q --verify "$ref" >/dev/null && { base="$(git -C "$FLOW_ROOT" merge-base HEAD "$ref")"; break; }
  done
fi
head="$(sha)"; fails=0
pass() { echo "  ✓ $*"; }
miss() { echo "  ✗ $*"; fails=$((fails + 1)); }
run() { # run <label> <cmd>: through evidence.sh so an active task records it
  ( cd "$FLOW_ROOT" && "$sk/verify/scripts/evidence.sh" "$1" "$2" >/dev/null 2>&1 )
}
echo "ready for review? $(echo "$head" | cut -c1-7)${base:+ vs $(echo "$base" | cut -c1-7)}"

if [ -n "$(git -C "$FLOW_ROOT" status --porcelain 2>/dev/null | grep -v ' \.flow/' || true)" ]; then
  miss "clean tree: uncommitted changes aren't in the PR; commit or stash them"
else pass "clean tree"; fi

for c in lint typecheck; do
  cmd="$(jq -r --arg c "$c" '.commands[$c] // empty' "$FLOW_DIR/config.json" 2>/dev/null)"
  [ -n "$cmd" ] || continue
  if run "ready:$c" "$cmd"; then pass "$c"; else miss "$c fails: $cmd"; fi
done

while IFS=$'\t' read -r id kind body; do
  if [ "$kind" = run ]; then
    if run "ready:$id" "$body"; then pass "$id"; else miss "$id fails: $body"; fi
  elif [ "$(latest "$head" "$id")" = done ]; then pass "$id"
  else miss "$id: not done for this HEAD. $body, then: ready.sh record $id done"; fi
done < <(custom)

if [ -d "$FLOW_DIR/features" ] && [ -n "$base" ]; then
  out="$(cd "$FLOW_ROOT" && "$sk/feature-map/scripts/features.sh" run --impacted --base "$base" 2>&1 || true)"
  bad_f="$(grep -E '· (FAIL|BROKEN)' <<<"$out" | sed 's/^feat://; s/ ·.*//' | tr '\n' ' ')"
  n="$(grep -c '^feat:.* · PASS' <<<"$out" || true)"
  if [ -n "$bad_f" ]; then miss "impacted feature scenarios fail: $bad_f"; else pass "impacted feature scenarios ($n passed)"; fi
fi

task="$FLOW_TASK"
td="$FLOW_TASK_DIR"
if [ -n "$task" ] && [ -f "$td/INTENT.md" ]; then
  while IFS=$'\t' read -r id cmd; do
    if run "$id" "$cmd"; then pass "$id acceptance check"; else miss "$id acceptance check fails: $cmd"; fi
  done < <(sed -n 's/^- \[.\] \(C[0-9][0-9]*\) · .*`\([^`]*\)`[[:space:]]*$/\1	\2/p' "$td/INTENT.md")
  if [ -s "$td/SEALS" ]; then
    if ( cd "$FLOW_ROOT" && "$sk/seal/scripts/seal.sh" verify >/dev/null 2>&1 ); then pass "seals intact"; else miss "a sealed check changed (seal.sh verify)"; fi
  fi
  if [ -f "$td/blind/MANIFEST" ]; then
    if ( cd "$FLOW_ROOT" && "$sk/verify/scripts/blind-run.sh" >/dev/null 2>&1 ); then pass "blind checks"; else miss "blind checks fail"; fi
  fi
fi

r="$(latest "$head" review)"
case "$r" in
  ship) pass "review: ship" ;;
  "") miss "review: none for this HEAD (run the review skill; it records its verdict)" ;;
  *) miss "review: $r (fix the blockers, then review again)" ;;
esac
[ -n "$(latest "$head" deslop)" ] && pass "deslop" || miss "deslop: not run on this HEAD"
[ -n "$(latest "$head" tour)" ] && pass "tour for the PR body" || miss "tour: none for this HEAD (the human reviewer needs it)"

if [ "$fails" -eq 0 ]; then
  mkdir -p "$FLOW_DIR"
  printf '%s\t%s\tready\tpass\t%s\n' "$(date -u +%FT%TZ)" "$head" "${base:-}" >>"$ledger"
  echo "ready for review: $(echo "$head" | cut -c1-7) stamped"; exit 0
fi
echo "not ready: $fails missing (a draft PR is fine meanwhile: gh pr create --draft)"; exit 1
