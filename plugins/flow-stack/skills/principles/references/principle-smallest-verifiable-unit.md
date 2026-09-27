# Smallest verifiable unit

**Rule.** Every unit of work ends green with its own check. The first unit is a thin end-to-end tracer. Units are ordered with the riskiest unknowns first.

**Why.** Big-bang changes fail in ways you can't localize. Small green steps localize every failure to the last step and give the human natural review points.

**Bad.** One 1,200-line change that "adds rate limiting" and only runs at the end.

**Good.** S1: a tracer where one route returns 429 at a hard-coded limit (80 lines, check C1). S2: per-key buckets. S3: the Redis store. S4: config and docs. Each is green.

**Check yourself.** If you stopped after this unit, would the repo be green and the progress provable?
