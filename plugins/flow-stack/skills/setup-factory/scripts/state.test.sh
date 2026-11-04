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
  "repo view") case "\$*" in *defaultBranchRef*) echo main ;; *) echo acme/app ;; esac ;;
  "secret list") [ "\$m" = admin ] && echo OTHER || exit 1 ;;
  "api repos/acme/app/rules/branches/main") [ "\$m" = reader ] && echo 1 || echo 0 ;;
  "api repos/acme/app/branches/main/protection") [ "\$m" = admin ] && echo 'gh: Branch not protected (HTTP 404)' >&2 || echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
  "variable get") case "\$m" in admin) echo off ;; reader) echo 'variable FLOW_FACTORY was not found' >&2; exit 1 ;; *) echo 'HTTP 403' >&2; exit 1 ;; esac ;;
  "label list") echo approved ;;
  "issue list") case "\$*" in *--label*) echo 2 ;; *) echo 7 ;; esac ;;
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

echo noauth >"$SB/mode"; out="$(bash "$D")"
want gh unknown

git remote set-url origin git@gitlab.com:acme/app.git; out="$(bash "$D")"
want GITHUB none; grep -q '^secret' <<<"$out" && bad "gh rows printed without a GitHub remote" || ok "no gh rows without a GitHub remote"

[ "$FAILS" -eq 0 ] && echo "state: PASS" || { echo "state: $FAILS failed"; exit 1; }
