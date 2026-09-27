# Model the domain

**Rule.** When the logic branches on what kind of thing, or what state, something is, put that knowledge in one structure the code reads from. Don't spread it across conditionals.

**Why.** Every scattered branch is a place the next change can miss. A structure that matches the domain makes invalid states unrepresentable and deletes branches. It is also the most reliable way to add behavior by *removing* code.

**Bad.** `if (isPaid && !isTrial && !isCancelled) …` in six files; a new "paused" state adds a seventh flag.

**Good.** `status: 'trial' | 'active' | 'paused' | 'cancelled'` plus a `limits[status]` table. "Paused" adds one union member and one table row.

**Check yourself.** Is this feature growing an existing if/else chain by one more branch, or adding a boolean that must match another? Then the structure is missing. Don't force it, though: boring local code that is already clear stays.
