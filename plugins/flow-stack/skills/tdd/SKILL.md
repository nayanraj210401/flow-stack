---
name: tdd
description: Red → green → refactor for checks that run in seconds. Use for /tdd, "test first", "write a failing test".
---

# tdd

Use this when the test runs in seconds and the behavior is expressible as input → output. For UI flows, slow integration, or unclear targets, use `verify` with the repo driver instead. Don't force TDD where the feedback loop is slow.

1. **Red.** Write one test for one behavior, through the public interface (not private helpers). Run it through `../verify/scripts/evidence.sh <id>:red "<cmd>"`. It must fail, and for the right reason: the failure message names the missing behavior, not an import error.
2. **Seal** the test file if it is an acceptance or slice check.
3. **Green.** The smallest change that passes. Hard-coding is allowed only if the next red test will force generality, and you write that test immediately.
4. **Probe.** `../probe/scripts/probe.sh <id> "<cmd>"` must say TEETH.
5. **Refactor** with the test green. Run it after each step. Delete duplication, name things by the profile's Naming taste.
6. Repeat for the next behavior.

The slice-done gate (`../flow/scripts/task.sh slice <id> done`) enforces this cadence. It refuses without the red run, a fresh green, and the probe. Principle: `principle-red-before-green`.

Principle: `principle-checks-need-teeth`. Assert the observable result, including an absence when the contract requires it ("no email sent").
