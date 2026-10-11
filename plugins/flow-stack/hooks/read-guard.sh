#!/usr/bin/env bash
# PreToolUse(Read|Grep|Glob): blind checks are held out from the builder, and
# .env files stay out of the transcript (the guard hook covers the shell side).
. "$(dirname "$0")/lib.sh"
flow_init read-guard

cwd="$(flow_field .cwd)"
abs_of() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "${cwd:-$PWD}" "$1" ;; esac; }

if flow_enabled blind; then
  blind_msg="flow blind: this search reaches .flow/tasks/*/blind, which is held out so the builder cannot fit the code to it. Search a narrower path, such as .flow/features or one task file."
  base="$(flow_field '.tool_input.path // .tool_input.file_path // empty')"
  n="$(flow_norm "$(abs_of "${base:-.}")")"
  # path=. and no path stay allowed: ripgrep honours .gitignore, which ignores .flow/tasks/
  case "$n" in
    "$FLOW_DIR"|"$FLOW_DIR"/tasks) pre_decide deny "$blind_msg" ;;
    "$FLOW_DIR"/tasks/*)
      rest="${n#"$FLOW_DIR"/tasks/}"
      case "$rest" in
        */blind|*/blind/*) pre_decide deny "$blind_msg" ;;
        */*) ;;
        *) pre_decide deny "$blind_msg" ;;
      esac
      ;;
  esac
  rel=""
  case "$n" in "$FLOW_DIR"/*) rel=".flow/${n#"$FLOW_DIR"/}" ;; esac
  case "$(flow_field .tool_name)" in
    Glob) g="$(flow_field .tool_input.pattern)" ;;
    Grep) g="$(flow_field .tool_input.glob)" ;;
    *) g="" ;;
  esac
  if [ -n "$g" ]; then
    full="${rel:+$rel/}$g"
    case "/$full/" in
      */blind/*) pre_decide deny "$blind_msg" ;;
    esac
    case "$full" in
      MANIFEST|*/MANIFEST|MANIFEST/*|*/MANIFEST/*|*.flow/\*\**|*.flow/tasks/\*\**|*.flow/tasks/\*/\*|*.flow/tasks/\*/\*\**) pre_decide deny "$blind_msg" ;;
    esac
  fi
fi

if flow_enabled guard; then
  for f in "$(flow_field .tool_input.file_path)" "$(flow_field .tool_input.path)" "$(flow_field .tool_input.glob)"; do
    case "$(basename "${f:-x}")" in
      .env.example|.env.sample|.env.template) ;;
      .env|.env.*|.env\*)
        pre_decide deny "flow guard: reading .env files puts secrets in the transcript. Read .env.example, or ask the user which variable matters."
        ;;
    esac
  done
fi
exit 0
