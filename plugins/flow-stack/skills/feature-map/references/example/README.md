# Feature map

The maintained, user-facing source for what this repo does and how to prove each part works.
One file per feature. Regenerate this table with `features.sh index`; edit the feature files, not this table.

| Feature | Status | Verified | Entry points | Owns |
|---|---|---|---|---|
| [auth.login](auth.login.md) · Log in | verified | 2026-09-27 a1b2c3d | web /login<br>api POST /api/session<br>cli acme login | `src/auth/** src/routes/login.ts` |

Status: `verified` (scenario passed at the recorded commit) · `stale` (owned code changed since) · `broken` (scenario failed) · `unverified`.
