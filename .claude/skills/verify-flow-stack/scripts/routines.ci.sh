#!/usr/bin/env bash
# routines.ci: make-routines writes .github/routines/<name>.md plus a headless profile and renders a
# GitHub Actions workflow (schedule or pull_request) that installs the plugin and runs flow on it with
# least-privilege permissions; check catches drift.
. "$(dirname "$0")/lib.sh"; sandbox routines.ci
R="$S/make-routines/scripts/routines.sh"; TPL="$S/make-routines/templates"

check "add self-create" "$R" add self-create
check "add self-heal" "$R" add self-heal
check "add review" "$R" add review
check "add a custom routine" "$R" add weekly-deps
W=.github/workflows/flow-self-heal.yml
check "workflow is valid YAML" ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$W"
# YAML 1.1 reads the bare key `on` as true
[ "$(ruby -ryaml -e 'puts YAML.load_file(ARGV[0])[true]["schedule"][0]["cron"]' "$W")" = "0 4 * * *" ] && ok "cron from the routine's frontmatter" || bad "cron"
step="$(ruby -ryaml -e 'puts YAML.load_file(ARGV[0])["jobs"]["run"]["steps"].find { |s| s["uses"].to_s.start_with?("anthropics/claude-code-action") }.to_yaml' "$W")"
has "$step" "plugins: flow-stack@flow-stack" && ok "installs the flow-stack plugin" || bad "plugin not installed: $step"
has "$step" "flow-stack.git" && ok "adds the flow-stack marketplace" || bad "no marketplace"
has "$step" "--auto ship Run the routine in .github/routines/self-heal.md" && ok "prompt runs flow --auto ship on the routine" || bad "prompt"
has "$step" 'secrets.CLAUDE_CODE_OAUTH_TOKEN' && ok "oauth secret by default" || bad "auth"
grep -q 'FLOW_STACK_HOME=$RUNNER_TEMP/flow-stack' "$W" && ok "profile lives outside the checkout" || bad "FLOW_STACK_HOME"
grep -q 'for l in self-heal heal-ok needs-repro rework needs-human;' "$W" && ok "labels created from frontmatter" || bad "labels"
grep -q '^notify: off' .github/routines/profile.md && ok "CI profile has notifications off" || bad "notify"
grep -q '^preset: solo-hacker' .github/routines/profile.md && ok "CI profile from a preset" || bad "preset"
check "check passes on a fresh render" "$R" check
sees "setup's forge census sees the routines" "4 routine(s)" "$S/setup/scripts/detect.sh"

echo "-- edits: the routine is the source of truth"
fails "add refuses to clobber" "$R" add self-heal
fails "bad name refused" "$R" add "Bad Name"
perl -pi -e 's/^cron: .*/cron: "15 6 * * 1"/; s/^timeout: .*/timeout: 30\nauth: api-key/' .github/routines/self-heal.md
sees "check flags a stale workflow" "✗ self-heal" "$R" check
fails "check exits non-zero on drift" "$R" check
check "render" "$R" render
grep -q 'cron: "15 6 \* \* 1"' "$W" && ok "render picks up the new cron" || bad "cron not re-rendered"
grep -q 'timeout-minutes: 30' "$W" && ok "render picks up the timeout" || bad "timeout"
grep -q 'anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}' "$W" && ok "auth: api-key switches the secret" || bad "api-key"
check "check passes after render" "$R" check
echo "# hand edit" >>"$W"
fails "a hand-edited workflow is drift" "$R" check
check "render restores it" "$R" render

echo "-- least privilege and untrusted input"
perm() { ruby -ryaml -e 'puts YAML.load_file(ARGV[0])["permissions"][ARGV[1]]' "$1" "$2"; }
C=.github/workflows/flow-self-create.yml
[ "$(perm "$C" contents)/$(perm "$C" pull-requests)/$(perm "$C" issues)" = read/read/write ] && ok "self-create (grants: issues) can't push or open PRs" || bad "self-create perms: $(perm "$C" contents)/$(perm "$C" pull-requests)"
[ "$(perm "$W" contents)/$(perm "$W" pull-requests)" = write/write ] && ok "self-heal (grants contents) can push" || bad "self-heal perms"
[ "$(perm .github/workflows/flow-weekly-deps.yml contents)" = read ] && ok "a custom routine defaults to grants: issues" || bad "custom default perms"
grep -q WebFetch "$W" && bad "WebFetch still allowed" || ok "no WebFetch in allowedTools"
grep -q -- '--label heal-ok' .github/routines/self-heal.md && grep -q authorAssociation .github/routines/self-heal.md && ok "self-heal takes only maintainer-labelled issues and collaborator comments" || bad "self-heal trusts any issue"

echo "-- bad frontmatter fails loudly and never empties a workflow"
cp "$W" "$ART/before.yml"
for bad_line in "cron: '5 1 * *'" "timeout: 60m" "auth: apikey" "grants: admin" "trigger: push" "flow_ref: a;b" 'labels: a;b'; do
  k="${bad_line%%:*}"
  perl -pi -e "s/^$k:.*/$bad_line/" .github/routines/self-heal.md
  grep -q "^$k:" .github/routines/self-heal.md || printf '%s\n' "$bad_line" | perl -0pi -e 'BEGIN{$l=<STDIN>} s/\n---\n/\n$l---\n/' .github/routines/self-heal.md
  fails "rejects $bad_line" "$R" render
  cmp -s "$W" "$ART/before.yml" && ok "workflow intact after $bad_line" || bad "workflow changed after $bad_line"
  cp "$TPL/self-heal.md" .github/routines/self-heal.md
done
perl -pi -e "s/^cron: .*/cron: '5 1 * * *'/" .github/routines/self-heal.md
check "single-quoted cron renders" "$R" render
grep -q 'cron: "5 1 \* \* \*"' "$W" && ok "single quotes stripped" || bad "cron: $(grep cron: "$W")"
printf -- '---\ncron: "0 3 * * *"\n---\nx\n' >".github/routines/My R.md"
fails "a bad routine filename is refused" "$R" render
rm ".github/routines/My R.md"

echo "-- review: the reviewer agent on pull requests"
V=.github/workflows/flow-review.yml
check "review workflow is valid YAML" ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$V"
[ "$(ruby -ryaml -e 'puts YAML.load_file(ARGV[0])[true]["pull_request"]["types"].join(",")' "$V")" = "opened,synchronize,ready_for_review" ] && ok "runs on pull_request events" || bad "pull_request trigger"
grep -q "schedule:" "$V" && bad "review has a schedule" || ok "no schedule on a PR routine"
grep -q "if: github.event.pull_request.draft == false && github.event.pull_request.head.repo.full_name == github.repository && github.actor != 'dependabot\[bot\]'" "$V" && ok "skips drafts, fork PRs, and Dependabot" || bad "job condition: $(grep 'if:' "$V")"
[ "$(perm "$V" contents)/$(perm "$V" pull-requests)/$(perm "$V" issues)" = read/write/read ] && ok "review can comment on PRs, not push" || bad "review perms"
grep -q -- "--auto Run the routine in .github/routines/review.md. Follow it exactly. The pull request is #\${{ github.event.pull_request.number }}." "$V" && ok "review runs --auto (not ship) with the PR number" || bad "review prompt: $(grep -A1 prompt: "$V")"
grep -q "flow-review-\${{ github.event.pull_request.number }}" "$V" && grep -q "cancel-in-progress: true" "$V" && ok "one run per PR; a new push cancels the old run" || bad "concurrency"
grep -q "^            --auto Run" "$V" && ok "review skips flow's task machinery (plain --auto)" || bad "review prompt prefix"
grep -q "^            /flow-stack:flow --auto ship Run" "$W" && ok "self-heal runs through flow --auto ship" || bad "self-heal prompt prefix"
grep -q 'github_token: ${{ github.token }}' "$V" && grep -q 'github_token: ${{ github.token }}' "$C" && ok "routines without contents use github.token, bounded by grants" || bad "github_token missing"
grep -q 'github_token:' "$W" && bad "self-heal should use the App token so its PRs trigger CI" || ok "self-heal keeps the App token"
grep -q "flow-stack:reviewer" .github/routines/review.md && ok "review spawns the flow-stack reviewer agent" || bad "no reviewer agent"
sees "list shows the catalog" "review       pull_request" "$R" list

echo "-- plugin version"
grep -q "plugin_marketplaces: https://github.com/nayanraj210401/flow-stack.git$" "$V" && ok "unpinned: the default branch, fresh each run" || bad "unpinned marketplace"
perl -0pi -e 's/\n---\n/\nflow_ref: v1.3.0\n---\n/' .github/routines/review.md
check "render with flow_ref" "$R" render
grep -q 'plugin_marketplaces: ${{ runner.temp }}/flow-stack-plugin$' "$V" && ok "a pin installs from a local clone (the action takes only URLs ending in .git)" || bad "pin: $(grep plugin_marketplaces "$V")"
grep -q "git clone -q --depth 1 --branch 'v1.3.0' https://github.com/nayanraj210401/flow-stack.git \"\$RUNNER_TEMP/flow-stack-plugin\"" "$V" && ok "the clone is at the pinned ref" || bad "clone: $(grep 'git clone' "$V")"
check "pinned workflow is valid YAML" ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$V"
grep -q 'flow-stack.git#' "$V" && bad "a #ref URL would be rejected by the action" || ok "no #ref URL"

echo "-- per-routine schedules"
check "add with --cron" "$R" add nightly-docs --cron "30 1 * * 2"
grep -q 'cron: "30 1 \* \* 2"' .github/routines/nightly-docs.md && grep -q 'cron: "30 1 \* \* 2"' .github/workflows/flow-nightly-docs.yml && ok "--cron lands in the routine and its workflow" || bad "--cron"
check "schedule changes an existing routine" "$R" schedule self-create "0 */6 * * *"
grep -q 'cron: "0 \*/6 \* \* \*"' .github/workflows/flow-self-create.yml && ok "schedule re-renders the workflow" || bad "schedule render: $(grep cron: .github/workflows/flow-self-create.yml)"
[ "$(grep -c '^cron:' .github/routines/self-create.md)" = 1 ] && ok "one cron line, replaced in place" || bad "cron lines: $(grep -c '^cron:' .github/routines/self-create.md)"
grep -q 'cron: "5 1 \* \* \*"' .github/workflows/flow-self-heal.yml && ok "other routines keep their own schedule" || bad "self-heal cron lost"
cp .github/workflows/flow-self-create.yml "$ART/sc.yml"
fails "schedule rejects a bad cron" "$R" schedule self-create "every day"
cmp -s .github/workflows/flow-self-create.yml "$ART/sc.yml" && grep -q 'cron: "0 \*/6' .github/routines/self-create.md && ok "a bad cron changes nothing" || bad "bad cron changed files"
fails "schedule refuses a pull_request routine" "$R" schedule review "0 1 * * *"
fails "add --cron rejects a bad cron" "$R" add bad-cron --cron "61"
[ ! -f .github/routines/bad-cron.md ] && ok "no routine written for a bad --cron" || bad "bad-cron.md written"
rm .github/routines/review.md .github/workflows/flow-review.yml
fails "add --cron refuses a pull_request routine" "$R" add review --cron "0 1 * * *"
[ ! -f .github/routines/review.md ] && ok "nothing written for it" || bad "review.md written"
check "re-add review" "$R" add review
perl -0pi -e 's/\n---\n/\nflow_ref: v1.3.0\n---\n/' .github/routines/review.md
fails "schedule needs an existing routine" "$R" schedule nope "0 1 * * *"
perl -0pi -e 's/flow_ref: v1.3.0/flow_ref: 29510cb/' .github/routines/review.md
fails "flow_ref rejects a commit SHA" "$R" render
perl -0pi -e 's/flow_ref: 29510cb/flow_ref: v1.3.0/' .github/routines/review.md
check "render" "$R" render
printf -- '---\ntrigger: schedule\ntimeout: 60\ngrants: issues\n---\n# body-cron\n\ncron: keep this body line\n' >.github/routines/body-cron.md
check "schedule a routine whose frontmatter has no cron" "$R" schedule body-cron "5 5 * * *"
[ "$(awk '/^---$/{n++;next} n==1' .github/routines/body-cron.md | grep -c '^cron: "5 5 \* \* \*"')" = 1 ] && ok "cron added inside the frontmatter" || bad "frontmatter: $(head -6 .github/routines/body-cron.md | tr '\n' '|')"
grep -q '^cron: keep this body line$' .github/routines/body-cron.md && ok "a body line starting cron: is left alone" || bad "body line rewritten"
grep -q 'cron: "5 5 \* \* \*"' .github/workflows/flow-body-cron.yml && ok "the workflow gets the new cron" || bad "workflow cron: $(grep cron: .github/workflows/flow-body-cron.yml)"
printf -- '---\r\ntrigger: schedule\r\ncron: "0 1 * * *"\r\ngrants: issues\r\n---\r\n# crlf\r\n' >.github/routines/crlf.md
check "schedule a CRLF routine" "$R" schedule crlf "7 7 * * *"
grep -q $'^cron: "7 7 \\* \\* \\*"\r$' .github/routines/crlf.md && [ "$(grep -c $'\r$' .github/routines/crlf.md)" = 6 ] && ok "CRLF routine stays CRLF with the new cron" || bad "crlf: $(od -c .github/routines/crlf.md | head -3 | tr '\n' ' ')"
printf -- '# no frontmatter\ncron: x\n' >.github/routines/nofm.md
cp .github/routines/nofm.md "$ART/nofm.md"
fails "schedule refuses a routine without frontmatter" "$R" schedule nofm "1 1 * * *"
cmp -s .github/routines/nofm.md "$ART/nofm.md" && ok "and leaves it untouched" || bad "nofm changed"
rm .github/routines/nofm.md
perl -pi -e 's/^grants: .*/grants: admin/' .github/routines/body-cron.md
cp .github/routines/body-cron.md "$ART/bc.md"; cp .github/workflows/flow-body-cron.yml "$ART/bc.yml"
fails "schedule fails when the routine can't render" "$R" schedule body-cron "6 6 * * *"
cmp -s .github/routines/body-cron.md "$ART/bc.md" && cmp -s .github/workflows/flow-body-cron.yml "$ART/bc.yml" && ok "a failed render restores the old schedule" || bad "routine or workflow changed after a failed render"
rm .github/routines/body-cron.md .github/workflows/flow-body-cron.yml .github/routines/crlf.md .github/workflows/flow-crlf.yml
rm .github/routines/nightly-docs.md .github/workflows/flow-nightly-docs.yml

echo "-- timezones"
check "add --cron --tz" "$R" add morning --cron "0 9 * * *" --tz Asia/Kolkata
tzof() { ruby -ryaml -e 's = YAML.load_file(ARGV[0])[true]["schedule"][0]; puts "#{s["cron"]}|#{s["timezone"]}"' "$1"; }
[ "$(tzof .github/workflows/flow-morning.yml)" = "0 9 * * *|Asia/Kolkata" ] && ok "9 AM local: the cron stays 0 9 and GitHub gets the zone" || bad "tz render: $(tzof .github/workflows/flow-morning.yml)"
check "schedule --tz changes the zone" "$R" schedule morning "30 8 * * 1-5" --tz America/New_York
[ "$(tzof .github/workflows/flow-morning.yml)" = "30 8 * * 1-5|America/New_York" ] && [ "$(grep -c '^timezone:' .github/routines/morning.md)" = 1 ] && ok "zone replaced in place" || bad "tz change: $(tzof .github/workflows/flow-morning.yml)"
check "schedule without --tz keeps the zone" "$R" schedule morning "0 7 * * *"
[ "$(tzof .github/workflows/flow-morning.yml)" = "0 7 * * *|America/New_York" ] && ok "the zone survives a cron change" || bad "tz lost: $(tzof .github/workflows/flow-morning.yml)"
cp .github/routines/morning.md "$ART/m.md"; cp .github/workflows/flow-morning.yml "$ART/m.yml"
fails "schedule rejects an unknown zone" "$R" schedule morning "0 9 * * *" --tz Mars/Base
cmp -s .github/routines/morning.md "$ART/m.md" && cmp -s .github/workflows/flow-morning.yml "$ART/m.yml" && ok "a bad zone changes nothing" || bad "bad zone changed files"
fails "add --tz without --cron" "$R" add lonely-tz --tz Asia/Kolkata
fails "schedule rejects an alias zone" "$R" schedule morning "0 9 * * *" --tz Asia/Calcutta
fails "schedule rejects a non-zone file" "$R" schedule morning "0 9 * * *" --tz posixrules
fails "schedule rejects Factory" "$R" schedule morning "0 9 * * *" --tz Factory
fails "schedule rejects trailing arguments" "$R" schedule morning "0 9 * * *" --tz Asia/Kolkata extra
fails "schedule rejects --tz with no zone" "$R" schedule morning "0 9 * * *" --tz
cmp -s .github/routines/morning.md "$ART/m.md" && ok "rejected zones and arguments change nothing" || bad "rejections changed files"
check "UTC is accepted" "$R" schedule morning "0 7 * * *" --tz UTC
check "Etc/GMT-5 is accepted" "$R" schedule morning "0 7 * * *" --tz Etc/GMT-5
check "Etc/GMT-14 and GMT are accepted" sh -c '"$1" schedule morning "0 7 * * *" --tz Etc/GMT-14 && "$1" schedule morning "0 7 * * *" --tz GMT' _ "$R"
fails "Etc/GMT+13 (no such zone) is refused" "$R" schedule morning "0 7 * * *" --tz Etc/GMT+13
fails "Etc/GMT-15 (no such zone) is refused" "$R" schedule morning "0 7 * * *" --tz Etc/GMT-15
grep -q timezone: .github/workflows/flow-self-heal.yml && bad "self-heal got a zone it never set" || ok "no timezone key means UTC"
rm .github/routines/morning.md .github/workflows/flow-morning.yml
check "check passes after schedule edits" "$R" check

echo "-- orphans"
rm .github/routines/weekly-deps.md
sees "check flags a workflow whose routine is gone" "flow-weekly-deps.yml: its routine" "$R" check
rm .github/workflows/flow-weekly-deps.yml
check "check passes once the orphan is gone" "$R" check
cp -r .github "$ART/"
finish
