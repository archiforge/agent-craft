---
name: pr-reviewer
description: Use when reviewing any pull request or diff, including your own, to run an ordered audit — correctness, regressions, concurrency, errors, security, tests — with P0–P3 severity-tagged findings.
---

# Rigorous PR Review

A review is a bounded engineering audit, not a vibe check. This protocol walks the diff in a fixed order so nothing important depends on mood or stamina, tags every finding with a severity (P0–P3) so the author knows what blocks merge and what does not, and ends with an explicit verdict. The reviewer's job is to find the ways this change can hurt users, the system, or the next engineer — style is the last concern, not the first comment.

## When to use

- Any pull/merge request you are asked to review, including authored-then-self-reviewed work.
- Reviewing an AI agent's diff before merging — treat it as a junior engineer's eager work: high throughput, zero earned trust, every diff fully audited.
- Pre-merge checks on hot paths: payments, auth, data migrations, concurrency, public APIs.
- You are the second pair of eyes on a hotfix going straight to production.

Do NOT use for: trivial mechanical changes (renames, formatting) where a CI check suffices — skim for scope creep and approve. Do not confuse commenting with reviewing: a review is not finished until it has a verdict.

## Protocol

1. **Read the intent before the diff.** Open the linked issue/ticket and the PR description first. Ask: what problem is this change claiming to solve? A diff without a stated purpose cannot be reviewed for fit — only for syntax. If purpose is unclear, ask and stop; do not reverse-engineer intent from 2,000 lines.

2. **Survey the shape.** Skim the file list and diff stats before line-by-line reading:
   - Is the change the size it should be for the stated goal? A "small fix" touching 40 files is either misdescribed or contains smuggled scope — flag immediately.
   - Which risk areas does it touch? Payments, auth, concurrency, migrations, public contracts, deletion paths deserve the deep pass below.
   - Test files included? A behavior change with zero test changes is a red flag to verify, not always a blocker (generated code, config), but always a question.

3. **First pass — what and why.** Understand the change as a narrative: entry point → logic → output. Do not comment yet; comments before understanding produce noise that the author then has to argue with.

4. **Second pass — the audit sweep.** Walk the diff line by line and interrogate it in this order:

   **a. Correctness**
   - Does the code do what the description claims, in all branches — including the empty, null, zero, negative, unicode, and very-long cases?
   - Off-by-one boundaries, inverted conditions, wrong operator (= vs ==, && vs ||), unit confusion (bytes/KB, cents/dollars, seconds/millis), timezone handling, integer overflow/truncation.
   - Are error paths correct: does a thrown/errored branch leave the system in a valid state?

   **b. Regressions**
   - Who else calls the changed function/endpoint/table? Grep every call site, not just the ones the author updated.
   - Is any public contract changed (signature, response shape, status codes, column meaning) without versioning or migration?
   - Config/feature flags: default values safe for environments that do not set them?

   **c. Concurrency and state**
   - Shared mutable state: what happens when two requests/threads/processes run this simultaneously?
   - Check-then-act races (read a value, decide, write — without atomicity), lost updates, non-idempotent handlers behind retries, unguarded lazy initialization.
   - Transactions: is the boundary right? Multiple writes that must be atomic committed separately? Locks held across I/O?
   - Caches: invalidation on the write path, staleness windows, key collisions across tenants/users.

   **d. Error handling**
   - Failures of external calls (network, DB, third-party): timed out? retried with backoff and jitter? Retries safe if the operation is non-idempotent?
   - Are errors caught narrowly and handled specifically, or swallowed (`catch {}`), or converted into misleading success (returning default on failure)?
   - Do error messages leak internals (stack traces, SQL, internal hosts) to end users?

   **e. Security** (run the `security-sweep` skill for depth; minimum bar here)
   - Injection: SQL/string-built queries, shell commands, template rendering with user input, path traversal on filenames, XXE on XML parsing.
   - Authorization: every new endpoint/handler checks WHO may act on WHICH object (object-level, not just "is logged in")? IDOR on new ID parameters?
   - Secrets: any credential, token, key, or internal URL introduced in the diff? (Also check test fixtures and comments.)
   - Input validation at the trust boundary; unsafe deserialization of user-controlled payloads; SSRF on user-supplied URLs.

   **f. Tests**
   - Do the tests test the BEHAVIOR described, or just mirror the implementation (change code, test breaks in lockstep)?
   - Is the interesting part covered: boundary conditions, error branches, the exact scenario from the issue?
   - Would these tests FAIL if the bug being fixed were reintroduced? If you cannot say yes, ask for the regression test.
   - Are they deterministic (no sleeps/randomness/network), or are they the next person's flaky nightmare?

   **g. Docs and UX of the code**
   - Public API/behavior changes reflected in README/docs/changelog?
   - Names accurate? Comments explaining WHY (invariants, gotchas), not narrating WHAT?
   - Anything a newcomer will misread in six months? That deserves a comment — that is documentation at the point of need.

5. **Run it.** Check out the branch, run the tests, run the linter/type-checker. Static reading misses an enormous class of trivial-but-real failures. If CI is red for unrelated reasons, say what you ran locally. Never approve "assuming CI is green" — verify.

6. **Write findings with severities.** Every substantive finding gets a tag; the author gets a merge decision, not a pile of equal-looking comments:

   - **P0 — blocks merge.** Correctness on a main path, data loss/corruption, security hole, regression for existing callers, broken build/tests, anything that hurts users or lies to them.
   - **P1 — fix before merge unless explicitly deferred.** Likely bug on an edge case, missing test for the core behavior, missing auth check on an internal-only route today but exposed tomorrow, resource leak under load.
   - **P2 — follow-up.** Real improvement, not needed in this PR: tech debt adjacent to the change, docs gap, test brittleness. Requires a ticket link in the review, so it does not evaporate.
   - **P3 — nit.** Style, naming taste, preference. Prefix with `nit:` so the author knows it is optional; never let nits dominate the review.

   For each finding: file/line, what is wrong, why it matters, and a suggested fix. Comments that state a problem without a reason are heckling.

7. **Verdict, explicitly.** End with exactly one of:
   - **Approve** — no P0/P1 outstanding; nits explicitly optional.
   - **Approve with comments** — non-blocking items listed as such; you re-checked anything risky.
   - **Request changes** — list the P0/P1s; state what approval requires.
   - **Comment only** — for input asked mid-design; not a review verdict.

8. **Review the review.** Before submitting: are all P0s really P0s (would you block a release on this)? Is every comment actionable? Did you verify the two riskiest claims by running something? Would you want to receive this review?

## Severity calibration examples

Same diff area, different severities — calibration is the review skill that
takes the longest to acquire, so anchor it:

```java
// Diff under review: a new endpoint to fetch an invoice by id
@GetMapping("/invoices/{id}")
public Invoice getInvoice(@PathVariable long id) {
    return invoiceRepo.findById(id)
        .orElseThrow(() -> new NotFoundException("invoice " + id));
}
```

- **P0** — no authorization: any authenticated user can read any tenant's
  invoice by enumerating ids. Object-level access control is missing on a data
  path; blocks merge regardless of everything else being beautiful.
- **P1** — `NotFoundException` message leaks whether an id exists to any
  authorized user of ANOTHER scope... (information disclosure, fix before merge
  unless threat model says internal-only and short-lived).
- **P2** — no rate limit on id enumeration; hardening ticket with a link.
- **P3 (nit)** — parameter named `id` while the domain vocabulary elsewhere is
  `invoiceNumber`; optional rename.

If the reviewer's only comment on this diff is the rename, the review failed.

## Findings format

```markdown
**[P0] missing object-level authz — InvoicesController.getInvoice**
What: any authenticated caller can fetch any invoice id.
Why it matters: cross-tenant data exposure via enumeration.
Suggested fix: load invoice scoped to the caller's tenant
(`findByTenantAndId(tenantOf(currentUser), id)`); add test
`getInvoice_otherTenant_returns404`.
```

Location, mechanism, impact, fix, test. A finding missing any of the five is
half-reviewable; missing "why it matters" is the most common gap.

## Checklist

- [ ] Linked issue/description read; the stated goal is clear.
- [ ] Diff shape sanity-checked: size matches claimed scope; risk areas identified.
- [ ] Every call site of changed interfaces checked for regressions.
- [ ] Concurrency story examined for shared state, races, transaction boundaries, cache invalidation.
- [ ] External-failure paths traced: timeout, retry, partial failure, poison messages.
- [ ] Security minimum bar passed: injection, authz, secrets, validation, deserialization.
- [ ] Tests verified to constrain behavior (would fail on regression), not mirror implementation.
- [ ] Tests/linter/type-check actually run by the reviewer, not assumed.
- [ ] All findings severity-tagged; P0/P1 separated from nits.
- [ ] P2s have follow-up tickets; nits marked optional.
- [ ] Explicit verdict given (approve / approve with comments / request changes).
- [ ] Docs/changelog updated for user-visible or API changes.

## Anti-patterns

- **The style-first review.** Twenty comments about formatting and none about the missing authorization check. Order exists because correctness outranks taste; taste is cheap to fix later, bugs are not.
- **Rubber stamping.** Approving because the author is senior, trusted, or fast. Trust is earned per diff; the day you rubber-stamp is statistically the day it matters.
- **Reviewing the description, not the diff.** Reading the PR narrative and concluding "sounds right". The narrative describes intent; the diff contains reality.
- **Drive-by architecture.** Demanding a redesign of the surrounding system. Review THIS change; scope creep belongs in tickets, and blocking a fix to relitigate architecture weaponizes review.
- **Nit avalanches.** A wall of P3s that buries the one P1. Tag severities ruthlessly or the author will fix the nits and argue the bug.
- **Mystery requirements.** "This feels wrong" / "not best practice" with no reason or reference. Every finding needs a mechanism: here is what breaks, here is when.
- **Blocking on the unknowable.** Demanding proofs of impossibility. State the risk, ask for the mitigation that is reasonable at this change's stakes.
- **Silent merges.** Self-merging without a second read of your own diff after CI. Self-review is a genre of proofreading, not review; at minimum re-read cold and run the sweep.

## Signals you're done

- You can explain the change's purpose and mechanism in two sentences without opening the diff.
- Every finding is tagged, located, reasoned, and actionable; the merge/no-merge decision is unambiguous from your review alone.
- You personally ran the suite (or verified CI green on the exact revision).
- The author's response requires no re-litigation of severity — the tags were defensible.
- Nothing in the "risk areas" list from step 2 went unexamined; you can name what you checked in each.
