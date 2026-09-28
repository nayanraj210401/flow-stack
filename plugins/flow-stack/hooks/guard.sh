#!/usr/bin/env bash
# PreToolUse(Bash): block or escalate destructive commands, repo gates,
# writes to sealed checks, blind-check reads, and hallucinated packages.
. "$(dirname "$0")/lib.sh"
flow_init guard
flow_enabled guard || exit 0

cmd="$(flow_field .tool_input.command)"
[ -n "$cmd" ] || exit 0

has() { grep -Eiq -- "$1" <<<"$cmd"; }

# 1. Built-in hard stops.
if has 'rm[[:space:]]+-[a-z]*(rf|fr)[a-z]*[[:space:]]+(/|~|\$HOME)/?\*?([[:space:]]|$)'; then
  pre_decide deny "flow guard: recursive delete of / or home is never allowed."
fi
# 1b. Recursive delete of an unguarded variable: empty or wrong, it hits the wrong tree.
#     ${VAR:?} aborts instead of expanding to nothing, so guarded targets pass.
while IFS= read -r seg; do
  grep -Eq '[[:space:]](-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([[:space:]]|$)' <<<"$seg" || continue
  if sed -E 's/\$\{[A-Za-z_][A-Za-z0-9_]*:\?[^}]*\}//g' <<<"$seg" | grep -Eq '\$\{?[A-Za-z_]'; then
    pre_decide ask "flow guard: recursive rm on an unguarded variable ('$seg'). If it's empty or points elsewhere, this deletes the wrong tree. Check it first, then guard it: rm -rf \"\${VAR:?}\"."
  fi
done < <(grep -Eo '(^|[;&|(`[:space:]])rm[[:space:]][^;&|]*' <<<"$cmd" || true)
if has 'git[[:space:]]+push[^;&|]*(--force|[[:space:]]-f([[:space:]]|$))[^;&|]*[[:space:]:+](main|master)([[:space:]]|$)'; then
  pre_decide deny "flow guard: force-push to main/master is blocked. Push a branch and open a PR."
fi
if has '(^|[;&|[:space:]])(cat|less|more|head|tail|bat|strings|xxd)[[:space:]][^;&|]*\.env(\.[a-z]+)?([[:space:]]|$)' && ! has '\.env\.(example|sample|template)'; then
  pre_decide deny "flow guard: reading .env files puts secrets in the transcript. Read .env.example or ask the user which variable matters."
fi

# 2. Blind checks: only blind-run.sh may touch them.
if has '\.flow/tasks/[^/[:space:]]+/blind' && ! has 'blind-run\.sh'; then
  pre_decide deny "flow guard: blind checks are held out from the builder. Run them only via verify's scripts/blind-run.sh."
fi

# 3. Writes to sealed checks via the shell.
if [ -n "$FLOW_TASK_DIR" ] && [ -f "$FLOW_TASK_DIR/SEALS" ]; then
  if has 'seal\.sh[[:space:]]+(reseal|rm)'; then
    pre_decide ask "flow seal: re-sealing or unsealing changes what 'done' means for task '$FLOW_TASK'. Approve only if you agreed to the check change."
  fi
  if has '(SEALS|INTENT\.md)' && has '(sed[[:space:]]+-i|perl[[:space:]]+-p?i|>|tee|mv|rm|cp|truncate)'; then
    pre_decide ask "flow seal: task '$FLOW_TASK' is sealed; this command may change its acceptance contract."
  fi
  # SEALS names "<path>" (home repo) or "<repo>:<path>"; match the absolute path from anywhere,
  # and the relative path only inside the repo that owns it.
  while read -r _ sealed; do
    [ -n "$sealed" ] || continue
    n="${sealed%%:*}"; rest="$sealed"; base="$FLOW_TASK_HOME"; own=""
    if [ "$n" != "$sealed" ] && [ -n "$(flow_repo_path "$n")" ]; then
      rest="${sealed#*:}"; base="$(flow_repo_path "$n")"; [ "$n" = "$FLOW_REPO_KEY" ] && own=1
    else
      [ -z "$FLOW_REPO_KEY" ] && own=1
    fi
    for needle in "$base/$rest" ${own:+"$rest"}; do
      if grep -Fq -- "$needle" <<<"$cmd" && has '(sed[[:space:]]+-i|perl[[:space:]]+-p?i|>[^&]|tee|mv|rm|cp|truncate|git[[:space:]]+(checkout|restore|rm))'; then
        pre_decide ask "flow seal: this command may modify sealed check '$sealed'. Sealed checks change only with the human's approval."
      fi
    done
  done <"$FLOW_TASK_DIR/SEALS"
fi

# 3b. Slice completion goes through the proof gate.
# Only a write aimed at SLICES.md counts; reads, and writes elsewhere that mention it, pass.
if has 'status:[[:space:]]*done' && ! has 'task\.sh' &&
   has '(>>?|tee([[:space:]]+-a)?)[[:space:]]*[^[:space:]|;&]*SLICES\.md|(sed[[:space:]]+-i|perl[[:space:]]+-[a-z]*i|mv|cp|truncate)[^|;&]*SLICES\.md'; then
  pre_decide deny "flow gate: mark a slice done with task.sh slice <id> done (proof-gated), not by rewriting SLICES.md."
fi

# 3c. Ready for review: in a flow-stack repo, a non-draft PR or `gh pr ready` needs ready.sh's stamp for HEAD.
#     Only a real invocation counts: heredoc bodies are dropped, and gh must start a command
#     (line start, ; && || | or a subshell), so a commit message that mentions it passes.
code="$(awk -v q="'" '
  hd != "" { if ($0 == hd) hd = ""; next }
  { print
    if (match($0, "<<-?[ \t]*[\"" q "]?[A-Za-z_][A-Za-z0-9_]*")) {
      hd = substr($0, RSTART, RLENGTH); sub("<<-?[ \t]*[\"" q "]?", "", hd) } }' <<<"$cmd")"
pr_cmd="$(grep -E '(^|[;&|(])[[:space:]]*gh[[:space:]]+pr[[:space:]]+(create|ready)([[:space:]]|$)' <<<"$code" || true)"
if [ -d "$FLOW_DIR" ] && flow_enabled ready && [ -n "$pr_cmd" ] &&
   ! grep -Eq '(--draft|--undo|[[:space:]]-d)([[:space:]=]|$)' <<<"$pr_cmd"; then
  ready="$(cd "$(dirname "$0")/../skills/review/scripts" && pwd)/ready.sh"
  if [ "$(cd "$FLOW_ROOT" && "$ready" mode)" != yolo ] && ! (cd "$FLOW_ROOT" && "$ready" stamped); then
    pre_decide deny "flow ready-for-review: HEAD isn't stamped ready. Human review is the expensive step, so run $ready (it lists what's missing), or open a draft PR (--draft) meanwhile. review_gate: yolo in the profile or .flow/config.json turns this off."
  fi
fi

# 4. Repo gates from .flow/gates.md:  "- deny: <ERE> · reason" / "- ask: <ERE> · reason"
if [ -f "$FLOW_DIR/gates.md" ]; then
  while IFS= read -r line; do
    kind="${line%%:*}"; kind="${kind#- }"
    rest="${line#*: }"
    pattern="${rest%% · *}"
    reason="${rest#* · }"
    [ "$reason" = "$rest" ] && reason="repo gate"
    [ -n "$pattern" ] || continue
    if grep -Eiq -- "$pattern" <<<"$cmd" 2>/dev/null; then
      pre_decide "$kind" "flow gate (.flow/gates.md): $reason"
    fi
  done < <(grep -E '^- (deny|ask): ' "$FLOW_DIR/gates.md")
fi

# 5. Built-in escalations: reversible only with effort, so the human decides.
if has 'git[[:space:]]+push[^;&|]*(--force|[[:space:]]-f([[:space:]]|$))'; then
  pre_decide ask "flow guard: force-push rewrites remote history."
fi
if has 'git[[:space:]]+(reset[[:space:]]+--hard|clean[[:space:]]+-[a-z]*f)'; then
  pre_decide ask "flow guard: this discards uncommitted work."
fi
if has '(drop[[:space:]]+(table|database|schema)|truncate[[:space:]]+table)'; then
  pre_decide ask "flow guard: destructive SQL."
fi
if has '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z)?sh'; then
  pre_decide ask "flow guard: piping a download into a shell."
fi

# 6. Package existence: catch hallucinated or typo'd dependencies.
if flow_enabled pkgcheck && command -v curl >/dev/null 2>&1; then
  pkgs="$(perl -ne '
    for my $seg (split /&&|\|\||;|\|/) {
      if ($seg =~ /\b(?:npm\s+(?:i|install|add)|pnpm\s+(?:add|i|install)|yarn\s+add|bun\s+add)\s+(.*)/) {
        print "npm $_\n" for grep { !/^-/ && !/^[.\/~]/ && !/:\/\// } split " ", $1;
      } elsif ($seg =~ /\b(?:pip3?\s+install|uv\s+(?:add|pip\s+install)|poetry\s+add)\s+(.*)/) {
        print "pypi $_\n" for grep { !/^-/ && !/^[.\/~]/ && !/:\/\// && !/\.(txt|toml|whl)$/ } split " ", $1;
      }
    }' <<<"$cmd" | head -n 5)"
  while read -r eco name; do
    [ -n "$name" ] || continue
    name="${name//[\"\']/}"
    if [ "$eco" = npm ]; then
      base="$(sed -E 's/^(@[^@\/]+\/[^@]+|[^@]+)@.*$/\1/' <<<"$name")"
      url="https://registry.npmjs.org/${base/\//%2F}"
    else
      base="$(sed -E 's/[<>=!~;\[].*$//' <<<"$name")"
      url="https://pypi.org/pypi/$base/json"
    fi
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$url" || echo 000)"
    if [ "$code" = 404 ]; then
      pre_decide deny "flow guard: package '$base' does not exist on the $eco registry. Possibly hallucinated or misspelled; check the name."
    fi
  done <<<"$pkgs"
fi

exit 0
