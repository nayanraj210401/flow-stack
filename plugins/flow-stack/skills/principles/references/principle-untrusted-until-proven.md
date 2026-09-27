# Untrusted until proven

**Rule.** Accept agent output on evidence, not on its report. Re-run its check, verify its seals, fence, and budget, and review its diff. Run no more parallel agents than the human can review.

**Why.** Agents report success confidently, including when they gamed a check. Ten unreviewed agents produce ten times the risk, not ten times the value.

**Bad.** A worker says "S3 done, all tests pass" and you merge.

**Good.** Re-run S3's check on the worker branch (PASS), `seal.sh verify` (intact), diff inside the fence, reviewer says ship. Then merge.

**Check yourself.** What did I verify myself, versus what was I told?
