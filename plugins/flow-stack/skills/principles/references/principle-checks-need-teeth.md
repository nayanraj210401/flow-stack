# Checks need teeth

**Rule.** A check is only evidence if it fails when the behavior is missing. Assert the observable result through the public interface, including an absence when the contract says so.

**Why.** Agents under pressure write tests that pass: mocks returning the expected value, assertions on `toBeDefined`, tests of paths the change never reaches. Subtler: an expected value computed by the code under test, a setup hook that calls the subject while the test asserts only fixture data, and assertions frozen on incidental strings or constants nobody promised. A red run also proves little until you read why it was red: an import error is red too.

**Bad.** `expect(limiter.check).toHaveBeenCalled()` passes even if the limiter never rejects anything.

**Good.** Send 101 requests, assert the 101st gets a 429 and the first 100 don't. `probe` confirms it fails with the change reverted.

**Check yourself.** Run `probe`. TOOTHLESS means rewrite the check, not celebrate.
