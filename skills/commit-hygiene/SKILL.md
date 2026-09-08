---
name: commit-hygiene
description: Use when creating commits or pull request descriptions, to keep history atomic and readable — Conventional Commits, imperative subjects within 72 characters, and evidence-carrying PR write-ups.
---

# Commit Hygiene

History is the debugging database of a project. Six months from now, someone hits a regression and asks `git log` one question: "which change did this, and why?" Atomic commits with disciplined messages answer that question in seconds; mixed mega-commits with lazy messages make it a forensic archaeology project. This skill defines the write discipline: conventional, atomic, imperative, evidence-carrying.

## When to use

- Every commit you author, human or agent.
- Preparing a branch for PR: inspecting your own commit stream and fixing it up (rebase, split, reword) before requesting review.
- Writing the PR description that frames the branch.
- Squash-merge decisions: what belongs in the final squashed message.

Do NOT skip for: work-in-progress pushes to your own feature branch (still write real messages — WIP garbage gets rebased away, and often does not), agent-generated batch changes (agents commit fast; without discipline they generate history spam fastest), or "small" fixes (small fixes are the most frequently bisected commits of all).

## Protocol

1. **Stage one logical change.** Before committing, look at `git diff --staged` and ask: can this be described in a single sentence of the form "this commit <does X>"? If you need "and also", split the staging (`git add -p` is the scalpel) into separate commits:
   - fix and its test belong TOGETHER (the test fails without the fix);
   - refactor and behavior change NEVER belong together;
   - code and its documentation updates belong together when the docs describe that code's behavior;
   - formatting noise does not belong anywhere near a logic change — keep whitespace-only changes in their own commit or drop them.

2. **Subject line: Conventional Commits, imperative, ≤ 72 characters.**
   - Format: `type(scope): imperative summary` — for example `fix(auth): reject expired refresh tokens`.
   - Types: `feat` (new user-visible capability), `fix` (bug fix), `refactor` (behavior-preserving structure change), `test`, `docs`, `chore` (tooling, deps, config), `perf`, `style` (formatting only), `build`, `ci`. Use `!` after type/scope for breaking changes (`feat(api)!: ...`) plus a `BREAKING CHANGE:` footer in the body.
   - Imperative mood: "add", "reject", "extract" — as if completing "this commit will ___". Not "added", not "adds", never "fixing stuff".
   - Lowercase subject, no trailing period, specific over generic. `fix: bug` is a non-message; `fix(order): apply discount before tax, not after` is a message.
   - The 50-character target is a soft aim; 72 is the hard ceiling (terminal and tooling truncation). If the summary does not fit, the commit is probably too big — see step 1.

3. **Body: the why, the context, the evidence.** Anything non-trivial gets a body, wrapped at 72 characters, separated from the subject by a blank line:
   - WHAT changed and WHY — the motivation, the bug's user-visible effect, the decision's context. The diff shows the how; the body is the only place the why will ever live.
   - EVIDENCE for behavioral claims: `Tests: OrderDiscountTest.applyBeforeTax (new, fails on main)`. A commit message that says "fixed" without naming its test is an unverified claim.
   - For risky changes: migration/rollout notes, feature flag name, rollback path.
   - Reference the issue (`Closes #123`, `Refs #456`) on its own line.

4. **Verify green per commit.** Each commit should build and pass tests on its own — that is what makes `git bisect` usable. If intermediate states cannot be green (rare, e.g. multi-repo coupling), say so explicitly in the body ("intermediate commit, suite green from commit 3 onward"), so bisectors do not despair.

5. **Inspect the branch stream before PR.** Run `git log --oneline main..HEAD` and read it as a reviewer will:
   - Does the sequence tell a coherent story (spec/test → implementation → fixup → polish)?
   - Any `wip`, `oops`, `fix typo again`, `actually fix`? Clean these with an interactive rebase: reword, squash fixups into their target, drop noise. The branch is your workspace; the merged history is everyone's forever.
   - Squash-merge policy: if the project squashes, the PR title/description becomes the commit — apply steps 2-3 to it with full rigor.

6. **Write the PR description as an engineering document**, not a formality:
   - **What** — the change in 2-4 sentences, plus a bullet list of the user-visible/behavioral deltas.
   - **Why** — the problem, linked issue/ticket, the decision and alternatives weighed (one short paragraph; "why not the obvious alternative" is the most valuable paragraph in the PR).
   - **How tested** — concrete evidence, not assertions: tests added/updated (names), manual verification steps performed (commands, environments, data), screenshots for UI. "Tested locally" without artifacts is not evidence.
   - **Risk & rollback** — blast radius, feature flag status, migration notes, how to revert (and any reason reverting is not enough, e.g. data migrations).
   - **Review notes** — where you want eyes first (the risky diff hunks), what you are unsure about.

7. **Check self-consistency.** Title of PR matches the change; commit types match content (`feat` commit containing only test changes is a lie that corrupts changelog tooling); every claim in the description is verifiable from the diff or CI artifacts. Agents: your last action before opening the PR is re-reading your own diff hunk by hunk — you will find at least one thing you forgot you did; put it in the description or remove it from the diff.

8. **Never rewrite shared history.** All of the cleanup in step 5 happens on YOUR branch only. Once a branch is collaborating or merged, history is immutable; you fix forward with a new commit.

## Splitting a mixed commit (the scalpel work)

You wrote one sprawling change and need clean history. On your OWN branch only:

1. `git diff main...HEAD --stat` — group the touched files by concern
   (tests-for-X / behavior-X / refactor-Y / docs).
2. Interactive rebase or soft reset to the branch point:
   `git reset --soft $(git merge-base main HEAD)` — all changes staged, none lost.
3. Stage and commit concern by concern: `git add -p` for hunk-level splits
   (a file can serve two commits: its test hunks to the fix, its refactor
   hunks to the refactor).
4. After each commit: run the fast test subset. If a mid-sequence commit cannot
   be green (test of X committed before X), reorder: implementation first,
   tests second is acceptable when each commit builds; fix+test together is
   still the ideal.
5. `git log --oneline main..HEAD` — read it as a stranger. Coherent? Ship.

Cost: ten minutes. Payoff: every future bisect through this work lands on a
single-concern commit with a self-explanatory message.

## PR description skeleton

```markdown
## What
- Replace in-memory session store with Redis; sessions survive deploys.

## Why
Deploys log out all users (#881). Considered sticky sessions (rejected:
couples routing to instances) and JWT-only (rejected: no server-side revoke).

## How tested
- Tests: SessionStoreContractTest passes against both backends;
  RevokeTest.logoutInvalidatesImmediately (new, fails on the pre-change Redis path).
- Manual: ran 2-instance compose, logged in, killed instance 1, still logged in.
- Rollback: SESSION_STORE=memory reverts behavior; data is additive (no migration).

## Review notes
Start with SessionStore.ts:41-80 (the TTL semantics) — the rest is plumbing.
```

## Examples

Good:

```
fix(order): apply discount before tax, not after

Discounts were computed on the post-tax total, overcharging
discounted orders by the tax rate times the discount. Reproduces
with any order where coupon != null and tax_rate > 0.

Tests: OrderDiscountTest.applyDiscountBeforeTax (new, fails on
pre-fix code); regressions covered for zero-tax and zero-coupon
orders.

Closes #512
```

Bad (everything wrong in one place):

```
fixed stuff and refactored + formatting

also updated some tests and the readme. tested locally
```

Why bad: not imperative, no type/scope, mixes fix + refactor + formatting + docs, "stuff" says nothing, "tested locally" names no test, and no issue link. In eleven months this line is the only thing `git bisect` will show the person debugging a pricing regression.

## Checklist

- [ ] Every commit = one logical change, describable as "this commit <X>".
- [ ] Subject: `type(scope): imperative summary`, lowercase, ≤ 72 chars, no trailing period.
- [ ] Type matches content (feat/fix/refactor/test/docs/chore...); `!` + `BREAKING CHANGE:` footer for breaking changes.
- [ ] Body on non-trivial commits: why, context, evidence, issue refs, wrapped at 72.
- [ ] Tests committed together with the fix they verify; refactors unmixed with behavior.
- [ ] Each commit builds and passes tests (or the exception is stated in the body).
- [ ] Branch stream inspected; wip/oops/typo commits rebased away before PR.
- [ ] PR description: what / why / how tested (named tests, real commands) / risk & rollback / review notes.
- [ ] Squash-merge projects the same discipline into the final commit.
- [ ] Shared history never rewritten; fixes go forward.

## Anti-patterns

- **The mega-commit.** 45 files, three concerns, message "changes for sprint 4". Unreviewable, unbisectable, unrevertable without collateral damage.
- **Fix and refactor welded together.** Forces the reviewer to verify behavior-preservation and correctness simultaneously — the two hardest checks, done at once, badly. Split them (see `refactor-guard`).
- **Passive or vague subjects.** "updated files", "misc fixes", "code review feedback". Zero information survives the merge.
- **Evidence-free claims.** "Fixes the crash" with no test, no repro, no link. If it cannot point at a test, it did not demonstrably fix anything.
- **Commit-message archaeology gaps.** Decision context that lived only in a chat thread. The body is the only durable home for the why; links rot, memory rots faster.
- **History laundering.** Force-pushing a shared branch to "clean up", invalidating teammates' baselines mid-review. Clean YOUR branch before sharing; after sharing, commit forward.
- **Changelog theater.** `feat:` on a test-only change so it shows up in release notes. Conventional types are a contract with automation; breaking it poisons generated changelogs.
- **PR descriptions as URLs.** A bare ticket link. The diff should be reviewable without hop-scotching external systems that will eventually 404.

## Signals you're done

- `git log --oneline` of your branch reads as a coherent narrative a stranger could follow.
- Any single commit reverts cleanly without breaking neighbors.
- The riskiest commit's message names its test, its motivation, and its issue.
- The PR description lets a reviewer start on the dangerous hunks first, with evidence one click away.
- A future bisect through your work lands on precise, self-explanatory steps — and you never have to say "I think this one did it".
