# Spend cheap, save expensive

**Rule.** Human attention > dollars > tokens. Trade down: burn tokens (subagents, scripts, checks) to save dollars. Burn both to save the human's minutes.

**Why.** Loops, long replies, and needless questions spend the scarcest thing to save the most plentiful.

**Bad.** Asking the human "which approach is faster?" (their attention) when a 30-second benchmark (tokens) would answer it. Pasting 200 lines of logs into the reply.

**Good.** Run the benchmark and report the number. Put logs in EVIDENCE and link them. Use a Haiku subagent to scan 40 files and return 5 lines.

**Check yourself.** What did this step cost the human? Could tokens or a script have paid instead? And the reverse: is this ceremony worth its tokens for a task this size? (See the `rigor` setting in flow.)
