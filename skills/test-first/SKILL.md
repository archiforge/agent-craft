---
name: test-first
description: Use whenever adding or changing behavior, to enforce test-driven development — no implementation before a failing test exists — and characterization tests before touching untested legacy code.
---

# Test-First Development

Write the test before the code, watch it fail for the right reason, write the minimum code that makes it pass, then refactor with the safety net in place. For agents this discipline matters more than for humans: an agent that writes implementation first will unconsciously write tests that justify the implementation instead of constraining it. The failing test is the proof that the test can fail — a test that has never failed is a test that proves nothing.

## When to use

- Writing any new function, module, endpoint, or behavior.
- Fixing a bug: the fix begins with a test that reproduces the bug and fails on the current code.
- Changing existing behavior: update or write the test that encodes the NEW behavior first, watch it fail, then change the code.
- Touching legacy code with no tests: write characterization tests FIRST to pin down current behavior (see the legacy protocol below), then change anything.
- Reviewing your own completed work: no new behavior should exist without a test that would fail if it regressed.

Do NOT use test-first for: throwaway spikes and exploratory probes (but then the spike's code is thrown away or redone test-first — never "kept because it works"), pure configuration, or documentation. If you find yourself testing a language feature rather than your logic, stop.

## Protocol

1. **Pick the next smallest behavior.** From the spec or task, choose the single smallest observable behavior not yet implemented. If you cannot name the behavior in one sentence ("rejects a renewal date in the past"), the unit of work is too vague — decompose further.

2. **Write one failing test.**
   - Name the test after the behavior: `rejectsRenewalDateInThePast`, not `testDateLogic2`.
   - Arrange-Act-Assert: set up the minimal state, perform one action, assert observable outcomes.
   - The test must FAIL when run. Run it. Confirm it fails for the RIGHT reason — the assertion or a missing piece, not a compile error in the test itself, a missing import, or a typo. A test that fails for the wrong reason will pass for the wrong reason later.
   - If the test passes immediately, you have either already implemented the behavior (fine — but confirm the test fails when you temporarily break the implementation) or the test tests nothing. Investigate before proceeding.

3. **Write the minimum implementation that makes the test pass.** Resist implementing the next behavior, the general case, or "while I'm here" robustness. The point of minimal code is that every line of production code exists because a test demanded it. You may leave the code ugly — the next step fixes structure, not behavior.

4. **Run the full test suite, not just the new test.** The new test passes; confirm you broke nothing else. If something else fails, you have learned something about coupling — fix that before adding more code.

5. **Refactor.** With the suite green, improve names, extract duplication, simplify conditionals. Run the tests after each refactor step. If a refactor breaks a test, revert the refactor — the tests are the specification, and refactoring must not require changing them.

6. **Repeat.** Loop steps 1-5 for the next behavior. Commit at coherent green points (see the `commit-hygiene` skill): red-green-refactor cycles are cheap; lost context is not.

7. **For bug fixes, the reproduction test is mandatory, not optional.**
   - Write a test that reproduces the reported bug exactly, using the smallest real-world input that triggers it.
   - Confirm it fails against the buggy code.
   - Fix the code until it passes.
   - Do not delete or weaken the test afterward; it is the regression guard. If the test is flaky, fix its determinism (freeze clocks, seed randomness, control concurrency) — never add `sleep` to make it pass.

8. **Legacy protocol: characterization tests before change.**
   - Before modifying untested legacy code, write tests that capture its CURRENT behavior — including behavior that looks wrong. You are not approving the behavior; you are pinning it so your change's effects become visible.
   - Choose inputs from real production shapes: actual request payloads, real database rows (sanitized), boundary values. Coverage from synthetic happy-path inputs will miss the landmines.
   - Where current behavior is unknown, write the test with your GUESS at the behavior, run it, and let the failure tell you the truth. This is the fastest known way to read legacy code.
   - Only after a characterization net exists (even a partial one around the code you touch), make your intended change — and now update the characterization tests deliberately, one assertion at a time, each update justified by the new spec.

9. **Keep tests honest.**
   - One logical assertion cluster per test: a test should fail for one reason.
   - Test through the public interface; do not test private internals you will want to refactor. If testing private details feels necessary, the design is telling you a class wants to be extracted.
   - Never mock what you do not own without an adapter; mocks of third-party clients drift from reality silently.
   - Deterministic or explicitly labeled: time, randomness, concurrency, and network must be controlled or faked, and the test suite must be runnable offline and in parallel.

10. **Watch the suite's signal quality.** If you find yourself modifying tests in every refactoring step, they are over-specified. If a bug escaped that a test should have caught, tighten that test before writing any new one. The suite is an instrument; recalibrate it when its readings drift.

## Worked example: one red-green-refactor cycle

Task: "A renewal date must not be in the past."

**Red.** Write the test; run it; watch it fail for the right reason (the method
does not yet reject — not a compile error):

```java
@Test
void rejectsRenewalDateInThePast() {
    var policy = new RenewalPolicy(clock.fixedAt("2026-09-08T10:00:00Z"));
    assertThatThrownBy(() ->
        policy.renew(DateInput.of("2026-09-07")))
        .isInstanceOf(InvalidRenewalException.class)
        .hasMessage("renewal date must not be in the past");
}
```

Failure observed: `Expected InvalidRenewalException ... but no exception thrown`.
The test failed on the assertion — the right reason.

**Green.** Minimal code only: add the check that throws. No validator framework,
no error-code registry, no "while here" date formatting:

```java
public void renew(LocalDate date) {
    if (date.isBefore(today())) {
        throw new InvalidRenewalException("renewal date must not be in the past");
    }
    // ...
}
```

Test passes. Full suite passes.

**Refactor.** The check is fine; nothing to extract yet — so change nothing.
Forcing a refactor every cycle is its own anti-pattern. The cycle ends when the
code is honest, not when it is clever.

Next behaviors, each their own cycle: same-day renewal (allowed? new test decides),
timezones (whose "past"?), and the exact error surface callers will see.

## Choosing the test double

| Situation | Use | Because |
|---|---|---|
| Slow/external dependency behind your interface | Fake (in-memory impl) | Fast, behavior-real, survives refactor of call sites |
| Third-party client with no interface of yours | Thin adapter you own + fake adapter | Never mock what you don't own; the adapter is the mock point |
| Expensive edge condition (network fault, 429) | Stub at the boundary returning the fault | Deterministically produces conditions you cannot order on demand |
| Verifying an interaction itself ("email sent once") | Mock with call assertions | The call IS the behavior under test |
| Anything you can do for real in <10ms (pure logic, in-memory store) | The real thing | Doubles exist to remove cost, not reality |

Default to the real thing and the fake; reach for interaction mocks last — they
are the double most likely to pass while the system is actually broken.

## When a test is the wrong answer

- **Testing the language/framework.** `assertTrue("a".equals("a"))` tests the
  compiler. Test YOUR logic, not the platform it runs on.
- **Testing private mechanics you intend to change.** If the test reaches into
  private state, every refactor breaks it; that test is a cage. Test through
  the public surface, or extract the mechanics into a unit with a public one.
- **100% branch coverage on trivial DTOs.** Getters and builders do not earn
  tests; the logic that DECIDES things does.
- **Spike code.** Explore freely, test nothing — then throw the spike away and
  reimplement test-first. "Keep the spike because it works" is how untested
  cores accrete.
- **Timing/perf assertions in the unit suite.** Wall-clock asserts flake on
  loaded CI machines; perf belongs in a benchmark harness with its own
  methodology (see the `perf-profiling` skill).

## Checklist

- [ ] A failing test existed BEFORE each new behavior was implemented.
- [ ] Each new test was observed failing, for the intended reason.
- [ ] Tests are named after behaviors, readable as specifications.
- [ ] Implementation added only what the current failing test demanded.
- [ ] Full suite run after each green step; failures fixed before proceeding.
- [ ] Refactoring done only with the suite green, in steps, never mixed with new behavior.
- [ ] Bug fixes began with a failing reproduction test that remains in the suite.
- [ ] Legacy changes preceded by characterization tests pinning current behavior.
- [ ] No test depends on wall-clock time, real network, ordering, or shared mutable state — or is explicitly marked and isolated.
- [ ] No assertion was weakened or deleted merely to make a suite pass.

## Anti-patterns

- **Test-after.** Writing all the implementation, then backfilling tests. The tests inherit every misunderstanding in the implementation and rarely challenge edge cases; you verify what you built, not what was asked.
- **Testing the mock.** Over-mocked suites where elaborate fake setups pass while real integrations fail. Mock at architectural boundaries (your interfaces), not inside third-party clients.
- **Assertion-free testing.** Tests that execute code but assert only "does not throw". They catch crashes, not wrong answers.
- **Snapshot everything.** Giant golden files that get blindly regenerated on every change. Snapshots are appropriate for truly structural output (renderers, serializers); regenerating without human diff review turns the suite into a rubber stamp.
- **Chained tests.** Tests that depend on execution order or on each other's side effects. One `fit`/`only`-style accident later, the suite lies.
- **Sleep-based synchronization.** `sleep(1000)` to wait for async work. Use deterministic synchronization (await, polling with timeout on a condition, test clocks).
- **Catching-and-passing.** try/catch around the act step that swallows the exception and lets assertions be skipped. Assert the specific exception type and message.
- **Coverage theater.** Chasing a coverage percentage with meaningless tests. Coverage tells you what was executed, never what was verified.
- **Deleting the canary.** Removing a flaky-but-real regression test instead of fixing its determinism. The bug it caught will return.

## Signals you're done

- Every behavior in the change has a test that demonstrably failed before the behavior existed and passes after.
- The suite runs green deterministically, offline, repeatedly (run it three times in a row before claiming done).
- You can delete any production module and name exactly which tests will fail — if you cannot, coverage is decorative.
- Bug reports arriving for this area now arrive with a failing test attached, because the habit is institutional.
- Refactoring feels safe and boring. If refactoring this code feels risky, the net has holes — fix the net first.
