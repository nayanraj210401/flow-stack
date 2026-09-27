# Minimize reader load

**Rule.** Maintainability is the effort to answer "where does X come from?" and "what can change X?". Keep both answers under 30 seconds for a new reader. Every layer and every piece of mutable state has to pay for itself by removing more load elsewhere.

**Why.** Code is read far more than it's written, and agent code gets read by humans under review pressure. Line counts and "clean architecture" are proxies. Reader load is what matters.

**Bad.** `handler → service → manager → repository → adapter`, each passing the same arguments through. A module-level flag that three functions mutate.

**Good.** The handler calls one function that owns the decision. State lives in locals or in the return values of pure functions. The invariant is named once, at the boundary.

**Check yourself.** How many files must I open to answer "what does this request do"? More than 3 means flatten it. Did this change lower reader load somewhere? A refactor that doesn't gets reverted.
