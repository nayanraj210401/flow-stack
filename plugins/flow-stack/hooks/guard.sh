#!/usr/bin/env bash
# PreToolUse(Bash): block or escalate destructive commands, repo gates,
# writes to sealed checks, blind-check reads, and hallucinated packages.
. "$(dirname "$0")/lib.sh"
flow_init guard
flow_enabled guard || exit 0

# Auto mode: nobody is there to answer a question.
if [ "$(flow_field .tool_name)" = AskUserQuestion ]; then
  flow_auto && pre_decide deny "flow auto: the human is away (--auto). Don't ask: pick your recommended option if it's reversible and log it (task.sh decide agent), otherwise queue it. $FLOW_AUTO_QUEUE"
  exit 0
fi

cmd="$(flow_field .tool_input.command)"
[ -n "$cmd" ] || exit 0

has() { grep -Eiq -- "$1" <<<"$cmd"; }

# Literal text can't run, so the hard stops below skip it: the bodies of heredocs fed to cat, tee,
# git or gh that have a terminator line (an unquoted one only without $( or backticks), and quoted
# -m/--message/--title/--body values and the words of an echo/printf command that have neither and
# aren't piped on. A heredoc fed to anything else (bash, ssh …) is code.
lit="$(perl -e '
  my @l = split /\n/, do { local $/; <STDIN> }, -1; my @o;
  for (my $i = 0; $i < @l; $i++) {
    push @o, $l[$i];
    next unless $l[$i] =~ /^(.*?)(?:^|\s)<<(-?)[ \t]*(["\x27]?)([A-Za-z_]\w*)\3/;
    my ($pre, $dash, $q, $d) = ($1, $2, $3, $4); my $j = $i + 1;
    next unless ((split /[;&|(]/, " $pre")[-1] // "") =~ /^\s*(?:\w+=\S*\s+)*(?:cat|tee|git|gh)(?:\s|$)/;
    $j++ while $j < @l && $l[$j] !~ ($dash ? qr/^\t*\Q$d\E$/ : qr/^\Q$d\E$/);
    next if $j >= @l || ($q eq "" && join("\n", @l[$i + 1 .. $j - 1]) =~ /\$\(|`/);
    $i = $j;
  }
  $_ = join "\n", @o;
  s/((?:^|\s)(?:-m|--message|--title|--body)(?:\s+|=))(\x27[^\x27]*\x27|"[^"`\$\\]*")/$1\x27\x27/g;
  s{((?:^|[;&|(])[ \t]*)(echo|printf)([^;&|\n]*)(\|?)}{ my @m = ($1, $2, $3, $4); $m[3] || $m[2] =~ /\$\(|`/ ? join("", @m) : "$m[0]$m[1]" }ge;
  print' <<<"$cmd")"

# 1. Built-in hard stops: recursive delete of / or home, in any flag spelling.
# 1b. Recursive delete of an unguarded variable: empty or wrong, it hits the wrong tree.
#     ${VAR:?} aborts instead of expanding to nothing, so guarded targets pass.
while IFS= read -r seg; do
  grep -Eq '[[:space:]](-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([[:space:]]|$)' <<<"$seg" || continue
  if grep -Eq "[[:space:]][\"']?(/|~|\\\$HOME|\\\$\{HOME\})/?\*?[\"']?([[:space:]]|\$)" <<<"$seg"; then
    pre_decide deny "flow guard: recursive delete of / or home is never allowed."
  fi
  if sed -E 's/\$\{[A-Za-z_0-9]+:\?[^}]*\}//g' <<<"$seg" | grep -Eq '\$\{?[A-Za-z_0-9@*]'; then
    pre_decide ask "flow guard: recursive rm on an unguarded variable ('$seg'). If it's empty or points elsewhere, this deletes the wrong tree. Check it first, then guard it: rm -rf \"\${VAR:?}\"."
  fi
done < <(grep -Eo "(^|[;&|(\`[:space:]]|(-c|eval)[[:space:]]+[\"'])rm[[:space:]][^;&|)\`]*" <<<"$lit" || true)
gopts='git([[:space:]]+(-[cC][[:space:]]+[^[:space:];&|]+|-[^[:space:];&|]+))*'
force_push="" force_main=""
while IFS= read -r seg; do
  rest="$(sed -E "s/^$gopts[[:space:]]+push//" <<<"$seg")"
  grep -Eq '(^|[[:space:]])(--force|-[A-Za-z]*f[A-Za-z]*([[:space:]]|$))|(^|[[:space:]:])\+[^[:space:]]' <<<"$rest" || continue
  force_push=1
  grep -Eq '([[:space:]:+]["'"'"']?|refs/heads/)(main|master)["'"'"']?([[:space:]]|$)' <<<"$rest" && force_main=1
done < <(grep -Eo "$gopts[[:space:]]+push([[:space:]][^;&|)\`]*)?" <<<"$lit" || true)
if [ -n "$force_main" ]; then
  pre_decide deny "flow guard: force-push to main/master is blocked. Push a branch and open a PR."
fi
# Judge each argument of a reader on its own: quotes and dirs stripped, the example/sample/template
# names exempt per path, so a second .env.example arg doesn't waive the check.
env_deny() { pre_decide deny "flow guard: reading .env files puts secrets in the transcript. Read .env.example or ask the user which variable matters."; }
env_file() { # env_file <word>: a real .env file, not an example/sample/template
  local a="$1"; a="${a//[\"\']/}"; a="${a%%[<>]*}"; a="${a##*/}"
  grep -Eiq '^\.env(\.[A-Za-z0-9_.-]+)?$' <<<"$a" && ! grep -Eiq '^\.env\.(example|sample|template)$' <<<"$a"
}
while IFS= read -r seg; do
  seg="${seg//</ }"
  set -f; set -- $seg; set +f
  for a in "$@"; do env_file "$a" && env_deny; done
done < <(grep -Eio '(^|[;&|[:space:]])(cat|less|more|head|tail|bat|strings|xxd|hexdump|od|tac|nl|rev|fold|column|cut|sort|uniq|paste|base64|grep|egrep|fgrep|rg|ag|sed|awk|gawk|diff|cmp|comm)([[:space:]<][^;&|]*)' <<<"$cmd" || true)
# `< .env` feeds the file to any command.
while IFS= read -r a; do env_file "${a#<}" && env_deny; done < <(grep -Eo '(^|[^<])<[[:space:]]*[^[:space:];&|<>]+' <<<"$cmd" | sed -E 's/^[^<]*<[[:space:]]*//' || true)

# Gates are the human's: the /flow-pane decides them through task.sh gate, never the agent.
# A speed bump, not a boundary: an agent could still edit GATES.md by hand.
if has 'task\.sh[[:space:]]+gate([[:space:]]|$)'; then
  pre_decide deny "flow guard: gates are the human's to decide (the /flow-pane's buttons). Ask, or leave it in GATES.md."
fi

# Paths as the shell resolves them, for the blind and seal checks below: after `cd <dir>`, each
# word also appears absolute and repo-relative, so `cd tests && echo x > a.test.sh` still names
# tests/a.test.sh. Words under .flow/tasks are always resolved, so their globs can be matched.
paths="" blind_glob=""
if has '(^|[;&|(])[[:space:]]*(cd|pushd)[[:space:]]|\.flow/tasks/'; then
  dir="$FLOW_CWD" cded=""
  while IFS= read -r seg; do
    set -f; set -- $seg; set +f
    if [ "${1:-}" = cd ] || [ "${1:-}" = pushd ]; then
      shift; while [ "${1:-}" = -- ] || [[ "${1:-}" == -[LPe@] ]]; do shift; done
      a="${1//[\"\']/}"
      case "$a" in ""|-|\~*|*\$*) ;; /*) dir="$(flow_norm "$a")"; cded=1 ;; *) dir="$(flow_norm "$dir/$a")"; cded=1 ;; esac
      continue
    fi
    for w in "$@"; do
      w="${w//[\"\']/}"; [[ "$w" =~ ^[0-9\&]*[\<\>]+(.*) ]] && w="${BASH_REMATCH[1]}"
      case "$w" in ""|-*|*\$*) continue ;; esac
      [ -n "$cded" ] || [[ "$w" == *.flow/tasks/* ]] || continue
      case "$w" in /*) p="$(flow_norm "$w")" ;; *) p="$(flow_norm "$dir/$w")" ;; esac
      r="$(flow_rel "$p")"; paths="$paths"$'\n'"$p"$'\n'"$r"
      # .flow/tasks/<task>/<seg>/...: <seg> that is, or globs to, "blind" reaches the blind checks.
      if [[ "$r" == .flow/tasks/*/* ]]; then
        s="${r#.flow/tasks/*/}"; s="${s%%/*}"
        # shellcheck disable=SC2053
        [[ blind == $s ]] && blind_glob=1
      fi
    done
  done < <(tr ';&|(){}' '\n' <<<"$cmd")
fi

# 2. Blind checks: only blind-run.sh may touch them.
if { has '\.flow/tasks/[^/[:space:]]+/blind' || [ -n "$blind_glob" ] ||
     grep -Eq '\.flow/tasks/[^/[:space:]]+/blind' <<<"$paths"; } && ! has 'blind-run\.sh'; then
  pre_decide deny "flow guard: blind checks are held out from the builder. Run them only via verify's scripts/blind-run.sh."
fi

# 2b. Modes are the human's: a write to the auto-mode flags, or to Claude Code settings (whose env block
# could fake a GitHub runner for --gha), would let the model grant itself a mode. The path must follow a
# write verb (a whole word, or a redirect) in the same segment, so reading these files stays allowed.
# Interpreter one-liners (python -c, node -e) are a known gap; --gha still re-checks the runner itself.
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; c2="${cmd//"$FLOW_HOME"/FLOW_HOME}"; c2="${c2//"$cfg"/CLAUDE_CONFIG_DIR}"
wr='(>|(^|[[:space:];&|(])(tee|cp|mv|ln|install|dd|truncate|rm|sponge|sed[[:space:]]+-[A-Za-z]*i|perl[[:space:]]+-[A-Za-z]*i)([[:space:]]|$))[^;&|]*'
home='(\.flow-stack|FLOW_STACK_HOME\}?|FLOW_HOME\}?)'; conf='(\.claude|CLAUDE_CONFIG_DIR\}?)'
end='([/"'\''[:space:]]|$)'; sett='settings[^/[:space:]"'\'']*\.json'
cdin() { grep -Eq -- "(^|[;&|(][[:space:]]*)cd[[:space:]]+[^;&|]*$1" <<<"$c2"; }
if grep -Eq -- "$wr$home/auto$end" <<<"$c2" || { cdin "$home" && grep -Eq -- "$wr[\"']?(\./)?auto$end" <<<"$c2"; }; then
  pre_decide deny "flow guard: \$FLOW_STACK_HOME/auto/ holds the session's mode (--auto, ship, --gha). Only the human's prompt sets it."
fi
if grep -Eq -- "$wr$conf/$sett" <<<"$c2" || { cdin "$conf" && grep -Eq -- "$wr[\"']?(\./)?$sett" <<<"$c2"; }; then
  pre_decide ask "flow guard: writing Claude Code settings can change permissions, hooks, or env (an env block can fake a GitHub runner for --gha), so the human approves."
fi

# 3. Writes to sealed checks via the shell.
if [ -n "$FLOW_TASK_DIR" ] && [ -f "$FLOW_TASK_DIR/SEALS" ]; then
  if has 'seal\.sh[[:space:]]+(reseal|rm)'; then
    pre_decide ask "flow seal: re-sealing or unsealing changes what 'done' means for task '$FLOW_TASK'. Approve only if you agreed to the check change."
  fi
  if has '(SEALS|INTENT\.md)' && has '(sed[[:space:]]+-i|perl[[:space:]]+-p?i|>|tee|mv|rm|cp|truncate)'; then
    pre_decide ask "flow seal: task '$FLOW_TASK' is sealed; this command may change its acceptance contract."
  fi
  # A sealed check that is only read, run or copied from is not a write: '>' and cp count only when
  # the sealed path is their target (cp's last non-flag word). Every other write verb asks as before.
  wt="$(grep -Eo '>[>|]?[[:space:]]*[^[:space:];&|<>]+' <<<"$cmd" | sed -E 's/^>[>|]?[[:space:]]*//' || true)"
  wt="$wt"$'\n'"$(grep -Eo '(^|[^[:alnum:]_-])cp([[:space:]]+[^[:space:];&|<>]+)+' <<<"$cmd" |
    awk '{ for (i = NF; i > 1; i--) if ($i !~ /^-/) { print $i; break } }')"
  wt="${wt//[\"\']/}"
  writes() { # writes <needle>: is the needle, or a path ending in /<target>, a '>' or cp target?
    local t
    while IFS= read -r t; do
      t="${t#./}"
      [ -n "$t" ] && case "$1" in "$t"|*/"$t") return 0 ;; esac
    done <<<"$wt"
    return 1
  }
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
      if grep -Fq -- "$needle" <<<"$cmd$paths" &&
         { has '(sed[[:space:]]+(-i|--in-place)|perl[[:space:]]+-p?i|tee|mv|rm|truncate|(^|[^[:alnum:]_-])(install|ln)[[:space:]]|dd[[:space:]].*of=|git[[:space:]]+(checkout|restore))' || writes "$needle"; }; then
        pre_decide ask "flow seal: this command may modify sealed check '$sealed'. Sealed checks change only with the human's approval."
      fi
    done
  done <"$FLOW_TASK_DIR/SEALS"
fi

# 3a. TDD green: tests are locked against shell writes too. Write targets are redirects, tee's
# files, in-place sed/perl files, rm/truncate and git checkout/restore/rm paths, and cp/mv's
# destination, per command segment.
if [ -n "$FLOW_TASK_DIR" ] && flow_tdd && [ "$TDD_PHASE" = green ] && flow_enabled tdd; then
  targets="$(grep -Eo '>>?[[:space:]]*[^[:space:];&|<>]+' <<<"$cmd" | sed -E 's/^>>?[[:space:]]*//' || true)"
  while IFS= read -r seg; do
    set -f; set -- $seg; set +f
    case "${1:-}" in sudo|command|env|xargs) shift ;; esac
    case "${1:-}" in
      tee|rm|truncate) shift; targets="$targets"$'\n'"$(printf '%s\n' "$@")" ;;
      cp|mv) [ $# -lt 3 ] || targets="$targets"$'\n'"${@: -1}" ;;
      sed|perl) # the files, not the script: skip flags and the first operand (or -e's argument)
        printf '%s\n' "$@" | grep -Eq '^-[a-z]*i' || continue
        shift; script=""
        for a in "$@"; do
          case "$a" in
            -e|-[a-z]*e) script=next ;;
            -*|"''"|'""') ;;
            *) if [ "$script" = next ] || [ -z "$script" ]; then script=done; else targets="$targets"$'\n'"$a"; fi ;;
          esac
        done ;;
      git) case "${2:-}" in
        restore|rm) shift 2; targets="$targets"$'\n'"$(printf '%s\n' "$@")" ;;
        checkout) shift 2; skip="" dd="" # paths, not refs or the branch -b/-B/--orphan creates
          for a in "$@"; do
            a="${a//[\"\']/}"
            if [ -n "$dd" ]; then targets="$targets"$'\n'"$a"; continue; fi
            case "$a" in --) dd=1; continue ;; -b|-B|--orphan) skip=1; continue ;; -*) continue ;; esac
            [ -z "$skip" ] || { skip=""; continue; }
            git -C "$FLOW_CWD" rev-parse -q --verify "$a^{commit}" >/dev/null 2>&1 ||
              [ -n "$(git -C "$FLOW_CWD" for-each-ref --count=1 "refs/remotes/*/$a" 2>/dev/null)" ] ||
              targets="$targets"$'\n'"$a"
          done ;;
      esac ;;
    esac
  done < <(tr ';&|(){}' '\n' <<<"$cmd")
  while IFS= read -r t; do
    t="${t//[\"\']/}"; [ -n "$t" ] || continue
    t="$(flow_rel "$t")"; case "$t" in /*|.flow/*|-*) continue ;; esac
    if flow_is_test "$t" "$TDD_TESTS"; then
      pre_decide deny "flow tdd: this command writes to '$t', a test, and slice $TDD_ID is in green, so tests are locked. Change the code instead, or go back to red (task.sh tdd $TDD_ID red)."
    fi
  done <<<"$targets"
fi

# 3b. Slice completion goes through the proof gate.
# Only a write aimed at SLICES.md counts; reads, and writes elsewhere that mention it, pass.
if has 'status:[[:space:]]*done' && ! has 'task\.sh' &&
   has '(>>?|tee([[:space:]]+-a)?)[[:space:]]*[^[:space:]|;&]*SLICES\.md|(sed[[:space:]]+-i|perl[[:space:]]+-[a-z]*i|mv|cp|truncate)[^|;&]*SLICES\.md'; then
  pre_decide deny "flow gate: mark a slice done with task.sh slice <id> done (proof-gated), not by rewriting SLICES.md."
fi

# 3c. Ready for review: in a flow-stack repo, a non-draft PR or `gh pr ready` needs ready.sh's stamp for HEAD.
#     Only a real invocation counts: heredoc bodies are dropped, and gh must start a command:
#     line start, ; && || | ( {, if/then/!, VAR=x prefixes, or behind a wrapper (eval, sh/bash/zsh/dash/ksh, command, env,
#     time, timeout, nice, nohup, xargs, sudo, exec) with any flags of its own. Case-insensitive: case-insensitive
#     filesystems run GH as gh. A commit message that mentions it mid-sentence passes.
code="$(awk -v q="'" '
  hd != "" { if ($0 == hd) hd = ""; next }
  { print
    if (match($0, "<<-?[ \t]*[\"" q "]?[A-Za-z_][A-Za-z0-9_]*")) {
      hd = substr($0, RSTART, RLENGTH); sub("<<-?[ \t]*[\"" q "]?", "", hd) } }' <<<"$cmd")"
lead='(^|[;&|({]|(^|[;&|({[:space:]])(eval|command|env|time|timeout|nice|nohup|xargs|sudo|exec|(ba|z|da|k)?sh)([[:space:]][^;&|]*)?[[:space:]])'
lead="$lead"'[[:space:]]*((if|then|elif|else|do|while|until|!)[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=([^[:space:]]*|"[^"]*"|'"'"'[^'"'"']*'"'"')[[:space:]]+)*([$]?["'"'"'])?'
cend='([[:space:];&|)]|$)'
gopt='([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*'
pr_cmd="$(grep -Ei "$lead"'gh'"$gopt"'[[:space:]]+pr[[:space:]]+(create|ready)'"$cend" <<<"$code" || true)"
# The line is split into shell words and commands (quotes, escapes, $'…', ; & | ( )), and sh -c / eval scripts are
# split the same way, so a quoted title saying "-d" is one word, not a flag. Every gh pr create|ready command needs
# its own --draft, -d, --draft=true or --undo word. A word with an unterminated quote is never a flag, and # starts
# a comment. Fails closed: when the line starts gh pr create|ready (in a command position, as above, or after a
# backtick) more often than the split found commands ("$(…)", another interpreter), it is not a draft. Only code
# is counted: quoted titles, bodies and messages that name the command are text.
pr_drafts() {
  awk -v q="'" -v said="(\`|$lead)gh$gopt[[:space:]]+pr[[:space:]]+(create|ready)" '
    # split_cmds(s): tokens T with kinds K (w | bad | op), the part of each word the shell runs as code C (unquoted
    # text, and $(…) or `…` inside "…"; nothing from single-quoted text), and CS set when C holds such a substitution
    function split_cmds(s, T, K, C, CS,   i, j, c, ch, e, n, w, wc, has, bad, L, sub_, bt, nq, sq, code, cs) {
      n = 0; w = wc = ""; has = bad = cs = 0; L = length(s)
      for (i = 1; i <= L; i++) {
        c = substr(s, i, 1)
        if (c == "\\") { if (substr(s, ++i, 1) != "\n") { w = w substr(s, i, 1); wc = wc substr(s, i, 1); has = 1 } }
        else if (c == q) { j = index(substr(s, i + 1), q); has = 1
          if (!j) { w = w substr(s, i + 1); bad = 1; i = L } else { w = w substr(s, i + 1, j - 1); i += j } }
        else if (c == "\"" || (c == "$" && substr(s, i + 1, 1) == q)) {
          e = (c == "$") ? q : "\""; if (c == "$") i++; has = 1; sub_ = bt = nq = sq = 0
          for (i++; i <= L; i++) {
            ch = substr(s, i, 1); code = sub_ || bt
            if (!code && ch == e) break
            # inside $(…) or `…`, quotes nest; that code is kept as written and checked as a script of its own
            if (sq) { if (ch == q) sq = 0; wc = wc ch; w = w ch; continue }
            # "…" drops a backslash only before $ ` " \ newline; $'…' always does
            if (ch == "\\" && (e == q || index("$`\"\\\n", substr(s, i + 1, 1)))) { ch = substr(s, ++i, 1); if (code) wc = wc ch }
            else if (code && ch == q) { sq = 1; wc = wc ch }
            else if (code && ch == "\"") { nq = !nq; wc = wc ch }
            else if (e != q && !nq && ch == "`") { bt = !bt; wc = wc ch; cs = 1 }
            else if (e != q && !nq && substr(s, i, 2) == "$(") { sub_++; wc = wc "$("; w = w ch; ch = "("; i++; cs = 1 }
            else if (code) { if (!nq) { if (ch == "(") sub_++; else if (ch == ")" && sub_) sub_-- } wc = wc ch }
            w = w ch }
          if (i > L) bad = 1 }
        else if (c == "#" && !has) { j = index(substr(s, i), "\n"); i = j ? i + j - 2 : L }
        else if (c ~ /[;&|()\n]/) { if (has) { T[++n] = w; K[n] = bad ? "bad" : "w"; C[n] = wc; CS[n] = cs }
          T[++n] = c; K[n] = "op"; w = wc = ""; has = bad = cs = 0 }
        else if (c ~ /[ \t]/) { if (has) { T[++n] = w; K[n] = bad ? "bad" : "w"; C[n] = wc; CS[n] = cs }
          w = wc = ""; has = bad = cs = 0 }
        else { w = w c; wc = wc c; has = 1 }
      }
      if (has) { T[++n] = w; K[n] = bad ? "bad" : "w"; C[n] = wc; CS[n] = cs }
      return n
    }
    # check(s): adds to found / nondraft for each gh pr create|ready command in s, recursing into every word after
    # eval, after a -c option of sh, and into the substitutions in "…". Returns the code in s for the fail-closed count: each word keeps only its code
    # part, and a recursed word is replaced by its own check.
    function check(s,   T, K, C, CS, X, n, i, start, g, p, d, k, sh, ev, out) {
      n = split_cmds(s, T, K, C, CS); start = 1
      for (i = 1; i <= n + 1; i++) {
        if (i <= n && K[i] != "op") continue
        g = p = d = sh = ev = 0
        for (k = start; k < i; k++) {
          if (K[k] != "w") continue
          if (ev || sh > 1) X[k] = check(T[k]); else if (CS[k]) X[k] = check(C[k])
          if (tolower(T[k]) == "eval") ev = 1
          if (T[k] ~ /^(ba|z|da|k)?sh$/ || T[k] ~ /\/(ba|z|da|k)?sh$/) sh = 1
          else if (sh && T[k] ~ /^-[A-Za-z]*c[A-Za-z]*$/) sh = 2
          if (!g && tolower(T[k]) == "gh") g = k
          else if (g && !p && T[k] == "pr" && k < i - 1 && T[k + 1] ~ /^(create|ready)$/ && K[k + 1] == "w") p = ++k
          else if (p && T[k] ~ /^(--draft(=true)?|-d|--undo)$/) d = 1
        }
        if (p) { found++; if (!d) nondraft++ }
        start = i + 1
      }
      for (k = 1; k <= n; k++) out = out (K[k] == "op" ? T[k] : " " ((k in X) ? X[k] : C[k]) " ")
      return out
    }
    { all = all $0 "\n" }
    END { s = tolower(check(all)); exit !(found && !nondraft && found >= gsub(said, "", s)) }'
}
if [ -d "$FLOW_DIR" ] && flow_enabled ready && [ -n "$pr_cmd" ] && ! pr_drafts <<<"$code"; then
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

# 4b. Auto mode: outward-facing actions wait for the human even where nothing else gates them.
# `--auto ship` lets exactly these through once ready.sh stamped HEAD: pushing the current branch
# (not main) by its name, gh pr create/ready, and merging the current branch's PR. Anything else asks.
ship_allowed() { # ship_allowed <one-line command>
  local cur
  [[ "$1" != *$'\n'* ]] || return 1
  case "$1" in
    git\ push\ *)
      cur="$(git -C "$FLOW_ROOT" symbolic-ref --short -q HEAD)" && [ "$cur" != main ] && [ "$cur" != master ] || return 1
      [[ "$1" =~ ^git\ push(\ -u|\ --set-upstream)?\ [A-Za-z0-9._-]+\ ([^[:space:]]+)$ ]] && [ "${BASH_REMATCH[2]}" = "$cur" ] ;;
    gh\ release\ create\ *)
      flow_auto_gha || return 1
      # the tag is cut from the stamped branch, never from the default branch's tip
      cur="$(git -C "$FLOW_ROOT" symbolic-ref --short -q HEAD)" && [ "$cur" != main ] && [ "$cur" != master ] || return 1
      [[ "$1" =~ ^gh\ release\ create\ [A-Za-z0-9._-]+\ --target\ ([A-Za-z0-9._/-]+)(\ --(generate-notes|draft|prerelease)|\ --(title|notes-file)\ [A-Za-z0-9._-]+)*$ ]] && [ "${BASH_REMATCH[1]}" = "$cur" ] ;;
    *) grep -Eq '^(gh pr (create|ready)( [^;&|`$<>()]*)?|gh pr merge( --(squash|merge|rebase|delete-branch))*)$' <<<"$1" ;;
  esac
}
if grep -Eiq "$lead"'(git'"$gopt"'[[:space:]]+push|gh'"$gopt"'[[:space:]]+(pr[[:space:]]+(create|merge|ready)|release[[:space:]]+create)|npm'"$gopt"'[[:space:]]+publish)'"$cend" <<<"$code" && flow_auto; then
  if ! flow_auto_ship || ! ship_allowed "$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$cmd")" \
     || ! (cd "$FLOW_ROOT" && "$(dirname "$0")/../skills/review/scripts/ready.sh" stamped) 2>/dev/null; then
    pre_decide ask "flow: outward-facing action$(flow_auto_gha && echo ". --gha adds only gh release create <tag> --target <current branch> (plain flags) to the --auto ship set.")$(flow_auto_ship && echo ". --auto ship allows only \`git push [-u] <remote> <current branch>\` (not main), gh pr create/ready (body via --body-file or --fill, no shell expansions), and gh pr merge of the current branch's PR, once review/scripts/ready.sh has stamped HEAD")."
  fi
fi

# 5. Built-in escalations: reversible only with effort, so the human decides.
if [ -n "$force_push" ]; then
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
    # Package names of one install segment: redirections are dropped, and so are flags with their
    # value (-r reqs.in), paths and archives (pip install dist/x.tar.gz).
    # Only flags that take a value in that ecosystem: a boolean one (pnpm -r) would swallow a name.
    sub names { my ($args, $eco) = @_; $args =~ s/&?\d*[<>]+&?\s*\S+//g; my ($skip, @n);
      my $val = $eco eq "npm" ? qr/^(?:-C|--(?:prefix|cwd|dir|registry))$/
        : qr/^(?:-[rceti]|--(?:requirement|constraint|editable|target|prefix|index-url|extra-index-url|find-links|root|python))$/;
      for (split " ", $args) {
        if ($skip) { $skip = 0; next }
        if ($_ =~ $val) { $skip = 1; next }
        next if /^-/ || /^[.\/~]/ || /:\/\// || ($eco eq "pypi" && (m{/} || /\.(?:txt|toml|whl|in|zip)$/)) || /\.(?:tar|tgz|gz)$/;
        push @n, "$eco $_";
      } @n }
    for my $seg (split /&&|\|\||;|\|/) {
      if ($seg =~ /\b(?:npm\s+(?:i|install|add)|pnpm\s+(?:add|i|install)|yarn\s+add|bun\s+add)\s+(.*)/) {
        print "$_\n" for names($1, "npm");
      } elsif ($seg =~ /\b(?:pip3?\s+install|uv\s+(?:add|pip\s+install)|poetry\s+add)\s+(.*)/) {
        print "$_\n" for names($1, "pypi");
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
