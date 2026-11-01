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
step "flow-stack home and labels" | sed '/RUNNER_TEMP/d; /GITHUB_ENV/d; /profile.md/d' >labels.sh
GH_LOG="$SB/repo/gh.log" PATH="$SB/repo/bin:$PATH" bash labels.sh || bad "label step failed"
[ -s gh.log ] && ! grep -q -- "--force" gh.log && ok "label step: no --force" || bad "label step: --force, or gh never ran"
grep -qix 'label create self-heal' gh.log && bad "re-created an existing label (Self-Heal)" || ok "existing label left alone, even in another case"
grep -qx 'label create heal-ok' gh.log && ok "missing label created" || bad "missing label not created: $(cat gh.log)"

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
