#!/usr/bin/env bash
# state.test.sh: state.sh reports the GitHub side from gh, and says unknown, not ok, when gh can't see it.
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)/state.sh"
FAILS=0
ok()  { echo "  ✓ $*"; }
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
want() { grep -Eq "^$1 +$2( |$)" <<<"$out" && ok "$1 $2" || bad "$1: want $2, got: $(grep "^$1 " <<<"$out")"; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/state.XXXXXX")"; trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin" "$SB/home" "$SB/repo/.github/workflows" && cd "$SB/repo" && git init -q
git remote add origin https://github.com/acme/app.git
printf 'factory_ready: enforce\nnotify: osascript\nreview_gate: yolo\nshift:\n  when: "0 5 * * *"\n' >"$SB/home/profile.md"
touch .github/workflows/ci.yml .github/workflows/flow-review.yml
# fake gh: $SB/mode picks the answers; -q is ignored, so each call prints its final value
cat >"$SB/bin/gh" <<EOF
#!/usr/bin/env bash
m="\$(cat "$SB/mode")"
case "\$1 \$2" in
  "auth status") [ "\$m" != noauth ] ;;
  "repo view") [ "\$m" = broken ] && exit 1; case "\$*" in *defaultBranchRef*) echo main ;; *) echo acme/app ;; esac ;;
  "secret list") case "\$m" in admin) echo OTHER ;; team) printf 'OTHER\nANTHROPIC_API_KEY\n' ;; *) exit 1 ;; esac ;;
  "api repos/acme/app/actions/organization-secrets") [ "\$m" = orgsec ] && echo CLAUDE_CODE_OAUTH_TOKEN || exit 1 ;;
  "api repos/acme/app/rules/branches/main") [ "\$m" = reader ] && echo 1 || echo 0 ;;
  "api repos/acme/app/branches/main/protection") case "\$m" in team) echo '{}' ;; admin) echo 'gh: Branch not protected (HTTP 404)' >&2; exit 1 ;; *) echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;; esac ;;
  "api repos/acme/app") case "\$m" in orgsec|orgoff|orglocked) echo Organization ;; noowner) exit 1 ;; *) echo User ;; esac ;;
  "api repos/acme/app/actions/organization-variables") case "\$m" in orgoff) echo off ;; orgsec) echo '' ;; *) exit 1 ;; esac ;;
  "variable list") case "\$m" in reader|orgsec|orgoff|orglocked|noowner) echo OTHER ;; admin|team) echo FLOW_FACTORY ;; *) echo 'HTTP 404' >&2; exit 1 ;; esac ;;
  "variable get") [ "\$m" = admin ] && echo off || echo on ;;
  "label list") [ "\$m" = nolabels ] && exit 1; echo approved ;;
  "issue list") [ "\$m" = nolabels ] && exit 1; case "\$*" in *--label*) echo 2 ;; *) echo 7 ;; esac ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$SB/bin/gh"; export PATH="$SB/bin:$PATH" FLOW_STACK_HOME="$SB/home"

echo reader >"$SB/mode"; out="$(bash "$D")"
want profile ok; grep -q 'factory_ready: enforce · notify: osascript · review_gate: yolo' <<<"$out" && ok "reads the factory profile keys" || bad "profile keys: $(grep '^profile' <<<"$out")"
out="$(GITHUB_ACTIONS=true bash "$D")"; want host actions
out="$(env -u GITHUB_ACTIONS CLAUDE_CODE_REMOTE=true bash "$D")"; want host cloud
want shift missing
mkdir -p "$SB/home/shift" && echo tok >"$SB/home/shift/token"; out="$(bash "$D")"; want shift ok
want ci ok; grep -q '1 non-flow' <<<"$out" && ok "flow-* workflows not counted as CI" || bad "ci count"
want secret unknown
want protect ok
want kill on
want labels missing
want issues ok

echo admin >"$SB/mode"; mkdir -p .github/routines; printf 'heal-ok approved\n' >.github/routines/labels.tsv
out="$(bash "$D")"
want secret missing
want protect missing
want kill off
want labels ok; grep -q '7 open, 2 labelled approved' <<<"$out" && ok "counts the repo's own heal-ok label" || bad "issues: $(grep '^issues' <<<"$out")"

echo locked >"$SB/mode"; rm .github/routines/labels.tsv; out="$(bash "$D")"
want protect unknown
want kill unknown

echo team >"$SB/mode"; out="$(bash "$D")"
want secret ok; grep -q '^secret.*ANTHROPIC_API_KEY' <<<"$out" && ok "names the secret it found" || bad "secret name"
want protect ok
want kill on; grep -q 'FLOW_FACTORY=on' <<<"$out" && ok "reads the variable's value" || bad "kill value"

echo orgsec >"$SB/mode"; out="$(bash "$D")"
want secret ok; grep -q '(org secret)' <<<"$out" && ok "an org secret shared with the repo counts" || bad "org secret"

want kill on
echo orgoff >"$SB/mode"; out="$(bash "$D")"
want kill off; grep -q 'FLOW_FACTORY=off (org)' <<<"$out" && ok "an org-level FLOW_FACTORY=off pauses" || bad "org kill: $(grep '^kill' <<<"$out")"
echo orglocked >"$SB/mode"; out="$(bash "$D")"
want kill unknown

echo noowner >"$SB/mode"; out="$(bash "$D")"
want kill unknown

echo nolabels >"$SB/mode"; out="$(bash "$D")"
want labels unknown
want issues unknown

echo broken >"$SB/mode"; out="$(bash "$D")"
want gh unknown; grep -q '^secret' <<<"$out" && bad "rows printed after repo view failed" || ok "stops after repo view fails"

echo noauth >"$SB/mode"; out="$(bash "$D")"
want gh unknown

out="$(PATH=/usr/bin:/bin bash "$D")"; grep -q '^gh .*not installed' <<<"$out" && ok "says gh is not installed" || bad "no gh: $(grep '^gh' <<<"$out")"

git remote set-url origin git@gitlab.com:acme/app.git; out="$(bash "$D")"
want GITHUB none; grep -q '^secret' <<<"$out" && bad "gh rows printed without a GitHub remote" || ok "no gh rows without a GitHub remote"

[ "$FAILS" -eq 0 ] && echo "state: PASS" || { echo "state: $FAILS failed"; exit 1; }
