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
    run() { jq -nc --arg a "$1" --arg t "$2" '{check_runs: [{app: {slug: $a}, conclusion: "success", output: {title: $t}}]}'; }
    case "$2" in */stamped/*) j="$(run github-actions "ready.sh stamped this commit")" ;; */named/*) j="$(run github-actions "a job")" ;;
      */other-app/*) j="$(run evil "ready.sh stamped this commit")" ;; */broken/*) exit 1 ;; *) j='{"check_runs":[]}' ;; esac
    jq -r "$4" <<<"$j" ;;
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
for c in stamped:true fresh: broken: named: other-app:; do
  : >"$SB/out"; SHA="${c%%:*}" bash -eo pipefail -c "$(step $W/flow-review.yml)" || bad "$c: step failed"
  [ "$(sed -n 's/^skip=//p' "$SB/out")" = "${c#*:}" ] && ok "${c%%:*} head: skip='${c#*:}'" || bad "${c%%:*}: out '$(cat "$SB/out")'"
done

echo "-- routine contracts"
grep -q 'More than 2 means two rework rounds' "$H/../templates/self-heal.md" && grep -q 'add `needs-human`' "$H/../templates/self-heal.md" && ok "rework capped at 2 rounds, then needs-human" || bad "self-heal has no rework cap"
grep -q 'never push to any other PR' "$H/../templates/self-heal.md" && ok "rework only on PRs self-heal opened" || bad "no own-PR rule"
grep -q 'gh pr ready <n> --undo`, then `gh pr edit <n> --add-label rework`' "$H/../templates/review.md" && ok "review sends blocked factory PRs to rework" || bad "review has no rework path"
am="$(git -C "$H" rev-parse --show-toplevel)/.github/routines/auto-merge.md"
if [ -f "$am" ]; then
  grep -q '`self-create` alone, or a `heal-ok` a bot applied, never counts' "$am" && grep -q 'last `labeled` event for `heal-ok`' "$am" && ok "auto-merge: a self-heal PR needs a human heal-ok" || bad "auto-merge takes self-create alone"
  grep -q 'also for a PR with `flow/ready`' "$am" && ok "auto-merge still reviews a stamped PR itself" || bad "auto-merge trusts the self-written stamp"
fi

echo "-- triage: renders without push or PR power; a safety path scores risk:high"
"$H/routines.sh" add triage >/dev/null || bad "add triage failed"
tw=$W/flow-triage.yml
grep -q '^  issues: write$' $tw && grep -q '^  contents: read$' $tw && grep -q '^  pull-requests: read$' $tw && grep -q 'github_token: ${{ github.token }}' $tw &&
  grep -q -- ' --auto Run the routine' $tw && ok "triage writes only issues, with github.token, in plain --auto" || bad "triage can push or open PRs"
grep -q 'size:S size:M size:L risk:low' $tw && ok "triage creates its labels" || bad "triage labels missing"
cmp -s .github/routines/safety-paths.txt "$H/../templates/safety-paths.txt" && ok "add writes the default safety list" || bad "no safety list written"
"$H/routines.sh" safety src/app.sh docs/a.md >/dev/null && ok "ordinary paths pass" || bad "ordinary path flagged"
for p in .github/workflows/x.yml a/b/CLAUDE.md sub/.claude/agents/x.md settings.local.json '"odd\303"'; do
  "$H/routines.sh" safety src/app.sh "$p" >/dev/null; [ $? = 1 ] && ok "safety flags $p" || bad "safety missed $p"
done
zo="$(printf 'src/a\0x/.flow/run.sh\0' | "$H/routines.sh" safety -z)"; [ $? = 1 ] && [ "$zo" = "$(printf 'x/.flow/run.sh\t*/.flow/*')" ] && ok "-z reads NUL-separated paths" || bad "-z missed a hit"
git add -A && git -c user.email=t@t -c user.name=t commit -qm base && base="$(git rev-parse HEAD)" && git switch -qc pr
echo '/nothing/*' >.github/routines/safety-paths.txt
"$H/routines.sh" safety .github/x.yml >/dev/null && "$H/routines.sh" safety --ref "$base" .github/x.yml >/dev/null; [ $? = 1 ] &&
  ok "--ref reads the base branch's list, not the PR's" || bad "a PR shortened its own safety list"
"$H/routines.sh" safety --ref nope x >/dev/null 2>&1; [ $? = 2 ] && ok "a bad --ref is an error, not a pass" || bad "bad --ref passed"
"$H/routines.sh" safety --ref '' .github/x.yml >/dev/null 2>&1; [ $? = 2 ] && ok "an empty --ref is an error" || bad "empty --ref read the working tree"
printf '' | "$H/routines.sh" safety -z >/dev/null 2>&1; [ $? = 2 ] && printf '\n' | "$H/routines.sh" safety >/dev/null 2>&1; [ $? = 2 ] &&
  ok "no paths (a failed git diff upstream) is an error, not clean" || bad "empty input passed"
tt="$H/../templates/triage.md"
grep -q 'routines.sh safety <files>` exits non-zero |$' "$tt" && grep -q '\*\*risk:high is never built.\*\* Add `needs-human`, and put a draft INTENT' "$tt" &&
  ok "triage: a safety path is risk:high, which gets a draft INTENT and needs-human" || bad "triage contract"
grep -q 'When `.github/routines/triage.md` exists' "$H/../templates/self-heal.md" && grep -q '`risk:high` is never built' "$H/../templates/self-heal.md" &&
  grep -q 'triage miss: predicted' "$H/../templates/self-heal.md" && ok "self-heal: triage picks, never high, re-scores the diff" || bad "self-heal ignores triage"

echo "-- one safety list"
sp="$(git -C "$H" rev-parse --show-toplevel)/.github/routines/safety-paths.txt"
if [ -f "$am" ] && [ -f "$sp" ]; then
  grep -q 'origin/<base>...FETCH_HEAD | make-routines/scripts/routines.sh safety -z --ref origin/<base>' "$am" && grep -q '`.github/routines/safety-paths.txt`' "$am" && ok "auto-merge reads the safety list" || bad "auto-merge doesn't read the list"
  ! grep -qE 'plugins/flow-stack/(hooks|agents)/|`\.mcp\.json`|`make-gates/`' "$am" && ok "auto-merge has no path list of its own" || bad "auto-merge still lists paths in prose"
  diff <(grep -v '^#' "$H/../templates/safety-paths.txt") <(head -n "$(grep -vc '^#' "$H/../templates/safety-paths.txt")" < <(grep -v '^#' "$sp")) >/dev/null &&
    ok "this repo's list starts with the plugin default" || bad "this repo's list dropped a default glob"
  cd "$(dirname "$sp")/../.."
  for p in plugins/flow-stack/hooks/guard.sh plugins/flow-stack/skills/feature-map/scripts/features.sh README.md plugins/flow-stack/skills/make-routines/templates/triage.md; do
    "$H/routines.sh" safety "$p" >/dev/null; [ $? = 1 ] && ok "this repo flags $p" || bad "this repo missed $p"
  done
  "$H/routines.sh" safety plugins/flow-stack/skills/brief/SKILL.md >/dev/null && ok "this repo passes a plain skill doc" || bad "brief/SKILL.md flagged"
fi

[ "$FAILS" = 0 ] && echo "routines.test.sh: pass" || { echo "routines.test.sh: $FAILS failed"; exit 1; }
