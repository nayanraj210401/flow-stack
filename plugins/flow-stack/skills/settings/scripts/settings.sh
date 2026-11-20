#!/usr/bin/env bash
# settings.sh: flow-stack's settings, one place to see and change them.
#   settings.sh [show]                            every hook (on/off, where that comes from) and the test settings
#   settings.sh hook <name> on|off|default [--repo]
#                                                 turn a default hook on or off; default drops the key
#   settings.sh tests scope impacted|full [--repo]
#                                                 impacted: run only the suites a change touches (suites.sh)
#   settings.sh tests unmatched full|skip [--repo]
#                                                 a changed file no suite claims: run the full suite, or skip it
#   settings.sh chapters format [scroll|slides|rounds] [--repo]
#                                                 the chapters page: print the format, or set it (default scroll)
#   settings.sh init                              create ~/.flow-stack/settings.json, carrying over config.json toggles
#   settings.sh path                              the files read, highest precedence first
#
# Layers, first set wins: <repo>/.flow/config.json (committed, the team's), ~/.flow-stack/settings.json
# (yours, every repo), ~/.flow-stack/config.json (older global toggles), then the default: on.
# Writes go to settings.json unless --repo. Sub-suites themselves are repo-specific: they live in
# <repo>/.flow/config.json "tests": {"suites": [...]} (see suites.sh).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../../../hooks/roots.sh"; flow_roots
home="${FLOW_STACK_HOME:-$HOME/.flow-stack}"
global="$home/settings.json"
legacy="$home/config.json"
repo=""; git -C "$PWD" rev-parse --show-toplevel >/dev/null 2>&1 && repo="$FLOW_DIR/config.json"
# tests.* is read where suites.sh reads it: a linked worktree's own .flow/config.json first, then settings.json
trepo="$repo"; [ -n "$repo" ] && [ -f "$FLOW_ROOT/.flow/config.json" ] && trepo="$FLOW_ROOT/.flow/config.json"

die() { echo "settings.sh: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "needs jq"

# The default hooks: the name each hook checks with flow_enabled, and what turning it off gives up.
# settings.test.sh fails when a hook checks a name missing here.
catalog() {
  cat <<'EOF'
anchor	UserPromptSubmit: re-anchors the active task's goal and slice; --auto/--no-auto switching
session-start	SessionStart: profile, rules, toolchain and task primer
guard	PreToolUse Bash/Read: destructive shell commands, .flow/gates.md, secrets and .env reads
pkgcheck	PreToolUse Bash: an install of a package the registry doesn't have (typo or hallucinated)
ready	PreToolUse Bash: a non-draft gh pr create/ready needs ready.sh's stamp for HEAD
tdd	PreToolUse Edit/Bash: the red/green lock (red edits only tests, green can't touch them)
seal	PreToolUse Edit: sealed checks change only with the human's approval
fence	PreToolUse Edit: edits stay inside the current slice's fence
holds	PreToolUse/PostToolUse Edit: file holds between live sessions on different tasks
blind	PreToolUse Read/Grep/Glob: blind checks are held out from the builder
trail	PostToolUse: every tool call goes to trail.jsonl, secrets redacted
circuit	PostToolUse: the same failing check 3 times stops the fix-loop
delegate	PostToolUse Read/Grep/Glob: nudge to hand bulk reading to a subagent
handoff	UserPromptSubmit/PreCompact: handoff nudge at the context threshold, snapshot before compaction
claims	Stop: "done/works/fixed" needs passing evidence (evidence.sh) newer than the last edit
host	SessionStart/Notification: agent-host sidebar push (herdr, Orca, cmux) and the desktop-ping skip
EOF
}
known() { catalog | cut -f1 | grep -qx -- "$1"; }

# value <file> <jq-path>: the value as a string, empty when unset or the file is missing/invalid
value() { [ -f "$1" ] || return 0; jq -r "($2) // empty | tostring" "$1" 2>/dev/null || true; }
hook_val() { [ -f "$1" ] || return 0; jq -r --arg h "$2" 'if (.hooks // {} | has($h)) then .hooks[$h] | tostring else empty end' "$1" 2>/dev/null || true; }
short() { case "$1" in "$global") echo settings.json ;; "$legacy") echo "config.json (global)" ;; *) echo "repo .flow/config.json" ;; esac; }
layers() { [ -z "$repo" ] || echo "$repo"; echo "$global"; echo "$legacy"; }
tlayers() { [ -z "$trepo" ] || echo "$trepo"; echo "$global"; }

# effective <hook>: "on|off<TAB>where"
effective() {
  local f v
  case "$1" in ready|pkgcheck) # checked inside guard.sh, after its own flow_enabled guard
    [ "$(effective guard | cut -f1)" = off ] && { printf 'off\tguard is off\n'; return; } ;;
  esac
  while IFS= read -r f; do
    v="$(hook_val "$f" "$1")"
    [ -n "$v" ] || continue
    if [ "$v" = false ]; then printf 'off\t%s\n' "$(short "$f")"; else printf 'on\t%s\n' "$(short "$f")"; fi
    return
  done < <(layers)
  printf 'on\tdefault\n'
}
test_setting() { setting tests "$@"; }
setting() { # setting <section> <key> <default>: "value<TAB>where"
  local f v
  while IFS= read -r f; do
    v="$(value "$f" ".$1.$2")"
    [ -n "$v" ] && { printf '%s\t%s\n' "$v" "$(short "$f")"; return; }
  done < <(tlayers)
  printf '%s\tdefault\n' "$3"
}

# write <file> <jq-filter> [args...]: edit a JSON file in place (created as {} when missing)
write() {
  local f="$1" tmp; shift
  mkdir -p "$(dirname "$f")"
  [ -s "$f" ] || echo '{}' >"$f"
  jq -e . "$f" >/dev/null 2>&1 || die "$f is not valid JSON; fix it by hand first"
  local l; while l="$(readlink "$f")"; do case "$l" in /*) f="$l" ;; *) f="$(dirname "$f")/$l" ;; esac; done  # write the link's target
  tmp="$(mktemp "$f.XXXXXX")" && cp -p "$f" "$tmp"  # cp -p: mv keeps the file's mode, not mktemp's 0600
  jq "$@" "$f" >"$tmp" && mv "$tmp" "$f" || { rm -f "$tmp"; die "could not write $f"; }
}
target() { # target [--repo] [repo file]
  if [ "${1:-}" = --repo ]; then [ -n "$repo" ] || die "--repo needs a git repo"; echo "${2:-$repo}"; else echo "$global"; fi
}

show() {
  local name desc st where
  echo "hooks (first set wins: $( [ -n "$repo" ] && printf 'repo .flow/config.json > ' )settings.json > config.json > on)"
  while IFS=$'\t' read -r name desc; do
    IFS=$'\t' read -r st where < <(effective "$name")
    printf '  %-13s %-3s  %-22s %s\n' "$name" "$st" "$where" "$desc"
  done < <(catalog)
  local extra
  extra="$(layers | while IFS= read -r f; do [ -f "$f" ] && jq -r '.hooks // {} | keys[]' "$f" 2>/dev/null; done | sort -u | while IFS= read -r k; do known "$k" || echo "$k"; done | tr '\n' ' ')"
  [ -z "$extra" ] || echo "  unknown hook names (ignored by every hook): $extra"
  echo "tests"
  IFS=$'\t' read -r st where < <(test_setting scope impacted); printf '  %-13s %-8s %s\n' scope "$st" "$where"
  IFS=$'\t' read -r st where < <(test_setting unmatched full); printf '  %-13s %-8s %s\n' unmatched "$st" "$where"
  echo "chapters"
  IFS=$'\t' read -r st where < <(setting chapters format scroll); printf '  %-13s %-8s %s\n' format "$st" "$where"
  if [ -n "$repo" ]; then
    printf '  %-13s %s\n' suites "$(jq -r '.tests.suites // [] | length' "$trepo" 2>/dev/null || echo 0) in repo .flow/config.json (suites.sh list)"
  fi
}

case "${1:-show}" in
  show) show ;;
  path) layers ;;
  hook)
    name="${2:-}"; val="${3:-}"
    [ -n "$name" ] && [ -n "$val" ] || die "usage: settings.sh hook <name> on|off|default [--repo]"
    known "$name" || die "no hook '$name'. Hooks: $(catalog | cut -f1 | tr '\n' ' ')(evidence for success claims is 'claims')"
    f="$(target "${4:-}")"
    case "$val" in
      on) write "$f" --arg h "$name" '.hooks[$h] = true' ;;
      off) write "$f" --arg h "$name" '.hooks[$h] = false' ;;
      default) [ -f "$f" ] && write "$f" --arg h "$name" 'del(.hooks[$h])' ;;
      *) die "hook $name: want on, off or default (got '$val')" ;;
    esac
    IFS=$'\t' read -r st where < <(effective "$name")
    echo "$name: $st ($where)"
    [ "$f" = "$global" ] && [ "$where" = "repo .flow/config.json" ] && echo "note: this repo's .flow/config.json sets $name and wins here; settings.sh hook $name $val --repo changes it"
    exit 0 ;;
  tests)
    key="${2:-}"; val="${3:-}"
    case "$key:$val" in
      scope:impacted|scope:full|unmatched:full|unmatched:skip) ;;
      *) die "usage: settings.sh tests scope impacted|full | tests unmatched full|skip [--repo]" ;;
    esac
    write "$(target "${4:-}" "$trepo")" --arg k "$key" --arg v "$val" '.tests[$k] = $v'
    IFS=$'\t' read -r st where < <(test_setting "$key" x); echo "tests.$key: $st ($where)"
    exit 0 ;;
  chapters)
    [ "${2:-}" = format ] || die "usage: settings.sh chapters format [scroll|slides|rounds] [--repo]"
    case "${3:-}" in
      ''|--repo) setting chapters format scroll | cut -f1; exit 0 ;;
      scroll|slides|rounds) ;;
      *) die "chapters format: want scroll, slides or rounds (got '$3')" ;;
    esac
    write "$(target "${4:-}" "$trepo")" --arg v "$3" '.chapters.format = $v'
    IFS=$'\t' read -r st where < <(setting chapters format scroll); echo "chapters.format: $st ($where)"
    exit 0 ;;
  init)
    if [ -f "$global" ]; then echo "$global exists"; exit 0; fi
    mkdir -p "$home"
    hooks='{}'; [ -f "$legacy" ] && hooks="$(jq -c '.hooks // {}' "$legacy" 2>/dev/null || echo '{}')"
    jq -n --argjson h "$hooks" '{version: 1, hooks: $h, tests: {scope: "impacted", unmatched: "full"}}' >"$global"
    echo "wrote $global$( [ "$hooks" != '{}' ] && printf ' (hooks carried over from config.json)' )"
    exit 0 ;;
  -h|--help|help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command '$1' (show | hook | tests | chapters | init | path)" ;;
esac
