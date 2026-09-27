# Design it twice

**Rule.** No approach is chosen until a genuinely different one, and the null option, have been weighed against it. A second flavor of the same idea doesn't count. The alternative should come from a mind that never saw the first (the `challenge` skill's advocate).

**Why.** The first workable idea anchors every later step. Agents then spend their effort defending it: more code, more patches, more loops. Comparing costs minutes. Rebuilding costs days.

**Bad.** "Add a caching layer" → builds `CacheService`, an interface, and a TTL config. Never asks whether the slow query just needs an index.

**Good.** Brief the advocate with the problem only ("the product page p95 is 900ms; the query plan is at…"). It proposes a composite index (+1 migration line) and flags the null option (the page already has a CDN; is p95 measured before it?). The table shows the index wins: 1 line vs. 180.

**Check yourself.** Can I name the runner-up approach and the concrete reason it lost? Did I evaluate delete, reuse, and configure before build?
