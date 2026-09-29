---
name: gate
description: "Decide what needs the human: reversible choices proceed and are logged, irreversible or taste choices are asked, batched into one message. Use before asking the human anything."
---

# gate: ask rarely, ask well

Principle: `principle-human-owns-irreversible`.

## Classify before asking

| Decision | Examples | Action |
|---|---|---|
| **Answerable by running something** | "does this approach work?", "is it faster?" | Don't ask. Run the experiment. |
| **Reversible, inside intent** | naming, internal structure, which helper to use, test layout | Proceed. Log with `task.sh decide agent yes …` |
| **Taste with no profile entry** | UI copy, API naming visible to users, a new pattern | Ask, and offer to save the answer as a Taste entry |
| **Irreversible or outward-facing** | push, merge, deploy, publish, migrations, deleting data, sending messages, spending money, anything in `.flow/gates.md` | Ask, always |
| **Changes the contract** | a sealed check or INTENT edit, scope growth, a non-goal becoming a goal | Ask, always |

Repo-specific irreversible actions live in `.flow/gates.md`. `make-gates` generates it, and its hook lines are enforced by the guard hook.

## Ask well

One message, with every open gate in it:
```
GATE · <decision, one line>
  A) … (recommended: <why, one line>)   B) …
  evidence: <file:line / EVIDENCE label>
```
Use `AskUserQuestion` when available, with the recommended option first. Never ask a question you would answer "it depends" to. Resolve the dependency first.

## After the answer

Log it: `../flow/scripts/task.sh decide human <yes|no> "<decision>" "<their reason>"`. If it reveals a preference that will recur, note it for `reflect` to propose as a Taste entry.

## Auto mode

After `--auto` in a prompt (until `--no-auto`), nobody answers. Don't ask. Take the recommended option on reversible decisions and log it `who=agent`. Queue the rest in `.flow/tasks/<slug>/GATES.md`. The hooks enforce this: an ask comes back as a deny that says "queue it".

## Blocked and waiting

The Notification hook pings the human through the profile's `notify` target. Before going idle on a gate, finish every piece of work that doesn't depend on the answer.
