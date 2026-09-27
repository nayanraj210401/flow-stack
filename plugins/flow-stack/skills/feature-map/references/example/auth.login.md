---
id: auth.login
title: Log in
owns: src/auth/** src/routes/login.ts
entries: web /login | api POST /api/session | cli acme login
scenario: bash .claude/skills/verify-acme/scripts/login.sh
status: verified
verified: 2026-09-27 a1b2c3d
---
# Log in

A registered user signs in with email and password and lands on their dashboard. After 5 wrong passwords in 15 minutes the account is locked for 15 minutes.

## Sub-features
- auth.login.password · correct email + password starts a session and redirects to /dashboard
- auth.login.lockout · the 6th failed attempt within 15 min returns 423 and no session cookie
- auth.login.remember · "remember me" sets a 30-day cookie instead of a session cookie

## How to get to it
- Web: the "Sign in" button in the header → /login
- API: `POST /api/session` with `{email, password, remember}`
- CLI: `acme login` (prompts, stores a token in ~/.acme/token)

## Driving it
`scripts/login.sh` (in the verify-acme driver) runs all three entry points against the seed user `demo@acme.test / demo-pass`:
1. Web: Playwright opens /login, fills fields by label, clicks "Sign in", waits for /dashboard.
2. API: curl the route and check the status and `Set-Cookie`.
3. CLI: `printf 'demo@acme.test\ndemo-pass\n' | acme login` and check ~/.acme/token exists.
For lockout: 6 bad API attempts, then assert 423.

## Proof
- web: a screenshot of /dashboard showing "Welcome, Demo"
- api: 200 + `Set-Cookie: session=`; for lockout, 423 and **no** `Set-Cookie`
- cli: exit 0 and a non-empty token file

## Gotchas
- Lockout state lives in Redis; `scripts/reset.sh` clears it between runs.
- The web form is disabled until JS hydrates; wait for the "Sign in" button to be enabled.
