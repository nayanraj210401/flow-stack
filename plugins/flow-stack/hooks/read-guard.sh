#!/usr/bin/env bash
# PreToolUse(Read|Grep|Glob): blind checks are held out from the builder, and
# .env files stay out of the transcript (the guard hook covers the shell side).
. "$(dirname "$0")/lib.sh"
flow_init read-guard

target="$(flow_field '[.tool_input.file_path, .tool_input.path, .tool_input.pattern, .tool_input.glob] | map(select(. != null)) | join(" ")')"

if flow_enabled blind; then
  case "$target" in
    *.flow/tasks/*/blind*|*/blind/MANIFEST*)
      pre_decide deny "flow blind: blind checks are held out so the builder cannot fit the code to them. The PROVE step runs them via verify's scripts/blind-run.sh, which reports only pass/fail."
      ;;
  esac
fi

if flow_enabled guard; then
  file="$(flow_field .tool_input.file_path)"
  case "$(basename "${file:-x}")" in
    .env.example|.env.sample|.env.template) ;;
    .env|.env.*)
      pre_decide deny "flow guard: reading .env files puts secrets in the transcript. Read .env.example, or ask the user which variable matters."
      ;;
  esac
fi
exit 0
