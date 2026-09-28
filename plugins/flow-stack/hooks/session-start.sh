#!/usr/bin/env bash
# SessionStart: inject a short primer, the profile excerpt, this repo's
# entry, and the active task anchor. After compaction, re-inject the handoff.
. "$(dirname "$0")/lib.sh"
flow_init session-start
flow_enabled session-start || exit 0

source_kind="$(flow_field .source)"

router="$(profile_section Toolchain 2>/dev/null | sed -n 's/^- router:[[:space:]]*\([^ ·]*\).*/\1/p' | head -n1 || true)"

echo '# flow-stack'
if [ -z "$router" ] || [ "$router" = flow-stack:flow ] || [ "$router" = flow ]; then
  echo '- Before planning or coding non-trivial work (new feature, multi-file change, design choice, unknown bug), invoke the `flow-stack:flow` skill; it routes to a playbook. Questions and one-line edits skip the ceremony.'
else
  echo "- Workflow router: \`$router\` (the user's choice). Use it for non-trivial work. flow-stack's skills, checks, and hooks still apply; invoke \`flow-stack:flow\` only when asked."
fi
cat <<'EOF'
- Delete > add, even for small edits: before writing a new function, file, or helper, search the repo (`rg` the verbs and nouns) for one that already does it, and reuse, delete, or configure before adding.
- When the human proposes an approach or asks "is there a better way?", or you catch yourself defending your first idea, invoke `flow-stack:challenge`.
- Reply contract: answer first, ≤5 lines unless asked for more, detail goes to files. Tag claims `✓ verified (evidence)` or `~ assumed`.
- Human attention is the scarcest currency. Spend tokens (subagents, scripts, checks) to save it.
EOF

if profile_clean >/dev/null 2>&1; then
  printf '\n## Profile (%s)\n' "$FLOW_HOME/profile.md"
  who="$(profile_section Who | grep -E '^- .*:[[:space:]]*[^[:space:]]' | head -n 4 || true)"
  [ -n "$who" ] && printf '%s\n' "$who"

  rigor="$(profile_fm rigor 2>/dev/null || true)"
  [ -n "$rigor" ] && [ "$rigor" != standard ] && printf -- '- Rigor: %s (flow scales its ceremony to this)\n' "$rigor"

  rules="$(profile_section Rules | grep -E '^- [^[:space:]]' | head -n 20 || true)"
  [ -n "$rules" ] && printf '\n### Rules (hard constraints)\n%s\n' "$rules"

  taste="$(profile_section Taste | awk '
    /^## / { sub(/^## /, ""); area = tolower($0); next }
    /^- [0-9]{4}-[0-9]{2}-[0-9]{2}/ {
      line = $0; sub(/^- [0-9-]+ *· */, "", line); sub(/ *· *src:.*$/, "", line)
      print "- " area ": " line
    }' | head -n 25 || true)"
  [ -n "$taste" ] && printf '\n### Taste (current; full rubric in profile)\n%s\n' "$taste"

  toolchain="$(profile_section Toolchain | grep -E '^- [a-z-]+:' | grep -v '^- router:' | head -n 15 || true)"
  [ -n "$toolchain" ] && printf '\n### Toolchain (hand off to the listed provider; guarantees stay with flow-stack)\n%s\n' "$toolchain"

  repo_entry="$(profile_section Repos | awk -v root="$FLOW_ROOT" -v home="$HOME" '
    /^## / { if (hit) exit; block = $0 "\n"; name = $0; next }
    /^- path:/ {
      p = $0; sub(/^- path:[[:space:]]*/, "", p); sub(/[[:space:]]+$/, "", p); sub(/^~/, home, p)
      if (p != "" && (root == p || index(root, p "/") == 1)) hit = 1
    }
    { block = block $0 "\n" }
    END { if (hit) printf "%s", block }' || true)"
  if [ -n "$repo_entry" ]; then
    printf '\n### This repo\n%s\n' "$repo_entry"
  fi
else
  printf '\nNo flow-stack profile yet. When it fits, suggest `/flow-stack:setup` once.\n'
fi

[ -f "$FLOW_DIR/taste.md" ] && printf '\nRepo taste: .flow/taste.md overrides personal taste; read it before grading code or prose.\n'
[ -f "$FLOW_DIR/map.md" ] && printf 'Repo map: .flow/map.md; read it before exploring the codebase.\n'
[ -f "$FLOW_DIR/lessons.md" ] && printf 'Lessons: .flow/lessons.md; skim before planning.\n'
if [ -d "$FLOW_DIR/features" ]; then
  nfeat="$(ls "$FLOW_DIR"/features/*.md 2>/dev/null | grep -vc '/README\.md$' || true)"
  nstale="$(grep -lE '^status: (stale|broken)' "$FLOW_DIR"/features/*.md 2>/dev/null | wc -l | tr -d ' ')"
  printf 'Feature map: .flow/features/ (%s features%s). Before changing behavior, run %s impact.\n' "$nfeat" "$([ "$nstale" -gt 0 ] && printf ', %s stale or broken' "$nstale")" "$(cd "$(dirname "$0")/../skills/feature-map/scripts" && pwd)/features.sh"
fi

if [ -n "$FLOW_TASK_DIR" ]; then
  goal="$(awk '/<!--/{c=1} c{if(/-->/)c=0; next} /^## Goal/{on=1;next} on && /^## /{exit} on && NF{print; exit}' "$FLOW_TASK_DIR/INTENT.md" 2>/dev/null || true)"
  slice="$(awk '/^## /{h=$0} /^status: doing/{print h; exit}' "$FLOW_TASK_DIR/SLICES.md" 2>/dev/null || true)"
  printf '\n## Active task: %s (.flow/tasks/%s)\n' "$FLOW_TASK" "$FLOW_TASK"
  [ -n "$goal" ] && printf 'Goal: %s\n' "$goal"
  [ -n "$slice" ] && printf 'Current slice: %s\n' "${slice#\#\# }"

  if [ "$source_kind" = compact ] || [ "$source_kind" = resume ]; then
    handoff="$FLOW_TASK_DIR/HANDOFF.md"
    auto="$FLOW_TASK_DIR/HANDOFF.auto.md"
    if [ -f "$auto" ] && { [ ! -f "$handoff" ] || [ "$auto" -nt "$handoff" ]; }; then
      handoff="$auto"
    fi
    if [ -f "$handoff" ]; then
      printf '\n### Handoff (%s)\n' "$(basename "$handoff")"
      head -n 60 "$handoff"
    fi
  fi
fi

# Daily brief: once a day, when the profile asks for one and wrap hasn't run today.
digest="$(profile_fm digest 2>/dev/null || true)"
if [ -n "$digest" ] && [ "$digest" != off ] && [ "$(cat "$FLOW_HOME/digest/last" 2>/dev/null || true)" != "$(date +%F)" ]; then
  printf '\nNo daily brief yet today (digest: %s). Offer `/flow-stack:wrap` once at a natural pause.\n' "$digest"
fi

# Toolchain drift: suggest re-adapting when plugins, user hooks, MCP servers, or the status line changed.
if [ -f "$FLOW_HOME/profile.md" ]; then
  inv="$(dirname "$0")/../skills/setup/scripts/inventory.sh"
  if [ -x "$inv" ]; then
    now="$("$inv" --fingerprint 2>/dev/null || true)"
    was="$(cat "$FLOW_HOME/toolchain.fp" 2>/dev/null || true)"
    if [ -z "$was" ]; then
      printf '\nflow-stack has not adapted to this toolchain yet. When it fits, suggest `/flow-stack:setup adapt` once.\n'
    elif [ -n "$now" ] && [ "$now" != "$was" ]; then
      printf '\nToolchain changed since flow-stack last adapted (plugins, hooks, MCP, or status line). When it fits, suggest `/flow-stack:setup adapt` once.\n'
    fi
  fi
fi

exit 0
