# Redesign, don't bolt on

**Rule.** Ask: *if we were writing this today with the new requirement, what would we build?* Build toward that shape, delivered in small verifiable slices. Don't attach the requirement at the edge.

**Why.** Bolt-ons compound. Each one is small; together they make a design nobody would choose. Reshaping early costs little, and it usually deletes code.

**Bad.** Threading a new `skipValidation` flag through the controller, service, and repository for one caller.

**Good.** Notice that validation belongs at the boundary. Move it there once, and the special caller simply doesn't call it. The net diff is negative.

**Check yourself.** Did I thread a new parameter through three or more layers, or add a branch for one caller? Then redesign. Is the redesign still the smallest change that reaches the new shape (principle-subtract-before-add)?
