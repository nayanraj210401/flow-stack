#!/usr/bin/env bash
# routine-safety.test.sh: every rendered routine
#   - stops when the repo variable FLOW_FACTORY is off (#236),
#   - takes turns with the other routines that push (one flow-writers group) while review keeps a group per PR (#235),
#   - creates only the labels the repo lacks and never edits an existing one (#246),
#   - ends green with a "Not run" summary when the agent hit a Claude usage limit, and red on any other failure (#234).
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$H/../../../../.." && pwd)"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
SB="$(mktemp -d "${TMPDIR:-/tmp}/routine-safety.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/repo/.github" && cp -R "$REPO/.github/routines" "$SB/repo/.github/" && cd "$SB/repo"
bash "$H/routines.sh" render >/dev/null || bad "render failed"
# the rendered layout is the template's, so plain line reads find the job if:, the group and a step's run: block
job_if() { sed -n 's/^    if: //p' "$1" | head -n 1; }
group() { sed -n 's/^  group: //p' "$1"; }
step() { # step <name>: the run: block of that step in flow-self-heal.yml, unindented
  awk -v n="      - name: $1" '$0 == n { s = 1; next } s && /^        run: \|/ { r = 1; next }
    r && /^          / { print substr($0, 11); next } r { exit }' .github/workflows/flow-self-heal.yml
}

echo "-- kill switch, groups, labels"
for w in .github/workflows/flow-*.yml; do
  n="${w##*/flow-}"; n="${n%.yml}"
  [[ "$(job_if "$w")" == *"vars.FLOW_FACTORY != 'off'"* ]] && ok "$n: FLOW_FACTORY=off skips it" || bad "$n: no kill switch"
  grep -q 'gh label create "$l" --force' "$w" && bad "$n: overwrites existing labels" || ok "$n: never edits an existing label"
done
for n in self-heal auto-merge; do
  [ "$(group ".github/workflows/flow-$n.yml")" = flow-writers ] && ok "$n: in the flow-writers group" || bad "$n: own group"
done
[ "$(group .github/workflows/flow-review.yml)" = 'flow-review-${{ github.event.pull_request.number }}' ] \
  && ok "review: one group per PR" || bad "review group: $(group .github/workflows/flow-review.yml)"

# the label step and the Outcome step, run as written in the rendered workflow
mkdir -p bin; cat >bin/gh <<'GH'
#!/bin/sh
echo "$*" >>"$GH_LOG"
case "$1 $2" in "label list") printf 'Self-Heal\nbug\n' ;; esac
GH
chmod +x bin/gh
labels() { # run self-heal's label step as rendered; its summary goes to $SB/lsum
  : >gh.log; : >"$SB/lsum"
  step "flow-stack home and labels" | sed '/RUNNER_TEMP/d; /GITHUB_ENV/d; /profile.md/d' >labels.sh
  GH_LOG="$SB/repo/gh.log" GITHUB_STEP_SUMMARY="$SB/lsum" PATH="$SB/repo/bin:$PATH" bash labels.sh >/dev/null
}
if labels; then bad "a missing label didn't stop the run"; else ok "a missing label stops the run by default"; fi
grep -q 'label heal-ok missing' "$SB/lsum" && ok "summary names the missing label" || bad "summary: $(cat "$SB/lsum")"
grep -q 'label create' gh.log && bad "created a label without create_labels: $(cat gh.log)" || ok "no label created by default"
perl -pi -e "s/^labels:/create_labels: true\nlabels:/" .github/routines/self-heal.md && bash "$H/routines.sh" render >/dev/null
labels || bad "label step failed with create_labels: true"
[ -s gh.log ] && ! grep -q -- "--force" gh.log && ok "label step: no --force" || bad "label step: --force, or gh never ran"
grep -qix 'label create self-heal' gh.log && bad "re-created an existing label (Self-Heal)" || ok "existing label left alone, even in another case"
grep -qx 'label create heal-ok' gh.log && ok "create_labels: true creates the missing label" || bad "missing label not created: $(cat gh.log)"

echo "-- labels.tsv renames catalog labels on add"
mkdir -p "$SB/new/.github/routines" "$SB/new/verify" "$SB/new/.flow/features" && cd "$SB/new" && git init -q
echo x >verify/run.sh; printf -- '---\nid: a\nscenario: run it\n---\n' >.flow/features/a.md
git add -A && git -c user.email=a@b -c user.name=a commit -qm i
# self-heal is a label and the routine's name (and its branch prefix): only the label is renamed
printf '# catalog yours\nheal-ok approved\nneeds-repro Needs-Info\nself-create bot-filed\nself-heal fixer\n' >.github/routines/labels.tsv
bash "$H/routines.sh" add self-heal >/dev/null || bad "add self-heal failed"
r=.github/routines/self-heal.md
[ "$(sed -n 's/^labels: //p' $r)" = "fixer approved Needs-Info rework needs-human" ] && ok "labels: line uses the repo's names" || bad "labels: $(grep '^labels:' $r)"
grep -q -- '--label approved --json' $r && grep -q -- '--label bot-filed`' $r && grep -q '`Needs-Info`' $r && grep -q -- '--label fixer --title' $r \
  && ok "the prompt says approved, Needs-Info, bot-filed, fixer" || bad "prompt not renamed"
grep -q 'a self-heal comment' $r && ok "the routine's own name in prose stays" || bad "renamed self-heal in prose"
grep -qE 'heal-ok|needs-repro|`self-create`' $r && bad "a catalog label is left: $(grep -noE 'heal-ok|needs-repro|`self-create`' $r | head -3)" || ok "no catalog label left"
grep -q 'self-create routine' $r && grep -q '`self-heal/<number>-<slug>`' $r && ok "routine names and branch names untouched" || bad "renamed a non-label"
grep -q 'approved' .github/workflows/flow-self-heal.yml && ok "rendered workflow checks the mapped label" || bad "workflow lacks mapped label"
printf 'heal-ok has space\n' >.github/routines/labels.tsv
out="$(bash "$H/routines.sh" add self-heal --force 2>&1)"
[[ "$out" == *"no spaces inside a name"* ]] && grep -q approved $r && ok "a bad map line is refused, the routine left as it was" || bad "bad map: $out"
cd "$SB/repo"

echo "-- usage limit vs real failure"
step Outcome >outcome.sh
outcome() { # outcome <earlier assistant text> <last assistant text> → exit code; summary in $SB/summary
  jq -nc --arg a "$1" --arg b "$2" '[{type:"assistant",message:{content:[{type:"text",text:$a}]}},
    {type:"user",message:{content:[{type:"tool_result",content:"# A usage limit is not a verdict"}]}},
    {type:"assistant",message:{content:[{type:"text",text:$b}]}},{type:"result",subtype:"success",is_error:true}]' >run.json
  : >summary; RUN_FILE="$SB/repo/run.json" GITHUB_STEP_SUMMARY="$SB/summary" bash outcome.sh >/dev/null 2>&1
}
# the 5-hour line is verbatim from a real review run (#247, run 41298484012)
outcome "Confirm finding 1 and 4 against the code." "You've hit your 5-hour limit · resets 11:20am (UTC)" && ok "real 5-hour limit ends green" || bad "real 5-hour limit failed the job"
grep -q 'Stopped by a Claude usage limit (resets 11:20am (UTC))' "$SB/summary" && ok "summary says stopped, with the reset" || bad "summary: $(cat "$SB/summary")"
outcome "Starting." "You’ve hit your limit · resets 3am" && ok "curly apostrophe: usage limit ends green" || bad "curly apostrophe not matched"
outcome "Starting." "Claude AI usage limit reached|1761998400" && ok "epoch form ends green" || bad "epoch form failed the job"
grep -q 'Stopped by a Claude usage limit\. ' "$SB/summary" && ok "epoch form: no empty () in the summary" || bad "epoch summary: $(cat "$SB/summary")"
! outcome "Starting." "You've hit your GitHub API rate limit, so I stopped." && ok "a GitHub rate limit stays red" || bad "a GitHub rate limit went green"
! outcome "Error: tool crashed" "Giving up." && ok "any other failure stays red" || bad "a crash went green"
! outcome "Fixing #234 so a usage limit ends neutral." "I could not finish." && ok "a run that only mentions a usage limit stays red" || bad "a real failure went green"
! outcome "Starting." "$(printf 'Summary of #234:\nYou have hit your limit text is now detected.')" && ok "a limit phrase on a later line stays red" || bad "a later-line limit phrase went green"
! outcome "Starting." "$(printf "Summary of #234:\nYou've hit your weekly limit is detected now.")" && ok "the exact message on a later line stays red" || bad "a later-line limit message went green"
RUN_FILE=/nonexistent GITHUB_STEP_SUMMARY=/dev/null bash outcome.sh >/dev/null 2>&1 && bad "missing run file went green" || ok "missing run file stays red"

[ "$FAILS" -eq 0 ] && echo "== routine-safety · PASS" || { echo "== routine-safety · FAIL ($FAILS)"; exit 1; }
