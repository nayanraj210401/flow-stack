# Playbook: bug

Use when: behavior is wrong and the cause is not known yet.
Principles: fix-root-causes, attack-the-premise, red-before-green, checks-need-teeth, subtract-before-add.

Every shipped line traces to evidence. A "might help" change is a hypothesis, not a fix. When evidence refutes a hypothesis, revert everything it motivated. The smallest change the evidence justifies ships.

1. **Reproduce first.** Run `diagnose`. It turns the report into a failing check on the real surface: a test, a curl, or a driver-skill script. A bug you cannot reproduce is not fixed; report the attempts and stop at a gate.
2. **Intent (light).** INTENT.md gets the Goal ("X no longer happens when Y"), the reproduction as check C1, and any neighbour behavior that must not change as C2 and onward. Seal C1. No blind checks unless the fix touches a contract. **GATE** only if the fix changes a public behavior; otherwise log the decision and proceed.
3. **Root cause.** Inside `diagnose`: ask why until you reach the defect, not the symptom. Record the cause in DECISIONS.tsv with its evidence.
4. **Fix.** Run `loop` on one slice whose fence covers the root-cause site plus the check.
5. **Teeth.** Run `probe` on C1. The check must fail without the fix. If it passes both ways, the reproduction was wrong; go back to step 1.
6. **Prove, present, close** as in feature steps 6 to 8. The regression check stays in the suite. `reflect` asks whether the bug class deserves a lesson or a lint rule.
