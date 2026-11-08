#!/usr/bin/env bash
# ready-check.test.sh: the ready stamp travels as a flow/ready check run. A routine that pushes posts it on the self-heal
# PR head it stamped and marks that draft ready; review still runs on a stamped head. The steps are run
# from the rendered workflow against a fake gh.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
FAILS=0
PASSES=0
ok()  { PASSES=$((PASSES + 1)); }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/routines.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/repo/.github/routines" "$SB/bin" && cd "$SB/repo" && git init -q
cp "$H/../templates/self-heal.md" "$H/../templates/review.md" "$H/../templates/self-create.md" .github/routines/
# auto-merge pushes (contents) but isn't self-heal: it must not post flow/ready. It is this repo's routine, not a template.
am="$(git -C "$H" rev-parse --show-toplevel)/.github/routines/auto-merge.md"
cp "$am" .github/routines/ || bad "no $am"
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

# -- rendered workflows
grep -q '^  checks: write$' $W/flow-self-heal.yml && [ -n "$(step $W/flow-self-heal.yml)" ] && ok "self-heal posts flow/ready (checks: write)" || bad "self-heal has no flow/ready step"
! grep -q 'steps.stamp' $W/flow-review.yml && ok "review also runs on a stamped self-heal head" || bad "review still skips a stamped head"
grep -q '^  checks: read$' $W/flow-self-create.yml && ! grep -q 'flow/ready' $W/flow-self-create.yml && ok "self-create: no flow/ready step, checks read" || bad "self-create grew a flow/ready step"
grep -q '^  checks: read$' $W/flow-auto-merge.yml && ! grep -q 'flow/ready' $W/flow-auto-merge.yml && ok "auto-merge (contents, not self-heal): no flow/ready step, checks read" || bad "auto-merge posts flow/ready"
! grep -q '^$' $W/flow-self-create.yml && ok "an empty placeholder leaves no blank line" || bad "blank line in self-create"

# -- self-heal: post on the stamped self-heal head only, then mark it ready
A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa C=cccccccccccccccccccccccccccccccccccccccc
cat >"$SB/prs.json" <<EOF
[{"number":5,"headRefOid":"$A","headRefName":"self-heal/5-x","isCrossRepository":false,"isDraft":true,"author":{"is_bot":true}},
 {"number":6,"headRefOid":"bbbb","headRefName":"self-heal/6-y","isCrossRepository":false,"isDraft":true,"author":{"is_bot":true}},
 {"number":7,"headRefOid":"$C","headRefName":"feature/z","isCrossRepository":false,"isDraft":true,"author":{"is_bot":true}},
 {"number":8,"headRefOid":"$C","headRefName":"self-heal/8-z","isCrossRepository":true,"isDraft":true,"author":{"is_bot":true}},
 {"number":9,"headRefOid":"$A","headRefName":"self-heal/9-h","isCrossRepository":false,"isDraft":true,"author":{"is_bot":false}}]
EOF
mkdir -p .flow; printf 't1\t%s\treview\tship\tsecret note\nt2\t%s\tready\tpass\t\nt3\tbbbb\treview\tfix-first\t\nt4\t%s\tready\tpass\t\n' "$A" "$A" "$C" >.flow/ready.tsv
bash -eo pipefail -c "$(step $W/flow-self-heal.yml)" || bad "step failed"
[ "$(jq -s length "$SB/posted")" = 1 ] && [ "$(jq -r .head_sha "$SB/posted")" = "$A" ] && ok "one flow/ready, on #5's head" || bad "posted: $(cat "$SB/posted")"
jq -e '.name == "flow/ready" and .conclusion == "success" and (.output.summary | test("review ship") and (test("secret") | not))' "$SB/posted" >/dev/null && ok "summary holds the ready rows, not their notes" || bad "summary: $(jq -r .output.summary "$SB/posted")"
[ "$(grep -c '^gh pr ready' "$SB/calls")" = 1 ] && grep -q '^gh pr ready 5$' "$SB/calls" && ok "#5 marked ready, nothing else" || bad "calls: $(grep 'pr ready' "$SB/calls")"
rm .flow/ready.tsv "$SB/posted"; bash -eo pipefail -c "$(step $W/flow-self-heal.yml)" && [ ! -f "$SB/posted" ] && ok "no ledger: nothing posted" || bad "posted without a ledger"

# -- routine contracts
grep -q 'labelled `needs-human`: leave it' "$H/../templates/self-heal.md" && grep -q 'is .CONFLICTING.: .git fetch origin' "$H/../templates/self-heal.md" && ok "needs-human PRs are skipped; merge only on a conflict" || bad "pickup loops or merges needlessly"
grep -q 'CONFLICTING' "$H/../templates/self-heal.md" && grep -q 'never force-push, never rebase' "$H/../templates/self-heal.md" && ok "self-heal reworks a merge conflict by merging, not rebasing" || bad "no conflict rework"
grep -q "startsWith(github.event.pull_request.head.ref, 'self-heal/')" $W/flow-review.yml && ! grep -q APP_TOKEN $W/flow-self-heal.yml && ok "review runs on self-heal drafts; no token juggling" || bad "review skips self-heal drafts"
grep -q 'first line is exactly `Verdict: ship`' "$H/../templates/review.md" && grep -q 'Verdict: fix' "$H/../templates/self-heal.md" && ok "review states, self-heal reads the Verdict: first line" || bad "verdict contract drifted"
grep -q 'More than 3 means three rework rounds' "$H/../templates/self-heal.md" && grep -q 'add `needs-human`' "$H/../templates/self-heal.md" && ok "rework capped at 3 rounds, then needs-human" || bad "self-heal has no rework cap"
grep -q 'never push to any other PR' "$H/../templates/self-heal.md" && ok "rework only on PRs self-heal opened" || bad "no own-PR rule"
grep -q 'comes from people' "$H/../templates/self-heal.md" && ! grep -q 'rework' "$H/../templates/review.md" && ok "review itself labels nothing; self-heal reads its verdict" || bad "review labels rework"
grep -q 'A `self-heal` PR goes back to its routine instead of being blocked' "$am" && ok "auto-merge sends a non-ship self-heal PR to rework" || bad "auto-merge has no rework path"
grep -q 'last `labeled` event for `auto-merge`' "$am" && ok "auto-merge: a human auto-merge label stays the default path" || bad "auto-merge lost its human label path"
# an unlabelled self-heal merge (1b) rests on an issue link the agent wrote, so it is opt-in, bound to the branch, and
# every issue self-heal can build from must be text a human approved (no edit or rename after heal-ok)
if grep -q 'heal-ok' "$am"; then
  grep -q '`auto_merge: low-risk`' "$am" && grep -q 'head branch starts with `self-heal/<i>-`' "$am" && grep -q 'lastEditedAt' "$am" &&
    ok "auto-merge: the heal-ok path is opt-in, branch-bound, and edit-checked" || bad "auto-merge trusts an agent-chosen issue link"
  b1="$(sed -n '/^## 1b\./,/^## 2\./p' "$am")"
  for bar in 'Filter first, re-score included' 'is `admin`, `maintain`, or `write`' 'exactly one `labeled` event for `heal-ok` and no `unlabeled`' 'no `labeled` event for `rework`' 'comes before the `heal-ok` approval' 'that a non-`User` added' '`reviewDecision` is not `CHANGES_REQUESTED`' 'every changed path appears in one of those rows' 'non-empty `scenario:`' 'check-runs?check_name=flow/ready' 'no HTML comment' 'link-reference comment'; do
    grep -qF "$bar" <<<"$b1" && ok "1b bar: $bar" || bad "1b lost a bar: $bar"
  done
  grep -qF 'For a step 1b PR, also run every 1b bullet' "$am" && ok "1b re-checked before the merge" || bad "1b not re-checked before the merge"
  grep -qF 'does the diff do what issue `<i>` asks' "$am" && ok "reviewer checks the diff fits the issue" || bad "reviewer never checks the diff fits the issue"
  for f in "$H/../templates/self-heal.md" "$(dirname "$am")/self-heal.md"; do
    grep -q 'lastEditedAt. is later than the approval' "$f" && grep -q "only comments created before the approval and never edited" "$f" && grep -qF "<!--" "$f" && grep -q renamed "$f" && ok "self-heal builds only human-approved text: $(basename "$(dirname "$f")")" || bad "self-heal builds an issue edited after heal-ok: $f"
  done
fi
grep -q 'also for a PR with a `flow/ready` check' "$am" && ok "auto-merge still reviews a stamped PR itself" || bad "auto-merge trusts the self-written stamp"

# -- triage: renders without push or PR power; a safety path scores risk:high
"$H/routines.sh" add triage >/dev/null || bad "add triage failed"
tw=$W/flow-triage.yml
grep -q '^  issues: write$' $tw && grep -q '^  contents: read$' $tw && grep -q '^  pull-requests: read$' $tw && grep -q 'github_token: ${{ github.token }}' $tw &&
  grep -q -- ' --auto Run the routine' $tw && ok "triage writes only issues, with github.token, in plain --auto" || bad "triage can push or open PRs"
grep -q 'size:S size:M size:L risk:low' $tw && ok "triage lists the labels it needs" || bad "triage labels missing"
cmp -s .github/routines/safety-paths.txt "$H/../templates/safety-paths.txt" && ok "add writes the default safety list" || bad "no safety list written"
"$H/routines.sh" safety src/app.sh docs/a.md >/dev/null && ok "ordinary paths pass" || bad "ordinary path flagged"
for p in .github/workflows/x.yml a/b/CLAUDE.md sub/.claude/agents/x.md settings.local.json '"odd\303"'; do
  "$H/routines.sh" safety src/app.sh "$p" >/dev/null; [ $? = 1 ] && ok "safety flags $p" || bad "safety missed $p"
done
zo="$(printf 'src/a\0x/.flow/run.sh\0' | "$H/routines.sh" safety -z)"; [ $? = 1 ] && [ "$zo" = "$(printf 'x/.flow/run.sh\t*/.flow/*')" ] && ok "-z reads NUL-separated paths" || bad "-z missed a hit"
git add -A && git -c user.email=t@t -c user.name=t commit -qm base && base="$(git rev-parse HEAD)" && git switch -qc pr
echo '/nothing/*' >.github/routines/safety-paths.txt
"$H/routines.sh" safety .github/x.yml >/dev/null; wt=$?
"$H/routines.sh" safety --ref "$base" .github/x.yml >/dev/null; rf=$?
[ "$wt" = 0 ] && [ "$rf" = 1 ] && ok "--ref reads the base branch's list, not the PR's" || bad "a PR shortened its own safety list (tree=$wt ref=$rf)"
mkdir -p deep/dir && (cd deep/dir && "$H/routines.sh" safety .github/x.yml >/dev/null); [ $? = 0 ] && ok "below the repo root it still reads the repo's own list" || bad "a subdirectory fell back to the plugin default"
printf 'src/a\n.github/x.yml' | "$H/routines.sh" safety --ref "$base" >/dev/null; [ $? = 1 ] && ok "a last line with no newline is still checked" || bad "unterminated last path skipped"
printf 'src/a\0.github/x.yml' | "$H/routines.sh" safety -z --ref "$base" >/dev/null; [ $? = 1 ] && ok "a last -z path with no NUL is still checked" || bad "unterminated last -z path skipped"
printf '\0' | "$H/routines.sh" safety -z >/dev/null 2>&1; [ $? = 2 ] && ok "an empty -z path is an error" || bad "an empty -z path passed"
"$H/routines.sh" safety --ref nope x >/dev/null 2>&1; [ $? = 2 ] && ok "a bad --ref is an error, not a pass" || bad "bad --ref passed"
nolist="$(git -c user.email=t@t -c user.name=t commit-tree "$(git mktree </dev/null)" -m empty)"; [ -n "$nolist" ] || bad "could not make a commit without the list"
"$H/routines.sh" safety --ref "$nolist" plugins/flow-stack/hooks/guard.sh >/dev/null 2>&1; [ $? = 2 ] && ok "a base with no safety list is an error, not the generic default" || bad "no list at the base fell back"
"$H/routines.sh" safety --ref '' .github/x.yml >/dev/null 2>&1; [ $? = 2 ] && ok "an empty --ref is an error" || bad "empty --ref read the working tree"
printf '' | "$H/routines.sh" safety -z >/dev/null 2>&1; [ $? = 2 ] && printf '\n' | "$H/routines.sh" safety >/dev/null 2>&1; [ $? = 2 ] &&
  ok "no paths (a failed git diff upstream) is an error, not clean" || bad "empty input passed"
tt="$H/../templates/triage.md"
grep -q 'routines.sh safety <files>` exits non-zero |$' "$tt" && grep -q '\*\*risk:high is never built.\*\* Add `needs-human`, and put a draft INTENT' "$tt" &&
  ok "triage: a safety path is risk:high, which gets a draft INTENT and needs-human" || bad "triage contract"
grep -q 'When `.github/routines/triage.md` exists' "$H/../templates/self-heal.md" && grep -q '`risk:high` is never built' "$H/../templates/self-heal.md" &&
  grep -q 'triage miss: predicted' "$H/../templates/self-heal.md" && ok "self-heal: triage picks, never high, re-scores the diff" || bad "self-heal ignores triage"

# -- ideate: one cited proposal, issues only; self-heal skips a proposal without a human accept
"$H/routines.sh" add ideate >/dev/null || bad "add ideate failed"
iw=$W/flow-ideate.yml
grep -q '^  issues: write$' $iw && grep -q '^  contents: read$' $iw && grep -q '^  pull-requests: read$' $iw && grep -q 'github_token: ${{ github.token }}' $iw &&
  grep -q -- ' --auto Run the routine' $iw && grep -q 'labels="proposal accept"' $iw && ok "ideate writes only issues and needs proposal + accept" || bad "ideate render"
it="$H/../templates/ideate.md"
grep -q 'never more than one per run' "$it" && grep -q '\*\*2 or more independent sources\*\*' "$it" && grep -q 'no proposal: evidence below threshold' "$it" &&
  grep -q 'make-routines/templates/triage.md` step 2' "$it" && grep -q 'routines.sh safety <files>' "$it" && grep -q '\*\*Dry run\*\*' "$it" &&
  grep -q 'counts as no evidence at all' "$it" && grep -q 'with `proposal` as its only label' "$it" && grep -q 'Never comment, label, close, or edit other issues' "$it" &&
  ok "ideate: max 1, two sources or none, triage's risk table, a dry run" || bad "ideate contract"
for sh in "$H/../templates/self-heal.md" "$(git -C "$H" rev-parse --show-toplevel)/.github/routines/self-heal.md"; do
  [ -f "$sh" ] || continue
  grep -q 'skip it unless it carries `accept` and a human applied it, meaning the actor of the last `labeled` event for `accept`' "$sh" && grep -q '`heal-ok` alone never counts for a proposal, and a `heal-ok` no human applied' "$sh" &&
    ok "${sh#"$(dirname "$(dirname "$sh")")"/}: a proposal needs a human accept" || bad "$sh builds a proposal without accept"
done

# -- one safety list
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

[ "$FAILS" -eq 0 ] && echo "ready-check: $PASSES passed" || { echo "ready-check: $FAILS failed"; exit 1; }
