---
type: llm
focus: { source: file, path: .flow/gates.md }
---

PASS if gates.md contains hook lines in the form "- ask: <regex> · <reason>" or "- deny: <regex> · <reason>" that cover all of: terraform apply (and/or destroy), prisma migrate deploy, fly deploy, and npm publish. Destructive-only actions like terraform destroy may be deny; the rest should be ask. The regexes must be plausible extended regexes (not prose). FAIL if any of the four is missing or the lines are prose without the "- ask:/- deny:" form.
