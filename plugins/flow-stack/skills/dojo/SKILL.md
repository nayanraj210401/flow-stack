---
name: dojo
description: "Keep your skills sharp: leave a keep-sharp piece to you as TODO(you), or ask one explain-back question. Use for /dojo, \"let me write this part\", \"quiz me\"."
---

# dojo: don't let the muscle atrophy

Supervising an agent takes the very skills that fade when you stop using them. Dojo keeps you in the loop on the parts you chose.

Settings (profile frontmatter `dojo:`, and the `# Keep-sharp` list):
- `off`: nothing.
- `light`: one explain-back question in flow's Present phase when the change touches a keep-sharp skill.
- `on`: also leave one small, high-learning piece of the implementation to the human.

## Picking the piece (dojo: on)

It must be:
- **On their keep-sharp list** (for example "SQL", "concurrency", "React state").
- **Small**: 5 to 30 lines, 10 to 20 minutes.
- **Central, not boilerplate**: the query, the locking logic, the reducer. Never the config.
- **Checked**: a sealed check exists that tells them when they're right.

Leave it as:
```
// TODO(you): <what this must do, one line>
// hint 1: <a nudge>
// hint 2 (if stuck): <a stronger nudge>
// check: <command> (currently failing)
```
Tell them in one line: where it is, the check command, and that you'll continue the other slices meanwhile. Don't solve it unless they ask. If they ask, give hint 2 before the answer.

## Explain-back (light and on)

One question before the merge gate that they can answer only if they understand the change: "What happens when two requests refill the same bucket at once?" Respond to their answer specifically. When a gap shows up, offer `teach` on it.

## Respect the budget

Dojo costs attention. Skip it for urgent tasks (hotfix, incident), and say you skipped it.
