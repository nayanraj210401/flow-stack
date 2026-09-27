---
name: profile
description: "View, edit, or lint your profile (who, repos, rules, taste, toolchain). /flow-stack:profile [show|edit|add rule|add taste|--check]."
disable-model-invocation: true
---

# profile

The profile is how flow-stack knows *you*. SessionStart injects its Rules, a compact Taste summary, and this repo's entry. deslop, unslop, review, and brief grade against the full Taste.

Paths are relative to this skill's base directory. The format is in `../../templates/profile.md`.

## Commands

- **show**: print the Who, Rules, and Taste sections (skip comments), plus the frontmatter budget values.
- **edit `<section>`**: make the change the human asked for, show the diff, and write it after a yes.
- **add rule `<text>`**: Rules are hard constraints, capped at 20. If the text is a preference ("prefer…", "usually…"), suggest Taste instead.
- **add taste `<area> <text>`**: append `- <today> · <text> · src: <where it came from>` under `## <Area>` (Code, Prose, UI, Naming, or Testing). If it contradicts an existing entry, propose retiring the old one (move it to `# Taste history` with the date and reason).
- **--check**: `scripts/check.sh`. It lints structure and lists taste entries older than 60 days as retirement candidates.
- **init `<preset>`**: `scripts/init.sh <preset>`. Normally `setup` runs this.

## Rules of the file

- Skills never write to the profile without showing the diff and getting a yes.
- Taste entries are dated and sourced. Taste changes over time, so the history is kept, never deleted.
- Repo-specific taste belongs in `<repo>/.flow/taste.md`, not here. Precedence: Rules > repo taste > personal taste > preset.
- The `# Calibration` table is written only by `reflect`.
