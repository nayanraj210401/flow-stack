# Attack the premise

**Rule.** After two failed fixes, the problem is usually an assumption all your fixes share. Name it, design one observation that could disprove it, and run that observation before any further fix.

**Why.** Each new fix built on a false premise costs a cycle and learns nothing. One observation aimed at the premise can end the loop.

**Bad.** Third tweak to the retry timing, because "the request is slow".

**Good.** "All three fixes assumed the request reaches the server. Observation: server access log during the failing test." The log is empty → the test hits the wrong port.

**Check yourself.** Write: "Every fix so far assumed ___." If you can't fill the blank, you haven't stepped back far enough. Then run `challenge`: an advocate who never saw your fixes can't share their assumption.
