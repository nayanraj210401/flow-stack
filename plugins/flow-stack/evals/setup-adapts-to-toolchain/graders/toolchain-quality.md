---
type: llm
focus: { source: file, path: fh/profile.md }
---

Judge only the "# Toolchain" section. PASS if all of these hold:
1. router is pstack:poteto-mode, justified by usage (poteto-mode used, flow never).
2. how is delegated to pstack:how (used 4 times).
3. The existing status line is chained or kept, not replaced.
4. token-saver mentions headroom (heavily used) and/or the rtk hook.
5. review is NOT delegated to shinyreview, since it is installed but never used (it may stay flow-stack's or be listed as an unused overlap in a note).
6. Lines use the "- <key>: <provider> · <why>" form.
FAIL if any of these is wrong or the section is empty.
