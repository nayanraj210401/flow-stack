#!/usr/bin/env bash
# routines.test.sh: the ready stamp travels as a flow/ready check run. A routine that pushes posts it on the self-heal
# PR head it stamped and marks that draft ready; a pull_request routine skips a head that has one. The steps are run
# from the rendered workflow against a fake gh.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/routines.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/repo/.github/routines" "$SB/bin" && cd "$SB/repo" && git init -q
cp "$H/../templates/self-heal.md" "$H/../templates/review.md" "$H/../templates/self-create.md" .github/routines/
echo '# profile' >.github/routines/profile.md
"$H/routines.sh" render >/dev/null || bad "render failed"
W=.github/workflows

step() { # step <workflow>: the run script of its flow/ready step
  awk '/^      - name: flow\/ready$/ { on = 1; next } on && !/^        / { exit } on && r { print substr($0, 11) } on && /^        run: \|$/ { r = 1 }' "$1"
}
cat >"$SB/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$SB/calls"
case "$1 $2" in
  "pr list") while [ "$1" != --jq ]; do shift; done; jq -r "$2" "$SB/prs.json" ;;
  "pr ready") ;;
  "api "*check-runs*) [ "$1 $2" = "api repos/o/r/check-runs" ] && { cat >>"$SB/posted"; exit; }
    case "$2" in *stamped*) echo 1 ;; *broken*) exit 1 ;; *) echo 0 ;; esac ;;
esac
EOF
chmod +x "$SB/bin/gh"
export SB PATH="$SB/bin:$PATH" GITHUB_REPOSITORY=o/r GITHUB_STEP_SUMMARY="$SB/summary" GITHUB_OUTPUT="$SB/out"

echo "-- rendered workflows"
grep -q '^  checks: write$' $W/flow-self-heal.yml && [ -n "$(step $W/flow-self-heal.yml)" ] && ok "self-heal posts flow/ready (checks: write)" || bad "self-heal has no flow/ready step"
grep -q "if: steps.stamp.outputs.skip != 'true'" $W/flow-review.yml && ok "review runs only without a passing flow/ready" || bad "review has no skip"
grep -q '^  checks: read$' $W/flow-self-create.yml && ! grep -q 'flow/ready' $W/flow-self-create.yml && ok "self-create: no flow/ready step, checks read" || bad "self-create grew a flow/ready step"
! grep -q '^$' $W/flow-self-create.yml && ok "an empty placeholder leaves no blank line" || bad "blank line in self-create"

echo "-- self-heal: post on the stamped self-heal head only, then mark it ready"
A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa C=cccccccccccccccccccccccccccccccccccccccc
cat >"$SB/prs.json" <<EOF
[{"number":5,"headRefOid":"$A","headRefName":"self-heal/5-x","isCrossRepository":false,"isDraft":true},
 {"number":6,"headRefOid":"bbbb","headRefName":"self-heal/6-y","isCrossRepository":false,"isDraft":true},
 {"number":7,"headRefOid":"$C","headRefName":"feature/z","isCrossRepository":false,"isDraft":true},
 {"number":8,"headRefOid":"$C","headRefName":"self-heal/8-z","isCrossRepository":true,"isDraft":true}]
EOF
mkdir -p .flow; printf 't1\t%s\treview\tship\tsecret note\nt2\t%s\tready\tpass\t\nt3\tbbbb\treview\tfix-first\t\nt4\t%s\tready\tpass\t\n' "$A" "$A" "$C" >.flow/ready.tsv
bash -eo pipefail -c "$(step $W/flow-self-heal.yml)" || bad "step failed"
[ "$(jq -s length "$SB/posted")" = 1 ] && [ "$(jq -r .head_sha "$SB/posted")" = "$A" ] && ok "one flow/ready, on #5's head" || bad "posted: $(cat "$SB/posted")"
jq -e '.name == "flow/ready" and .conclusion == "success" and (.output.summary | test("review ship") and (test("secret") | not))' "$SB/posted" >/dev/null && ok "summary holds the ready rows, not their notes" || bad "summary: $(jq -r .output.summary "$SB/posted")"
[ "$(grep -c '^gh pr ready' "$SB/calls")" = 1 ] && grep -q '^gh pr ready 5$' "$SB/calls" && ok "#5 marked ready, nothing else" || bad "calls: $(grep 'pr ready' "$SB/calls")"
rm .flow/ready.tsv "$SB/posted"; bash -eo pipefail -c "$(step $W/flow-self-heal.yml)" && [ ! -f "$SB/posted" ] && ok "no ledger: nothing posted" || bad "posted without a ledger"

echo "-- review: skip a stamped head, review a new or unknown one"
for c in stamped:true fresh: broken:; do
  : >"$SB/out"; SHA="${c%%:*}" bash -eo pipefail -c "$(step $W/flow-review.yml)" || bad "$c: step failed"
  [ "$(sed -n 's/^skip=//p' "$SB/out")" = "${c#*:}" ] && ok "${c%%:*} head: skip='${c#*:}'" || bad "${c%%:*}: out '$(cat "$SB/out")'"
done

echo "-- routine contracts"
grep -q 'More than 2 means two rework rounds' "$H/../templates/self-heal.md" && grep -q 'add `needs-human`' "$H/../templates/self-heal.md" && ok "rework capped at 2 rounds, then needs-human" || bad "self-heal has no rework cap"
grep -q 'never push to any other PR' "$H/../templates/self-heal.md" && ok "rework only on PRs self-heal opened" || bad "no own-PR rule"
grep -q 'gh pr ready <n> --undo`, then `gh pr edit <n> --add-label rework`' "$H/../templates/review.md" && ok "review sends blocked factory PRs to rework" || bad "review has no rework path"

[ "$FAILS" = 0 ] && echo "routines.test.sh: pass" || { echo "routines.test.sh: $FAILS failed"; exit 1; }
