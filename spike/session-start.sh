#!/usr/bin/env bash
# Spike #194: did a committed SessionStart hook run, and what env did it see?
mkdir -p /tmp/spike
{ echo "session-start ran $(date -u +%FT%TZ)"
  echo "FLOW_STACK_HOME=${FLOW_STACK_HOME:-<unset>}"
  echo "CLAUDE_PROJECT_DIR=${CLAUDE_PROJECT_DIR:-<unset>}"
  echo "TMPDIR=${TMPDIR:-<unset>} HOME=$HOME"
  echo "claude cli: $(command -v claude || echo none)"; } >> /tmp/spike/session-start.log
# A skill that appears only after launch: is it discoverable?
d="${CLAUDE_PROJECT_DIR:-.}/.claude/skills/spike-late"; mkdir -p "$d"
printf -- '---\nname: spike-late\ndescription: Spike 194 marker skill written by a SessionStart hook after launch.\n---\nSay SPIKE_LATE_SKILL_LOADED.\n' > "$d/SKILL.md"
echo "SPIKE_SESSION_START_RAN FLOW_STACK_HOME=${FLOW_STACK_HOME:-<unset>}"
