# Playbook: refactor / migration

Use when: behavior must stay the same while structure changes. Renames, API migrations, dependency upgrades, sweeps.
Principles: build-the-lever, subtract-before-add, minimize-reader-load, model-the-domain, smallest-verifiable-unit.

1. **Pin the behavior.** If the area lacks coverage, first write a characterization check (snapshot, golden output, or equivalence script) that captures current behavior. Type-check and lint are not a pin. Then run the full relevant check suite through `evidence.sh` with the label `baseline`. Those checks are the acceptance checks. **Prove the pin bites** before trusting it: break the behavior on purpose (a one-line change, stashed), run the pin through `evidence.sh` with the label `pin:teeth`, confirm it FAILs, then restore. A pin that stays green is TOOTHLESS; strengthen it. Then seal them. A refactor that needs a check changed is not a pure refactor. Raise a gate.
2. **Intent (light).** Goal, the before-and-after shape, and Non-goals (especially "no behavior change"). Name the target as if built today with everything known now (principle-redesign-not-bolt-on). Run `challenge` on the target shape. **GATE** on the target shape.
3. **Lever first.** If the change repeats more than about 5 times, write a codemod or script (in `.flow/tasks/<slug>/`) and run it, instead of editing by hand. The script is the reviewable artifact.
4. **Slice.** Split into units that each keep the suite green. Delete the dead paths first (subtract before add). Each slice's diff budget is strict; a slice over budget gets split.
5. **Loop** each slice. All baseline checks must pass after every slice, not only at the end.
6. **Migrate callers, then delete the old path** in the same task. No compatibility shims left behind unless the human asks for them; if they do, log each one as `debt`.
7. **Worth keeping?** The success measure is lower reader load (principle-minimize-reader-load): fewer layers to trace, less state to hold, and fewer branches. Report the before-and-after (files to open to answer the key question, and diffstat net lines). If reader load didn't drop, revert.
8. **Prove, present, close** as in feature. `tour` should mark mechanical hunks as safe to skip. Refactor slices set `red: n/a behavior-preserving` and `teeth: n/a behavior-preserving, pin probed at baseline`. The pin passes on the old code by design, so reverting a slice can't make it fail; step 1's `pin:teeth` is the teeth proof.
