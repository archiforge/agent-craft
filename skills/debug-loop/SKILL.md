---
name: debug-loop
description: Use for any non-obvious bug, failing test, or production error, to run a root-cause protocol — reproduce, isolate, hypothesize, instrument, verify — with timeboxes and escalation rules.
---

# The Debug Loop

Bugs do not resist fixing; they resist understanding. This protocol replaces trial-and-error patching with a loop that converges on root cause: reproduce reliably, isolate the trigger, form one falsifiable hypothesis at a time, instrument to observe reality, and verify the fix kills the cause rather than the symptom. It ends with a regression test, because a bug is not fixed until it cannot return unnoticed.

## When to use

- A test fails and the reason is not immediately obvious from the failure output.
- Production reports an error, wrong result, or degradation and the cause is unknown.
- Behavior differs between environments (works locally, fails in CI/staging/prod).
- Something is intermittent or "flaky" — flakiness is a bug with an unsynchronized trigger, not bad luck.
- A previous fix for the same symptom did not hold.

Do NOT use the full loop for: errors whose stack trace points at a trivially wrong line (just fix it), or known missing features raising expected errors. Escalate to the loop the moment a second fix attempt fails.

## Protocol

1. **Stop. Write the bug statement.** One paragraph: expected behavior, actual behavior, exact error text or assertion, environment, and when it started. If you cannot write this, you are not ready to debug — you are ready to investigate what the bug even is.

2. **Reproduce reliably.**
   - Find the smallest, fastest, most deterministic sequence that triggers the failure. Strip inputs to the minimum that still fails; shrink data, disable noise.
   - If it will not reproduce: the trigger is hidden in what you are NOT controlling — time, ordering, randomness, network, data volume, locale, environment variables, concurrent load. Systematically vary one hidden variable at a time until it reproduces.
   - For intermittent bugs, measure frequency first (run 100 times, count failures). A repro that fires 30% of the time is workable; one that fires 0.1% needs a different lever (logs from production, stress loops, injected chaos).
   - Record the exact working repro command. Everything later depends on it.

3. **Isolate the layer.** Binary-search the system along its natural seams:
   - **Inputs:** does the failure depend on this field's value? Halve the input space.
   - **Commits:** `git bisect start`, mark good/bad commits, let history find the change that introduced it. This is the highest-yield isolation tool when the bug is recent — use it before theorizing.
   - **Code path:** disable/comment halves of the failing path (temporarily) and narrow to the exact statements involved.
   - **Environment:** run the suspect unit against the failing environment's versions, data, and config, one difference at a time, until the decisive difference appears.

4. **Form ONE falsifiable hypothesis.** Write it down in a fixed format: "The failure occurs because <mechanism> when <trigger conditions>; therefore <observable prediction>." A hypothesis with no observable prediction is a feeling. Predictions you can check cheaply: a log line that must appear, a value that must be wrong, a timing relationship, a row that must exist. While one hypothesis is being tested, park competing hypotheses in a list — do not test them simultaneously.

5. **Instrument, do not speculate.**
   - Add temporary logging, assertions, breakpoints, or tracepoints at the boundaries the hypothesis predicts (function entry, branch taken, value at handoff, timing before/after).
   - Observe reality. Compare what the code ACTUALLY did against what you believed it did. The most common debug outcome is discovering a hidden assumption was false — null handling, timezone, string encoding, integer division, retry semantics, cache staleness, transaction isolation.
   - Remove or promote instrumentation deliberately afterward: temporary prints get deleted; genuinely useful boundaries keep structured logs.

6. **Confirm or kill the hypothesis.**
   - If the prediction fails, the hypothesis is dead — discard it entirely and take the next one from the list, updated by what you learned. Do not "patch it up" with an exception to save it.
   - If the prediction holds, you have a candidate cause. Before fixing, verify it explains ALL observed facts: every symptom, the intermittency pattern, the environment difference, the timing. A cause that explains only some facts is a coincidence or a co-symptom.

7. **Fix the cause, not the symptom.**
   - The fix addresses the mechanism from step 4 — the wrong value, the missing lock, the unhandled null, the lost update — not the downstream error message.
   - Symptom checks that indicate you are about to patch, not fix: catching and ignoring the exception, adding a null guard that hides the real question of why it was null, retrying until it works, broadening a type to make the compiler quiet.
   - If the true fix is large or risky, a tactical mitigation may ship first — but only with a tracked follow-up ticket for the real fix, and never labeled "fixed".

8. **Prove the cause is dead.**
   - Write a failing regression test from the step-2 repro BEFORE applying the fix; confirm it fails; apply the fix; confirm it passes (see `test-first`).
   - Re-run the original repro command. Re-run the full suite. If the bug was intermittent, run the repro loop enough times to show the failure rate went to zero (100 clean runs for a formerly-30% failure, not 3).

9. **Record the trail.** In the PR or ticket, write three lines: cause (mechanism), fix (change), prevention (the regression test, plus any guard rail — assertion, type, lint rule, alert — that would catch this class next time).

10. **Timebox and escalate.** The loop has budgets; spending more is a decision, not a drift:
    - One hypothesis class: 30 minutes. If instrumenting has produced no new fact in 30 minutes, you are measuring the wrong thing.
    - A single bug overall: 2 hours of solo work. Past that, escalate — bring in a second reader, post the bug statement plus repro plus what you have ruled out (a written "ruled out" list is the escalation artifact; it is worth more than two more hours alone).
    - Intermittent bugs with no repro after a day of attempts: switch to production forensics (structured logs, tracing, canary instrumentation deployed to capture the next natural occurrence) rather than continuing to guess.
    - Production-impacting bugs: stabilize first (rollback, feature flag off) per the incident-response skill; the loop runs on the stabilized system.

## Hidden-variables checklist (for the will-not-reproduce case)

When a bug refuses to reproduce, one of these is usually uncontrolled. Vary
them ONE at a time, in this order of empirical hit rate:

1. **Time and timezone** — system clock, TZ env, UTC vs local assumptions,
   DST boundaries, month/day vs day/month parsing.
2. **Ordering and concurrency** — test parallelism, map/set iteration order,
   hash seeds (JVM `-XX:-UseBiasedLocking`-style randomization), request interleavings.
3. **Randomness** — unseeded generators, UUID v4 in keys, fuzz inputs.
4. **Data shape** — unicode, empty vs null vs missing, very long strings, huge
   payloads, negative and zero numbers, duplicate ids, files that are also
   directories (or symlinks).
5. **Environment drift** — env vars set in one shell and not the other,
   locale (number formatting!), ulimits, container vs bare differences,
   dependency versions resolved differently (lockfiles!).
6. **State left by earlier runs** — caches, database rows from previous tests,
   local config files, feature flags from last week's experiment.
7. **Load** — anything that works at 1 request and fails at 50: pools,
   timeouts, lock contention, memory pressure.

## Timebox and escalation table

| Situation | Budget | When exceeded |
|---|---|---|
| One hypothesis, instrumenting | 30 min | Kill or confirm the hypothesis; take the next one from the list |
| Same bug, solo, all hypotheses | 2 h | Escalate with the bug statement, repro, and the "ruled out" list |
| Intermittent, no reliable repro | 1 day | Switch to production forensics: structured logs, tracing, canary instrumentation to catch the next natural occurrence |
| Production is actively hurting | Immediately | Stabilize first (rollback, flag off); debug the stabilized copy |
| Fix did not hold (bug returned) | Immediately | Treat as "fix addressed a symptom" — restart the loop at step 4 with new facts |

The point of budgets is not haste; it is that fresh eyes and written artifacts
outperform diminishing solo intuition. The "ruled out" list you produce while
failing is the cheapest artifact a second engineer can consume.

## Worked example: the hypothesis ledger

Symptom: checkout 500s a few times per hour in prod; never locally.

- **Bug statement.** POST /checkout returns 500 "Connection timed out" ~0.2% of
  requests, since Tuesday's deploy, prod only.
- **Repro attempts.** 1,000 local requests: clean. Frequency says trigger is
  environmental. Hidden variables varied: load (yes — under 50 concurrent
  requests it reproduces in ~15 min locally). Repro = load loop + checkout.
- **git bisect.** Lands on the commit that added the coupon-verification HTTP
  call in the checkout path. Suspect acquired, not convicted.
- **Hypothesis 1.** "The coupon service times out under load because its client
  uses a 30s timeout and the pool is small." Prediction: pool-exhaustion metrics
  on our client during repro. Instrumented: no exhaustion, timeouts still occur.
  Killed.
- **Hypothesis 2.** "The new call adds latency inside the existing DB
  transaction, holding row locks past the DB wait timeout." Prediction: lock-wait
  time rises during repro; failure message originates from the DB driver, not the
  HTTP client. Instrumented: lock waits spike exactly at failures. Confirmed —
  and it also explains why local (no lock contention) never failed.
- **Fix.** Move the coupon call outside the transaction. Regression test: a load
  test asserting lock-wait time stays flat with the coupon call present.
- **Prevention.** Lint/CI rule: no outbound HTTP inside `@Transactional` scopes.

Ledger discipline is the whole trick: one falsifiable prediction at a time,
dead hypotheses recorded, all symptoms explained before fixing.

## Checklist

- [ ] Bug statement written: expected vs actual, environment, start time.
- [ ] Deterministic repro command recorded (or hidden-variable variation plan for intermittent cases).
- [ ] `git bisect` used when the bug is plausibly recent.
- [ ] Hypotheses written as mechanism + trigger + falsifiable prediction; one tested at a time.
- [ ] Instrumentation observed actual behavior at boundaries; assumptions that were false are named.
- [ ] Confirmed cause explains every observed symptom, including intermittency.
- [ ] Fix targets the mechanism; any tactical mitigation has a tracked follow-up.
- [ ] Regression test written from the repro, seen failing, then passing.
- [ ] Repro loop run enough times to prove frequency dropped to zero.
- [ ] Cause / fix / prevention recorded in the PR or ticket.

## Anti-patterns

- **Shotgunning.** Changing five things at once "to see if it helps". When the bug disappears you learn nothing about which change mattered, and you ship four untested changes.
- **Fixing the error message.** Suppressing, catching, or rewording the exception. The crash was the messenger; the cause is still there, now quieter.
- **Hypothesis hoarding.** Testing three theories at once by adding layered logging everywhere. The signal drowns, and when it passes you cannot say why.
- **Pillow-fort debugging.** Reasoning from what the code "should do" instead of instrumenting what it does. Reading is necessary; believing what you read without observation is how multi-hour sessions happen.
- **The unreproducible hunt.** Attacking an intermittent bug with intuition instead of first engineering a reliable trigger or capturing production forensics.
- **Fix-and-forget.** No regression test. The merge that reintroduces the same line six weeks later fails silently.
- **Blame-the-tool.** Concluding "the framework has a bug" without a minimal reproducer outside your code. Occasionally true; almost always an unverified escape hatch.
- **Infinite timebox.** Polishing a hypothesis for a day because "we're close". The 30-minute instrumenting rule exists precisely because "close" is a feeling instruments can contradict.

## Signals you're done

- You can state the root cause in one sentence and point to the exact line/mechanism.
- The regression test fails on the pre-fix code and passes now — demonstrated, not assumed.
- The original repro runs clean repeatedly, including under the conditions that made it intermittent.
- Every instrument you added is either removed or consciously promoted to a permanent, structured signal.
- The prevention line exists: something automated (test, assertion, alert, type) makes this class of bug more expensive to reintroduce than to avoid.
