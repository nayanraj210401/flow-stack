# Fix root causes

**Rule.** Reproduce the failure as a check. Ask "why" until you reach the decision that was wrong. Fix it there.

**Why.** A guard at the symptom hides the bug and moves it somewhere harder to find. Special-casing the failing input is how agents "pass" without fixing anything.

**Bad.** `if (user == null) return;` added where the crash happened.

**Good.** The user is null → the session lookup misses → the cookie name changed in the auth upgrade → fix the cookie name. Keep the reproduction as the regression check.

**Check yourself.** Can you state the root cause in one sentence that names a wrong decision, not a symptom? Does `probe` show the check fails without your fix?
