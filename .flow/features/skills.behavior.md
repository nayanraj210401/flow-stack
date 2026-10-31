---
id: skills.behavior
title: Skill routing and behavior
owns: plugins/flow-stack/evals/** plugins/flow-stack/agents/** plugins/flow-stack/skills/*/SKILL.md plugins/flow-stack/skills/flow/playbooks/**
entries: skill /flow-stack:<name> | prompt (auto-routing) | agent flow-stack:<advocate|checker|reviewer|worker|flow-agent>
scenario: 
status: unverified
verified:
---
# Skill routing and behavior

The model follows the skills: routes work to flow, writes intent, challenges, reviews, and replies briefly. Proven by model evals.

## Sub-features
- skills.behavior.routing · non-trivial requests route to flow; questions skip ceremony
- skills.behavior.define · intent writes runnable checks that cite feature IDs
- skills.behavior.quality · deslop/unslop/brief/claims shape output
- skills.behavior.forge · make-* skills generate repo skills

## How to get to it
- Any prompt in a session with the plugin installed; slash commands `/flow-stack:<skill>`.

## Driving it
Not scripted (see Gotchas).

## Proof
- `claude plugin eval` scores per case (see plugins/flow-stack/evals/README.md)
- absence: routing cases fail when the plugin is off (baseline arm)

## Gotchas
- No scenario on purpose: evals spend real model $ and take minutes. Run by hand:
  `cd plugins/flow-stack && claude plugin eval . --tag routing hooks define quality context forge --scaffold --allow-tools Edit Write --runs 3 --no-publish`
