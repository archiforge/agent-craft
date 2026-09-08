---
name: refactor-guard
description: Use before any refactor, extraction, or rewrite, to keep changes behavior-preserving — green tests before and after, structure and behavior in separate commits, strangler-fig for rewrites.
---

# Refactor Guard

Refactoring is changing structure without changing behavior. The guard is the discipline that keeps that promise verifiable: a test suite that was green BEFORE you started, stays green AFTER every step, and no behavior change ever rides in the same commit as a structural change. When the rewrite is too large for that safety net, you do not jump — you strangle the old system piece by piece until the new one carries all traffic and the old one can be deleted.

## When to use

- Renaming, extracting functions/modules, deduplicating, inverting dependencies, splitting a god class.
- Upgrading internal structure of tests (helpers, fixtures) without changing what they verify.
- Replacing one implementation with another that must behave identically (parser, serializer, cache, client wrapper).
- Any large rewrite where "rewrite and swap at the end" is being considered — use the strangler-fig protocol below instead.
- Cleaning up code immediately before or after a behavior change, as a SEPARATE step.

Do NOT start a refactor when: the suite is red or flaky for unrelated reasons (fix or quarantine that first — a noisy net catches nothing), the code is about to be deleted anyway, or a release is in flight. Refactor on green, on main, in the quiet.

## Protocol

1. **Define the invariant.** Write one sentence: "After this refactor, externally observable behavior X is unchanged." Name what "observable" means here: public API responses, CLI output, file formats, event payloads, performance contracts. If you cannot state the invariant, you cannot detect violating it.

2. **Establish the green baseline.**
   - Run the FULL test suite on the untouched tree. Everything must pass, deterministically. Flaky tests get fixed or quarantined now, not during the refactor — a flake during refactoring is indistinguishable from a regression you just caused.
   - Record the baseline (commit SHA, suite output). This is your "before" evidence.
   - If coverage of the code you are about to move is thin, ADD characterization tests first (see `test-first`, legacy protocol). Refactoring without a net is not refactoring; it is gambling with extra steps.

3. **Commit the before-state.** Working tree clean, everything committed. Every refactor step must start from a state you can return to with one command.

4. **Take the smallest step that improves structure.** One extraction, one rename, one deduplication, one dependency inversion. Prefer mechanical, tool-assisted moves (IDE rename/extract, codemods) over hand-editing — tools do not typo. If hand-editing, keep the diff small enough that a reviewer can verify it contains NO semantic edits.

5. **Verify after every step.** Run the suite (the relevant fast subset during the loop; the full suite at commit boundaries). Green: continue. Red: you changed behavior — stop, find the divergence, fix or revert. NEVER adapt the tests to the new code during a refactor: if a test must change, either you broke the invariant (revert) or you are actually changing behavior (finish the refactor, commit it, then make the behavior change as its own change with its own test updates).

6. **Commit each coherent step separately.** One structural idea per commit, message describing the move (`refactor: extract pricing rules from Order into PriceBook`). The point is bisection: if something breaks later, `git bisect` lands on a single small structural step, not a 3,000-line omnibus.

7. **Respect the no-mixing rule.** Behavior changes and structure changes never share a commit. The classic smuggle is "while I was in there I also fixed the off-by-one". That fix belongs in its own red-green commit. If a refactor genuinely reveals a bug, note it, ticket it, and keep the refactor pure — mixing destroys the review value of both.

8. **Constrain public-surface renames.** Renaming internals is cheap. Renaming anything external (API fields, CLI flags, config keys, event names, library symbols) is a behavior change for callers: deprecate the old surface, add the new, migrate callers, then remove the old in a later release — each phase its own commit/PR.

9. **For large replacements: strangler-fig, not big-bang.** When the new implementation is substantial (new framework, rewritten parser, different storage):
   a. **Build the facade.** Route all traffic to the old system through ONE seam (interface, proxy, gateway function) if it does not already exist. Behavior unchanged; commit.
   b. **Grow the new system beside the old.** Implement incremental slices of functionality in the new system, complete with tests ported or rewritten to assert IDENTICAL behavior.
   c. **Switch traffic incrementally.** One route/case/tenant at a time, behind a flag. After each slice: compare old vs new outputs (dual-run or shadow traffic where feasible), watch error/latency metrics, keep the rollback one flag-flip away.
   d. **Delete the old system only when it carries zero traffic** — not "probably zero": verified by metrics or logs over a meaningful window. Deletion is its own commit, celebrated separately.
   e. The strangler timeline can span weeks; the invariant checks of steps 5-6 apply at every slice.

10. **Close out.** Full suite green on the final state. Diff summary: what moved where, what was deleted, and explicitly what did NOT change (the invariant from step 1, with evidence: same tests, same outputs, shadow-diff results). Update docs that referenced the old structure (see `docs-writer`) in the same PR or an immediately following one.

## Behavior change or refactor? The decision table

When you cannot tell whether your edit is structural, apply this test: "Could
this diff alter what a well-informed outside observer (a test, a client, a
log parser) sees?" If yes to any row below, it is a behavior change — separate
commit, test-first treatment.

| Edit | Refactor? | Why |
|---|---|---|
| Rename a private method | Yes | Invisible outside the unit |
| Extract a function from inline code | Yes | Same computation, new address |
| Rename an API field / CLI flag | NO | Observers bind to the name |
| Change an error message text | NO (usually) | Log parsers and users read it; treat as behavior unless the message is documented as unstable |
| Change iteration order of a Map | NO | Ordering is observable; verify no consumer depends on it — if one does, it never should have (fix THAT as its own behavior change) |
| Add caching of pure lookups | NO (perf, but observable) | Latency and staleness are observable; perf changes get their own commit and their own evidence |
| Tighten validation on input | NO | Requests that used to succeed now fail — the definition of behavior |
| Reorder independent statements | Yes | Only after proving independence (no shared side effects) |
| Change a floating-point expression's association | NO | Different rounding is a different answer |

## The safe-moves ladder

Ordered from safest to riskiest — climb only as far as the task requires:

1. **Rename** (tool-assisted, no dynamic resolution tricks).
2. **Extract function** — pure cut-and-paste of statements, inputs/outputs as
   parameters/returns; no logic edits during the move.
3. **Extract class / module** — move a cohesive cluster plus its tests.
4. **Invert dependency** — introduce an interface at the boundary, old caller
   depends on the abstraction, implementation swaps behind it.
5. **Strangler-fig replacement** — only when steps 1-4 cannot reach the goal
   (framework change, storage change, paradigm change).

Skipping rungs (jumping from "this function is messy" to "rewrite the module
on a new framework") is how refactors become rewrites become abandonware branches.

## Worked example: strangler-fig in five commits

Situation: replace a hand-rolled CSV importer (1,800 lines, no tests) with a
library-backed parser. Behavior must be identical — 40 downstream jobs consume
the output.

1. `refactor: route all CSV imports through Importer facade`
   No logic change: 14 call sites now call `Importer.parse(file)` which
   delegates to the legacy code. Full suite green. (The seam now exists.)
2. `test: characterization tests pinning legacy importer output`
   30 real-world files (sanitized production shapes, including the cursed
   quoted-semicolon file) → byte-level output snapshots. Green against legacy.
   (The net now exists.)
3. `feat: add library-backed parser behind ImportStrategy flag` (flag OFF)
   Same characterization tests run against the new parser in CI
   (parameterized over both strategies); 4 divergences found and fixed in the
   NEW parser before any traffic sees it.
4. `feat: route CSV imports through new parser (flag ON, 5% of jobs)`
   Shadow-diff job compares old/new output for every parsed file; alert on any
   divergence. Ramp 5% → 50% → 100% over a week, rollback = flag flip.
5. `chore: delete legacy importer`
   After 14 days of zero divergences at 100% — verified from metrics, not
   memory. -1,800 lines. Facade kept (it is now the public seam); flag class
   removed.

Note what never happened: no commit mixes parser replacement with behavior
changes; no step is unrevertable; at every point in time, production has a
working importer and a one-command escape route.

## Pre-flight (run before touching anything)

- [ ] Suite green twice in a row (catches flake before it catches you).
- [ ] Working tree clean; branch cut from main at a known SHA.
- [ ] The invariant written at the top of your scratch notes.
- [ ] Test runtime known (you will run it many times; if full-suite > 5 min,
      identify the fast relevant subset AND the commit-boundary full runs).

## Checklist

- [ ] Invariant stated in writing before any code moved.
- [ ] Full suite green and deterministic at baseline; flakiness fixed or quarantined first.
- [ ] Characterization tests added for any thinly covered code being touched.
- [ ] Each step is one structural idea, verified green, committed separately.
- [ ] Zero test changes during structural steps (behavior change ⇒ separate red-green change).
- [ ] Zero behavior edits smuggled into structural commits; discovered bugs ticketed instead.
- [ ] Public-surface renames staged: deprecate → migrate → remove, across releases.
- [ ] Large replacements run strangler-fig: facade, incremental slices, flag-gated cutover, verified zero traffic before deletion.
- [ ] Final full-suite run green; before/after evidence recorded.
- [ ] Docs referencing old structure updated.

## Anti-patterns

- **Refactor-with-fixups.** "I refactored it and while there also changed how retries work." The diff cannot be reviewed as behavior-preserving, the tests had to change, and the structural part loses its safety guarantee. Split. Always.
- **Rewrite-and-swap.** Building the entire replacement in a branch for months, then flipping. Merge hell, no incremental evidence, and the swap day is the scariest day of the quarter. Strangle instead.
- **Refactoring on a red net.** Starting while tests are broken or flaky "to save time". Every later red is ambiguous; you will ship a regression you attributed to pre-existing flake.
- **Test-editing during refactor.** Changing tests so the new structure passes. Tests are the specification being protected; editing them mid-refactor is moving the goalposts while the ball is in the air.
- **Structural sprawl.** Starting in `utils.js` and ending re-architecting three subsystems in one PR because each step suggested the next. Steps are cheap BECAUSE they stop; the next improvement is the next PR.
- **Cleanup stalling.** Deleting the old system "next sprint" forever. Dead parallel systems rot, drift, and confuse every newcomer; the strangler ends with deletion or it never ended.
- **Cosmetic renaming of externals.** "Just renaming" a JSON field or CLI flag is a breaking change for every caller; version it or deprecate it (see step 8).
- **Trusting the compiler as the only net.** Types catch a lot, not everything: string formats, ordering, null-vs-missing, side effects, and data all escape static checking. The suite is the net; types are a seatbelt.

## Signals you're done

- The invariant from step 1 holds and you can show it: same tests untouched and green, identical outputs on comparison cases.
- `git log` for the change reads as a sequence of small, individually revertible structural steps.
- No commit in the branch mixes behavior and structure; the review of each commit was mechanical, not forensic.
- For strangler efforts: old system deleted, flag removed, and the repo has no orphaned facade code.
- A newcomer reading the new structure does not need the old one explained — and the docs agree with the code.
