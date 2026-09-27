# Encode in structure

**Rule.** A rule that matters goes where it can't be skipped: a lint, a test, a hook, a type, a script default. Prose is the fallback.

**Why.** Instructions buried in long context get ignored. Structure is enforced every time, at no attention cost.

**Bad.** Lesson: "Remember to set TZ=UTC when running tests."

**Good.** Add `TZ=UTC` to the test script. Lesson: "tests need UTC · encoded: package.json scripts.test".

**Check yourself.** Is this the second time I'm saying this? What would make it impossible to get wrong?
