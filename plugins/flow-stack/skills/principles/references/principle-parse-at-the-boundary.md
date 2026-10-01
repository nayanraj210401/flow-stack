# Parse at the boundary

**Rule.** Data from outside (CLI args, HTTP bodies, messages, files, env, an LLM's output) is `unknown` until one function at the edge parses it into a domain type. Inside, trust the type: no re-validation, no casts, no "should never happen" checks. Shape the type so a wrong state can't be written down.

**Why.** Agents meet a type error by casting it away (`as`, `any`, `!`, `@ts-ignore`) or by adding a guard where the error surfaced. Each one moves the bug and teaches the next agent the pattern, because agents copy what surrounds them. One parse at the edge removes every guard behind it, and a tight type turns a review comment into a compile error.

**Bad.** `const msg = event.data as PlayerMsg` in the handler, `if (!msg?.track) return` three calls later, and `{ loading: boolean; error?: string; data?: Track }`, where `loading: true` with `data` set is legal.

**Good.** `parsePlayerMsg(raw: unknown): PlayerMsg | ParseError` at the listener. `type State = { kind: 'loading' } | { kind: 'error'; error: string } | { kind: 'ready'; data: Track }`. A `switch (s.kind)` whose default assigns `s` to `never`. Branded ids where two strings must not mix (`TrackId` vs `PlaylistId`). Types derived from the schema (`z.infer`) instead of a parallel hand-written copy.

**Check yourself.** Does the diff add a cast, a non-null assertion, or a suppression? Trace it to where the data entered and parse there instead. Could you write a comment explaining which field combinations are valid? Then the type is too loose. Is this a guard on an internal value? Delete it. The boundary already checked. Don't over-tighten either: strengthen a type only where a runtime check, `!`, or throw shows it's partial.
