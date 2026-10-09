#!/usr/bin/env bash
# Notification (and Stop, when notify_on: all): tell the human the agent
# needs them. Target comes from profile frontmatter "notify:".
#   osascript        macOS notification
#   ntfy:<topic>     push via ntfy.sh (NTFY_SERVER overrides the host)
#   off              nothing
. "$(dirname "$0")/lib.sh"
FLOW_HOOK=notify

msg="$1"
if [ -z "$msg" ]; then
  input="$(cat)"
  msg="$(jq -r '.message // "Claude needs you"' <<<"$input" 2>/dev/null || echo "Claude needs you")"
fi

target="$(profile_fm notify 2>/dev/null || true)"
case "$target" in
  ""|off) exit 0 ;;
  osascript)
    # a host (herdr, Orca, cmux) already pings; ntfy and notify_on: all still fire
    case "$(flow_host)" in herdr|orca|cmux)
      flow_roots "$(jq -r '.cwd // empty' <<<"${input:-}" 2>/dev/null)"   # so a repo's hooks.host: false counts
      flow_enabled host && exit 0 ;;
    esac
    osascript -e "display notification \"${msg//\"/\\\"}\" with title \"flow-stack\"" >/dev/null 2>&1 || flow_warn "osascript failed"
    ;;
  ntfy:*)
    curl -s --max-time 5 -d "$msg" "${NTFY_SERVER:-https://ntfy.sh}/${target#ntfy:}" >/dev/null 2>&1 || flow_warn "ntfy failed"
    ;;
  *) flow_warn "unknown notify target '$target'" ;;
esac
exit 0
