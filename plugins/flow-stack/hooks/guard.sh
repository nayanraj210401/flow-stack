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
  # A target that resolves to / or home (or its * glob) once quotes, ., .. and // are folded.
  if perl -ne 'for (split) { s/["\x27]//g; s{^(~|\$HOME|\$\{HOME(:\?[^\}]*)?\})(?=/|$)}{} or m{^/} or next; my @s;
      for (split m{/}) { next if $_ eq "" || $_ eq "."; $_ eq ".." ? pop @s : push @s, $_ }
      $hit = 1 if !@s || "@s" eq "*" } END { exit !$hit }' <<<"$seg"; then
    pre_decide deny "flow guard: recursive delete of / or home is never allowed."
  fi
  if sed -E 's/\$\{[A-Za-z_0-9]+:\?[^}]*\}//g' <<<"$seg" | grep -Eq '\$\{?[A-Za-z_0-9@*]'; then
    pre_decide ask "flow guard: recursive rm on an unguarded variable ('$seg'). If it's empty or points elsewhere, this deletes the wrong tree. Check it first, then guard it: rm -rf \"\${VAR:?}\"."
  fi
done < <(grep -Eo "(^|[;&|(\`[:space:]]|(-c|eval)[[:space:]]+[\"'])rm[[:space:]][^;&|)\`]*" <<<"$lit" || true)
gopts='git([[:space:]]+((-[cC]|--(git-dir|work-tree|namespace|super-prefix|exec-path|config-env|attr-source))[[:space:]]+[^[:space:];&|]+|-[^[:space:];&|]+))*'
force_push="" force_main=""
unshell='s/\$(?=["\x27])//g; tr/"\x27\\\\//d; '
while IFS= read -r seg; do
  # Push args as the shell hands them to git: $'..' and quotes and backslashes dropped, {a,b} expanded
  # (64 rounds or 8KB), so '+main', :$'main', '':main, :\main and :{main,x} read as written. What
  # this can't read counts as main (braces left over, escapes inside $'..') or asks ({a..b} ranges,
  # a delete whose target is a $ expansion).
  rest="$(sed -E "s/^$gopts[[:space:]]+push//" <<<"$seg" | perl -pe '$m = /\$\x27[^\x27]*\\/; $r = /\{[^{}]*\.\.[^{}]*\}/; '"$unshell"'1 while $n++ < 64 && length() < 8192 && s/(\S*)\{([^{}]*,[^{}]*)\}(\S*)/join " ", map { "$1$_$3" } split m{,}, $2, -1/e;
    $r ||= /(^|\s):\S*\$/ || (/(^|\s)(--de(l(e(te?)?)?)?|-[A-Za-z]*d[A-Za-z]*)(\s|$)/ && /\$/);
    $_ .= " :main" if $m || /\{[^{}]*,[^{}]*\}/; print "\@unread\n" if $r')"
  # An unread target asks on its own; it says nothing about main.
  case "$rest" in *@unread*) force_push=1 rest="${rest//@unread/}" ;; esac
  # Deleting main (:main, --delete/-d) is as final as force-pushing it; --mirror and --prune can do either.
  # git takes any unique prefix of a long option (--del, --m, --pru, --for).
  if grep -Eq '(^|[[:space:]]):((refs/)?heads/)?(main|master)([[:space:]]|$)' <<<"$rest" ||
    { grep -Eq '(^|[[:space:]])(--de(l(e(te?)?)?)?|-[A-Za-z]*d[A-Za-z]*)([[:space:]]|$)' <<<"$rest" &&
      grep -Eq '[[:space:]]((refs/)?heads/)?(main|master)([[:space:]]|$)' <<<"$rest"; }; then
    force_main=1
  fi
  grep -Eq '(^|[[:space:]])((--for(c(e[a-z-]*)?)?|--m(i(r(r(or?)?)?)?)?|--pru(ne?)?)([[:space:]=]|$)|-[A-Za-z]*f[A-Za-z]*([[:space:]]|$))|(^|[[:space:]:])\+[^[:space:]]' <<<"$rest" || continue
  force_push=1
  grep -Eq '[[:space:]:+]((refs/)?heads/)?(main|master)([[:space:]]|$)' <<<"$rest" && force_main=1
done < <(G="$gopts" perl -0777 -ne '
  # A command that only reads (grep, cat, git log …) can quote a push without running one, as long
  # as nothing pipes or substitutes its output on: then the text can reach a shell and is judged.
  # Anything that can run its arguments (sed e, git rebase -x, submodule foreach) is judged too.
  my $runs = /[|`]|\$\(|<\(/;
  for (split /[;&|(`\n]/) {
    s{(\S+)}{ my $o = $1; (my $w = $o) =~ s/\$(?=["\x27])//g; $w =~ tr/"\x27\\//d; $w =~ /^(?:git|push)$/ ? $w : $o }ge; # quoted or escaped spellings of git and push
    (my $c = $_) =~ s/^\s*(?:\w+=\S*\s+)*//;
    next if !$runs && ($c =~ /^(?:grep|rg|ag|cat|head|tail|less)\s/ || $c =~ /^$ENV{G}\s+(?:log|show|diff|commit|status|blame)(?:\s|$)/);
    print "$_\n";
  }' <<<"$lit" | grep -Eo "$gopts[[:space:]]+push([[:space:]][^;&|)\`]*)?" || true)
if [ -n "$force_main" ]; then
  pre_decide deny "flow guard: force-pushing or deleting main/master is blocked. Push a branch and open a PR."
fi
# Judge each argument of a reader on its own: quotes and dirs stripped, the example/sample/template
# names exempt per path, so a second .env.example arg doesn't waive the check.
while IFS= read -r seg; do
  set -f; set -- $seg; set +f
  for a in "$@"; do
    a="${a//[\"\']/}"; a="${a%%[<>]*}"; a="${a##*/}"
    grep -Eiq '^\.env(\.[A-Za-z0-9_.-]+)?$' <<<"$a" && ! grep -Eiq '^\.env\.(example|sample|template)$' <<<"$a" &&
      pre_decide deny "flow guard: reading .env files puts secrets in the transcript. Read .env.example or ask the user which variable matters."
  done
done < <(grep -Eio '(^|[;&|[:space:]])(cat|less|more|head|tail|bat|strings|xxd)[[:space:]][^;&|]*' <<<"$cmd" || true)

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

# 3b. The ready ledger is ready.sh's alone: a stamp written by hand would skip the bar (and, in a routine, post a
#     flow/ready check). A write that names it asks: a redirect or tee into it, in-place sed/perl, or a file verb or
#     interpreter word in the same command. Reading it (cat, tail, grep, 2>/dev/null) is fine.
if has 'ready\.tsv' && { has '(>>?|tee([[:space:]]+-a)?)[[:space:]]*[^[:space:];&|<>]*ready\.tsv' \
   || has '(^|[^[:alnum:]_.-])((sed|perl)[[:space:]]+(-[[:alnum:]]*i|--in-place)|(mv|rm|cp|truncate|dd|ln|install|python[0-9.]*|node|ruby)([[:space:]]|$))'; }; then
  pre_decide ask "flow ready: .flow/ready.tsv is ready.sh's ledger, and a stamp written by hand would skip the bar. Record steps with ready.sh record; ready.sh writes the stamp."
fi

# 3c. Ready for review: in a flow-stack repo, a non-draft PR or `gh pr ready` needs ready.sh's stamp for HEAD.
#     Only a real invocation counts: heredoc bodies are dropped, and gh must start a command:
#     line start, ; && || | ( {, if/then/!, VAR=x prefixes, or behind a wrapper (eval, sh/bash/zsh/dash/ksh, command, env,
#     time, timeout, nice, nohup, xargs, sudo, exec) with any flags of its own. Case-insensitive: case-insensitive
#     filesystems run GH as gh. A commit message that mentions it mid-sentence passes.
code="$(awk -v q="'" '
  hd != "" { t = $0; if (dash) sub(/^\t+/, "", t); if (t == hd) { hd = ""; body = "" } else body = body $0 "\n"; next }
  { print
    # <<<word is a here-string, not a heredoc; <<- lets the terminator be tab-indented. A heredoc that never
    # ends was no heredoc (a <<WORD in quotes, a comment or $((1<<X))), so its lines are code after all.
    # a << inside quotes or a comment starts nothing: match on the line with those blanked
    u = $0
    # unquote a quoted delimiter (<<'EOF') first, so the blanking below keeps it
    while (match(u, "<<-?[ \t]*[\"" q "][A-Za-z_][A-Za-z0-9_]*[\"" q "]")) { m = substr(u, RSTART, RLENGTH); gsub("[\"" q "]", "", m); u = substr(u, 1, RSTART - 1) m substr(u, RSTART + RLENGTH) }
    v = ""; sq = dq = 0
    # blank quoted text quote-aware: a backslash is literal in single quotes and escapes elsewhere
    for (x = 1; x <= length(u); x++) { c = substr(u, x, 1)
      if (sq) { if (c == q) sq = 0; continue }
      if (c == "\\") { x++; continue }
      if (dq) { if (c == "\"") dq = 0; continue }
      if (c == q) sq = 1; else if (c == "\"") dq = 1; else v = v c }
    u = v; sub(/(^|[ \t])#.*/, "", u)
    if (match(u, "(^|[^<])<<-?[ \t]*[\"" q "]?[A-Za-z_][A-Za-z0-9_]*")) {
      hd = substr(u, RSTART, RLENGTH); dash = hd ~ /<<-/; sub("^[^<]?<<-?[ \t]*[\"" q "]?", "", hd) } }
  END { printf "%s", body }' <<<"$cmd")"
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
split_awk='
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
            # "…" drops a backslash only before $ ` " \ newline; ANSI-C quoting ($ then a single quote) always does
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
'
pr_drafts() {
  awk -v q="'" -v said="(\`|$lead)gh$gopt[[:space:]]+pr[[:space:]]+(create|ready)" "$split_awk"'
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
  # `cd <dir> && gh pr create|ready …` (one plain gh call after it) is judged in <dir> when <dir> is a worktree of
  # this repo; anything else (another clone, no repo, more shell after the cd) keeps the session's root.
  rroot="$FLOW_ROOT" plain='^[[:space:]]*cd[[:space:]]+([A-Za-z0-9_./~@+,:=-]+)[[:space:]]*&&[[:space:]]*gh[[:space:]]+pr[[:space:]]+(create|ready)([[:space:]][^;&|`$()<>\\]*)?$'
  if [[ "$cmd" != *$'\n'* && "$cmd" =~ $plain ]]; then
    # resolved the way the shell's cd does (logical `..`, CDPATH off), not the way git -C does (physical)
    d="$(cd "$FLOW_CWD" 2>/dev/null && CDPATH='' cd -- "${BASH_REMATCH[1]/#\~\//$HOME/}" 2>/dev/null && pwd)" || d=""
    if [ -n "$d" ] && [ "$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" = "$FLOW_MAIN/.git" ]; then
      rroot="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$rroot" ] || rroot="$FLOW_ROOT"
    fi
  fi
  if [ "$(cd "$rroot" && "$ready" mode)" != yolo ] && ! (cd "$rroot" && "$ready" stamped); then
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
    *) # FLOW_SHIP_DRAFT=1 (set by the runner for @claude runs, out of the agent's reach): draft PRs only
      [ "${FLOW_SHIP_DRAFT:-}" != 1 ] || [[ "$1" =~ ^gh\ pr\ create\  && " $1 " == *" --draft "* ]] || return 1
      grep -Eq '^(gh pr (create|ready)( [^;&|`$<>()]*)?|gh pr merge( --(squash|merge|rebase|delete-branch))*)$' <<<"$1" ;;
  esac
}
# Turning a PR back into a draft only takes it out of review, so any auto mode may: `gh pr ready [<n>] --undo`, alone.
undo_only() { [[ "$1" =~ ^gh\ pr\ ready(\ [0-9]+\ --undo|\ --undo(\ [0-9]+)?)$ ]]; }
if grep -Eiq "$lead"'(git'"$gopt"'[[:space:]]+push|gh'"$gopt"'[[:space:]]+(pr[[:space:]]+(create|merge|ready)|release[[:space:]]+create)|npm'"$gopt"'[[:space:]]+publish)'"$cend" <<<"$code" && flow_auto \
   && ! undo_only "$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$cmd")"; then
  if ! flow_auto_ship || ! ship_allowed "$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$cmd")" \
     || ! (cd "$FLOW_ROOT" && "$(dirname "$0")/../skills/review/scripts/ready.sh" stamped) 2>/dev/null; then
    pre_decide ask "flow: outward-facing action$(flow_auto_gha && echo ". --gha adds only gh release create <tag> --target <current branch> (plain flags) to the --auto ship set.")$(flow_auto_ship && echo ". --auto ship allows only \`git push [-u] <remote> <current branch>\` (not main), gh pr create/ready (body via --body-file or --fill, no shell expansions), and gh pr merge of the current branch's PR, once review/scripts/ready.sh has stamped HEAD")."
  fi
fi
# 4c. Off a runner, auto mode also holds the GitHub writes the rule above can't see: gh api with a write method,
# or with fields (gh sends those as POST unless -X GET), and issue/PR comments, reviews and edits. --auto ship with
# a stamped HEAD lets the REST twins of gh pr create/ready through (cloud sessions have no GraphQL). Other gh write
# commands are held too, since only listed reads pass. A runner's token is already
# bounded by the workflow's grants, and the routines rely on these writes there.
gh_writes() { # gh writes in $cmd, judged on shell words (quotes and escapes resolved), one command at a time
  # a heredoc body is data unless a shell runs it (bash <<EOF, ssh host <<EOF), as in stop.sh
  awk -v q="'" '
    hd != "" { t = $0; if (dash) sub(/^\t+/, "", t); if (t == hd) { hd = ""; body = "" } else if (run) print; else body = body $0 "\n"; next }
    { print
      u = $0
    # unquote a quoted delimiter (<<'EOF') first, so the blanking below keeps it
    while (match(u, "<<-?[ \t]*[\"" q "][A-Za-z_][A-Za-z0-9_]*[\"" q "]")) { m = substr(u, RSTART, RLENGTH); gsub("[\"" q "]", "", m); u = substr(u, 1, RSTART - 1) m substr(u, RSTART + RLENGTH) }
    v = ""; sq = dq = 0
    # blank quoted text quote-aware: a backslash is literal in single quotes and escapes elsewhere
    for (x = 1; x <= length(u); x++) { c = substr(u, x, 1)
      if (sq) { if (c == q) sq = 0; continue }
      if (c == "\\") { x++; continue }
      if (dq) { if (c == "\"") dq = 0; continue }
      if (c == q) sq = 1; else if (c == "\"") dq = 1; else v = v c }
    u = v; sub(/(^|[ \t])#.*/, "", u)
      if (match(u, "(^|[^<])<<-?[ \t]*[\"" q "]?[A-Za-z_][A-Za-z0-9_]*")) {
        # the shell must be in the same command as the heredoc (cat <<EOF | bash), not a later one (…; ls /bin/sh)
        a = substr(u, 1, RSTART); sub(/.*[;&]/, "", a); b = substr(u, RSTART + RLENGTH); sub(/[;&].*/, "", b)
        run = (a b) ~ /(^|[|( \t\/"])(bash|sh|zsh|ksh|dash|ssh|\$SHELL|\$\{SHELL\})(["]?[ \t]|["]?$)/
        hd = substr(u, RSTART, RLENGTH); dash = hd ~ /<<-/; sub("^[^<]?<<-?[ \t]*[\"" q "]?", "", hd) } }
    END { printf "%s", body }' <<<"$cmd" |
  awk -v q="'" "$split_awk"'
    # unbt(s): an unquoted `…` is a command of its own, so it becomes one (split_cmds splits only `…` inside "…").
    # Each backtick also stays in the words around it, so a word cut by one (gh p`echo r` …) still reads as computed.
    function unbt(s,   i, c, o, sq, dq) {
      for (i = 1; i <= length(s); i++) { c = substr(s, i, 1)
        if (c == "\\" && !sq) { o = o c substr(s, ++i, 1); continue }
        if (c == q && !dq) sq = !sq; else if (c == "\"" && !sq) dq = !dq
        else if (c == "`" && !sq && !dq) c = "`\n`"
        o = o c }
      return o
    }
    # wr(s): 1 when s holds a gh command that is not a known read. An allowlist, so a spelling nobody listed is held:
    # a read is a literal list/view/status/diff/checks/checkout/download/watch/search/browse (clone: repo only), or
    # gh api with no method but GET/HEAD and no fields (GraphQL: a literal query without "mutation"). gh counts
    # in command position (if ! gh …, xargs -I {} gh …, sudo -u bob gh …); any other command that names gh is held
    # unless it starts with a known reader, and so is a shell reading stdin when gh is named. A $VAR command word
    # is not gh. A $ or
    # a backtick in the noun or verb (in gh api: the method, a flag position, or the start of the endpoint) is held;
    # after a literal read verb it is only an argument. gh pr create/ready/merge and gh release create belong to
    # rule 4. eval, sh -c and every substitution, flag values included, are checked as scripts of their own.
    function wr(s,   T, K, C, CS, n, i, k, j, c, r, start, g, look, noun, verb, ep, m, f, mut, ev, sh, w, lw, comp, hlp, cp, skip, wrap, dur, other, bare, anygh, bn) {
      n = split_cmds(unbt(s), T, K, C, CS); start = 1
      for (i = 1; i <= n + 1; i++) {
        if (i <= n && K[i] != "op") continue
        for (j = start; j < i; j++) if (K[j] != "op" && CS[j] && wr(C[j])) return 1
        g = hlp = skip = dur = anygh = 0; cp = 1; wrap = other = ""; noun = verb = ep = m = ""; f = mut = ev = sh = comp = 0
        for (k = start; k < i; k++) {
          if (K[k] == "op") continue
          if (ev || sh > 1) { if (wr(T[k])) return 1 }
          w = T[k]; lw = tolower(w)
          if (lw == "eval") ev = 1
          if (w ~ /^(ba|z|da|k)?sh$/ || w ~ /\/(ba|z|da|k)?sh$/) sh = 1; else if (sh && w ~ /^-[A-Za-z]*c[A-Za-z]*$/) sh = 2
          if (lw == "gh" || lw ~ /\/gh$/ || w ~ /(^|[^A-Za-z0-9_.\/-])gh([ \t]|$)/) anygh = sawgh = 1
          if (!g) {
            # gh in command position (first, or after keywords, VAR=value and wrappers with their flags) is checked
            # against the read list below. Any other command that names gh is held unless it is a known reader.
            if (!cp) continue
            if (skip) { skip--; continue }
            if (wrap == "command" && w ~ /^-[vV]$/) { cp = 0; other = "command"; continue }
            if (wrap != "" && w ~ /^-/) {
              if ((wrap ~ /^(sudo|doas)$/ && w ~ /^-[ugCDhpr]$/) || (wrap == "env" && w ~ /^-[uC]$/) \
                  || (wrap == "xargs" && w ~ /^-[IinLPdsE]$/) || (wrap ~ /^(timeout|nice|stdbuf)$/ && w ~ /^-[skn]$/)) skip = 1
              continue }
            if (wrap == "timeout" && !dur) { dur = 1; continue }
            if (lw == "gh" || lw ~ /\/gh$/) { g = 1; continue }
            bn = lw; sub(/.*\//, "", bn)
            if (bn ~ /^(if|then|elif|else|do|while|until|!|\{|time)$/ || w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
            if (bn ~ /^(sudo|doas|env|xargs|timeout|nice|nohup|exec|command|stdbuf)$/) { wrap = bn; dur = 0; continue }
            cp = 0; other = lw
            # a shell with no script reads stdin (echo gh pr close 1 | sh)
            if (bn ~ /^(ba|z|da|k)?sh$/) { bare = 1; for (j = k + 1; j < i; j++) if (K[j] != "op" && T[j] !~ /^-[A-Za-bd-z]*$/) bare = 0; if (bare) pipesh = 1 }
            continue }
          if (w ~ /^(-R|--repo|--jq|-q|--search|-S|--template|-t)$/ && k + 1 < i) { k++; continue }
          if (w ~ /^(--help|-h)$/ && T[k - 1] !~ /^-/) hlp = 1
          if (noun == "") { if (w ~ /[$`]/) comp = 1; if (w !~ /^-/) noun = lw; else if (w ~ /^(--version|--help|-h)$/) noun = "help"; continue }
          if (noun != "api") { if (verb == "" && w !~ /^-/) { verb = lw; if (w ~ /[$`]/) comp = 1 }; continue }
          # gh api: a flag position, the method or the start of the endpoint may not be computed
          if (w ~ /^[$`]/ || (w ~ /^-/ && w ~ /[$`]/)) comp = 1
          if (w ~ /^--method=/) m = toupper(substr(w, 10))
          else if (w == "--method") { m = toupper(T[++k]); if (m ~ /[$`]/) comp = 1 }
          else if (w ~ /^--(field|raw-field|input)(=|$)/) { f = 1; if (w !~ /=/) k++ }
          else if (w ~ /^--(header|preview|cache|hostname)$/) k++
          else if (w ~ /^-[^-]/) {
            # grouped short flags: -iXPOST, -iX DELETE, -if body=x
            for (j = 2; j <= length(w); j++) { c = substr(w, j, 1); r = substr(w, j + 1)
              if (c == "X") { m = r != "" ? r : T[++k]; sub(/^=/, "", m); if (m ~ /[$`]/) comp = 1; m = toupper(m); break }
              if (c ~ /[fF]/) { f = 1; if (r == "") k++; break }
              if (c ~ /[Hpqt]/) { if (r == "") k++; break } }
          } else if (ep == "") ep = lw
        }
        # git is a reader except where it runs a command of its own
        if (!g && other == "git" && anygh) for (j = start; j < i; j++) if (T[j] ~ /^(bisect|--exec|-x|-c|foreach|filter-branch|filter-repo)$/) return 1
        if (!g && other != "" && anygh && other !~ /^(rg|grep|egrep|fgrep|ag|ack|ls|cat|head|tail|less|more|wc|file|stat|echo|printf|go|cd|git|which|type|hash|whereis|man|brew|apt|apt-get|dnf|yum|pacman|port|apk|tree|du|realpath|readlink|basename|dirname|diff|jq|mkdir|touch|rm|cp|mv|ln|test|\[|true|false|command)$/) return 1
        if (g) {
          for (j = start; j < i; j++) if (tolower(T[j]) ~ /(^|[^a-z])mutation([^a-z]|$)/ || T[j] ~ /[@$`]|^--input(=|$)/) mut = 1
          if (comp) return 1
          if (hlp) { start = i + 1; continue }
          if (noun == "api") { if ((m != "" && m !~ /^(GET|HEAD)$/) || (f && m == "" && (ep != "graphql" || mut))) return 1 }
          else if (!(noun ~ /^(help|version|status|browse|search)$/ || (noun == "auth" && verb ~ /^(status|token)$/) \
                     || verb ~ /^(list|view|status|diff|checks|checkout|download|watch|search|browse|help)$/ || (noun == "repo" && verb == "clone") \
                     || (noun == "pr" && verb ~ /^(create|ready|merge)$/) || (noun == "release" && verb == "create"))) return 1
        }
        start = i + 1
      }
      return pipesh && sawgh
    }
    { all = all $0 "\n" }
    END { exit !wr(all) }'
}
if flow_auto && ! flow_on_runner && gh_writes; then
  rest_pr='^gh api( (-X|--method) POST)? repos/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pulls(/[0-9]+/ccr/ready_for_review)?( -[fF] [A-Za-z0-9_]+=[A-Za-z0-9._/-]*)*$'
  if ! { flow_auto_ship && [[ "$cmd" != *$'\n'* ]] && grep -Eq "$rest_pr" <<<"$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$cmd")" \
         && (cd "$FLOW_ROOT" && "$(dirname "$0")/../skills/review/scripts/ready.sh" stamped) 2>/dev/null; }; then
    pre_decide ask "flow: outward-facing GitHub write (gh api write, comment, review, edit). Off a runner it uses your own token, so in auto mode it waits.$(flow_auto_ship && echo " --auto ship allows only the REST twins of gh pr create/ready (gh api -X POST repos/o/r/pulls -f k=v…, …/pulls/<n>/ccr/ready_for_review), once ready.sh has stamped HEAD.")"
  fi
fi

# 5. Built-in escalations: reversible only with effort, so the human decides.
if [ -n "$force_push" ]; then
  pre_decide ask "flow guard: force-push rewrites remote history."
fi
# Unquoted like the push args above (git clean '-fd'), and long options by any prefix git accepts.
if perl -pe "$unshell" <<<"$cmd" |
  grep -Eiq -- "$gopts[[:space:]]+(reset([[:space:]][^;&|]*)?[[:space:]]--h(a(rd?)?)?([^a-z-]|\$)|clean([[:space:]][^;&|]*)?[[:space:]](--f(o(r(ce?)?)?)?|-[a-z]*f[a-z]*)([^a-z-]|\$))"; then
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
