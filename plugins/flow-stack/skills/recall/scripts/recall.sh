#!/usr/bin/env bash
# recall.sh: read past Claude Code conversations for this repo, cheaply and without noise.
# Only the human's own prompts and Claude's replies are kept: tool calls, tool output, skill
# expansions, agent hand-backs, and task notifications are dropped. Output is redacted.
#   recall.sh sessions [--days N]          recent conversations: date · id · title · prompts · PRs
#   recall.sh grep <regex> [--days N]      matching lines (case-insensitive): date · id · who: text
#   recall.sh show <id-prefix> [--full]    one conversation in order; --full keeps long replies whole
# Options: --days N (default 7) · --repo <path> (default: this git repo) · --skip <id-prefix>
# Transcripts: ${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<repo path, non-alphanumerics as "->/*.jsonl
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../../../hooks/lib.sh"

cmd="${1:-sessions}"; [ $# -gt 0 ] && shift
arg=""; days=7; repo=""; skip=""; full=0
while [ $# -gt 0 ]; do
  case "$1" in
    --days) days="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    --skip) skip="$2"; shift 2 ;;
    --full) full=1; shift ;;
    *) arg="$1"; shift ;;
  esac
done
[ -n "$repo" ] || repo="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(printf '%s' "$repo" | sed 's/[^A-Za-z0-9]/-/g')"
[ -d "$dir" ] || { echo "recall: no conversations for $repo (looked in $dir)"; exit 0; }

# One message per line as date<TAB>who<TAB>text, human prompts and Claude's text only.
lines='
def body: if (.message.content | type) == "string" then .message.content
          else [.message.content[]? | select(.type == "text") | .text] | join("\n") end;
def tool_result: (.message.content | type) == "array" and any(.message.content[]; .type == "tool_result");
def noise: test("^\\s*<(local-command|task-notification|system-reminder)") or test("^Another Claude session sent a message");
def command: if test("<command-name>") then
    (capture("<command-name>(?<n>[^<]*)</command-name>") | .n) + " " +
    ((capture("<command-args>(?<a>[\\s\\S]*)</command-args>") | .a) // "")
  else . end;
select(.message != null and (.isMeta | not) and (.isSidechain | not))
| if .type == "user" and ((.origin.kind // "human") == "human") and (tool_result | not)
  then (body | select(noise | not) | command) as $t | [(.timestamp // "")[0:16], "you", $t]
  elif .type == "assistant" then (body | select(length > 0)) as $t | [(.timestamp // "")[0:16], "claude", $t]
  else empty end
| select(.[2] | test("\\S")) | @tsv'

files() { # newest first, within --days, minus --skip
  find "$dir" -maxdepth 1 -name '*.jsonl' -mtime -"$days" -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null |
    { if [ -n "$skip" ]; then grep -v "/$skip[^/]*\.jsonl$" || true; else cat; fi; }
}
id8() { basename "$1" .jsonl | cut -c1-8; }
oneline() { tr '\t' ' ' | awk -F'\t' -v w="$1" '{ gsub(/\\n/, " "); if (w > 0 && length($0) > w) $0 = substr($0, 1, w) "…"; print }'; }

case "$cmd" in
  sessions)
    files | while IFS= read -r f; do
      title="$(jq -r 'select(.type == "ai-title") | .aiTitle' "$f" 2>/dev/null | tail -n1)"
      prs="$(jq -r 'select(.type == "pr-link") | "#\(.prNumber)"' "$f" 2>/dev/null | sort -u | tr '\n' ' ')"
      msgs="$(jq -r "$lines" "$f" 2>/dev/null || true)"
      n="$(grep -c "	you	" <<<"$msgs" || true)"
      [ "${n:-0}" -gt 0 ] || continue
      first="$(grep "	you	" <<<"$msgs" | cut -f3 | grep -Ev '^/[^ ]+ *$' | head -n1 | oneline 90)"
      printf '%s · %s · %s · %s prompts%s\n  first: %s\n' "$(head -n1 <<<"$msgs" | cut -f1)" "$(id8 "$f")" \
        "${title:-untitled}" "$n" "${prs:+ · PRs ${prs% }}" "$first"
    done | redact ;;
  grep)
    [ -n "$arg" ] || { echo "usage: recall.sh grep <regex> [--days N]" >&2; exit 2; }
    files | while IFS= read -r f; do
      jq -r "$lines" "$f" 2>/dev/null | grep -Ei -- "$arg" | while IFS=$'\t' read -r ts who text; do
        printf '%s · %s · %s: %s\n' "$ts" "$(id8 "$f")" "$who" "$(printf '%s' "$text" | oneline 240)"
      done || true
    done | redact ;;
  show)
    [ -n "$arg" ] || { echo "usage: recall.sh show <id-prefix> [--full]" >&2; exit 2; }
    f="$(ls "$dir"/"$arg"*.jsonl 2>/dev/null | head -n1)"
    [ -n "$f" ] || { echo "recall: no conversation $arg* in $dir" >&2; exit 1; }
    w=400; [ "$full" = 1 ] && w=0
    jq -r "$lines" "$f" | while IFS=$'\t' read -r ts who text; do
      printf '%s %s: %s\n' "$ts" "$who" "$(printf '%s' "$text" | oneline "$w")"
    done | redact ;;
  *) sed -n '2,10p' "$0" >&2; exit 2 ;;
esac
