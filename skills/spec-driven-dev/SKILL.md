---
name: spec-driven-dev
description: Use before writing code for any non-trivial feature, when the request is vague, to produce a written spec with goals, non-goals, and testable acceptance criteria approved before implementation.
---

# Spec-Driven Development

Turn a rough idea into a written specification that a reviewer can approve and an implementer (human or agent) can execute without guessing. The spec is the contract: code that satisfies the acceptance criteria is done; code that does not is not done, no matter how elegant it is.

## When to use

- A stakeholder, ticket, or user asks for a feature described in one sentence ("add export to CSV", "make the dashboard faster").
- You are an agent about to start implementing anything larger than a trivial fix and no spec, design note, or acceptance criteria exist yet.
- Requirements are spread across a conversation, your memory of a conversation, or nothing at all.
- The cost of building the wrong thing exceeds the cost of writing one page first.
- Multiple people (or multiple agent sessions) will touch the work and need a shared source of truth.

Do NOT use for: one-line fixes, typo corrections, mechanical renames, or anything where the change is fully described by an existing failing test. Specifying those adds latency without reducing risk.

## Protocol

1. **Capture the request verbatim.** Copy the exact words from the ticket, chat, or issue into the spec under "Original request". Never paraphrase during capture — paraphrasing is where requirements get silently "improved" and lost.

2. **Establish context before proposing anything.** Answer, from the codebase and the requester, the five context questions:
   - Who uses this feature, and what job are they doing when they reach for it?
   - What happens today instead (current behavior, workaround, error)?
   - What breaks or hurts if we ship nothing?
   - What systems does this touch (entry points, data stores, external APIs)?
   - What constraints are non-negotiable (deadlines, compliance, scale, supported versions)?

3. **Interview for the gaps.** If the request does not answer the context questions, ask a small, numbered set of targeted questions — at most five, ranked by how much the answer changes the design. State your working assumption for each question you do not ask, so the reviewer can correct assumptions cheaply instead of answering everything.

4. **Draft the spec from the template** (below). Rules while drafting:
   - Goals are user-visible outcomes, not implementation tasks.
   - Non-goals are explicit: name the attractive adjacent work you are deliberately NOT doing, so reviewers do not assume it is included.
   - Acceptance criteria are testable statements in the form "Given X, when Y, then Z". Each must be verifiable by a test, a command, or an inspection — never "works correctly" or "is fast".
   - Record open questions separately; never leave a decision buried inside a paragraph.

5. **Self-review against the ambiguity sweep.** Search your draft for these words: "should", "probably", "etc.", "and so on", "appropriate", "reasonable", "if needed", "user-friendly". Each occurrence is either replaced with something concrete or moved to Open questions. A spec containing "etc." is not a spec; it is a wish.

6. **Submit for approval.** Present the spec to the requester or reviewer with a one-paragraph summary and the acceptance criteria list visible without expanding anything. Explicitly ask for one of: approve, approve with changes, or reject. Silence is not approval.

7. **Iterate until approved.** Apply requested changes and re-present. Keep every revision — do not delete prior drafts, mark them superseded. When the reviewer says approve, mark the spec `Status: Approved` with the date and the approver's name. Only now is implementation allowed to start.

8. **Implement against the spec, not against memory.** Before each unit of implementation, re-read the relevant acceptance criterion. Build the acceptance criteria as tests first where feasible (see the `test-first` skill). When reality contradicts the spec — the codebase cannot support an assumption — stop and amend the spec rather than silently deviating.

9. **Handle change requests as spec deltas.** New requirements discovered mid-implementation get appended to the spec as dated amendments with updated acceptance criteria, then approved, then implemented. Never let the running code become the only record of what was agreed.

10. **Close the loop.** When implementation is complete, walk the acceptance criteria one by one and annotate each with the evidence that it is met (test name, command output, screenshot reference). Any criterion without evidence is unfinished. File the spec with the code (see `docs-writer`) so the next reader finds it.

## Worked example: one sentence to testable criteria

Original request (verbatim from a ticket):

> "Users keep asking for CSV export on the reports page."

Weak spec (what NOT to produce):

```markdown
## Goals
- Add CSV export to the reports page.
- Should be fast and handle large reports.
```

Nothing here is testable, "fast" is undefined, and "large" is undefined. A reviewer cannot
reject any implementation against it, so it gates nothing.

Strong spec (excerpt):

```markdown
## Goals
- A user viewing a report can download the currently filtered result set as CSV.

## Non-goals
- Excel (.xlsx) formatting, scheduled/recurring exports, export of saved reports
  by email. Each is a plausible follow-up; none is needed to close this ticket.

## Acceptance criteria
- Given a report with filters applied, when the user clicks "Export CSV",
  then the downloaded file contains exactly the rows currently visible
  (same filtering, same sort order, same column set).
- Given a report with zero matching rows, when the user exports,
  then the file downloads successfully and contains only the header row.
- Given a report with 100,000 matching rows, when the user exports,
  then the download starts within 5 seconds (the export may stream).
- Given a cell value containing a comma, quote, or newline, when exported,
  then the CSV quotes and escapes it so standard parsers round-trip it.
- Given a user without the "reports.export" permission, when the export button
  renders, then it is disabled and the export endpoint returns 403.
```

Notice what the strong version does that the ticket did not: it names the edge
cases (empty set, escaping, permission, large N) BEFORE implementation, when
resolving them is a conversation rather than a rewrite.

## Spec template

```markdown
# Spec: <short feature name>

Status: Draft | Approved (date, approver) | Superseded by <link>
Author: <who wrote it>
Reviewers: <who must approve>

## Original request
<verbatim quote or link to ticket/issue/conversation>

## Context
<The five context answers: users, current behavior, cost of nothing,
affected systems, hard constraints. Facts, not opinions.>

## Goals
- <User-visible outcome 1>
- <User-visible outcome 2>

## Non-goals
- <Attractive adjacent work explicitly excluded, and why>

## Proposed approach
<One to three paragraphs. Just enough design to justify the acceptance
criteria: components touched, data flow, key tradeoffs considered.
Not a full technical design unless the change is architectural.>

## Acceptance criteria
- Given <precondition>, when <action>, then <observable result>.
- Given <precondition>, when <action>, then <observable result>.
- <Each criterion independently testable; no criterion may depend on
  another criterion being tested first.>

## Open questions
- <Q: question — Owner: who resolves — Needed by: before/after implementation>

## Out of scope
- <Anything a reviewer might mistake for being included>
```

## Checklist

- [ ] Original request captured verbatim, not paraphrased.
- [ ] All five context questions answered or explicitly listed as assumptions.
- [ ] Goals written as user-visible outcomes, not tasks.
- [ ] Non-goals name at least one tempting adjacent exclusion.
- [ ] Every acceptance criterion is a testable Given/When/Then statement.
- [ ] Zero occurrences of "etc.", "as needed", "appropriate", "should probably".
- [ ] Open questions listed with owners, none load-bearing for starting work (or resolved).
- [ ] Spec explicitly approved by the requester before implementation began.
- [ ] Mid-implementation discoveries produced spec amendments, not silent drift.
- [ ] Every acceptance criterion annotated with evidence at completion.

## Anti-patterns

- **Specifying after coding.** Writing the spec to match what you already built is documentation of guesses, not a contract. If code exists first, say so honestly and spec what remains.
- **Implementation disguised as requirements.** "Add a Redis cache with LRU eviction" is a design, not a goal. The goal is "dashboard loads in under 2 seconds at p95"; the cache is one candidate solution the spec may propose but not presume.
- **Untestable acceptance criteria.** "The UI is intuitive", "performance is good", "errors are handled gracefully" cannot gate completion. Replace with measurable statements or admit they are aspirations and move them to a separate section.
- **The infinite spec.** Expanding scope until the spec becomes a book. If the spec exceeds roughly two pages for a normal feature, the feature is too big — split it into staged specs.
- **Approval theater.** Presenting the spec in a way nobody reads (wall of text, no summary, no explicit ask), then treating no objection as approval. Require an affirmative signal.
- **Freezing nothing.** Leaving the status as "Draft" forever while implementing, so later changes have no baseline to amend.
- **Spec sprawl.** Ten overlapping documents for one feature. One spec per unit of deliverable work; supersede, never fork.

## Signals you're done

- A reader who has never seen the feature can list what it will do, what it will not do, and how completion will be judged — using only the spec.
- The approver has affirmatively approved, and the spec records who and when.
- Every acceptance criterion maps to a test, command, or inspection that exists and passes.
- Nothing in the implementation contradicts the spec; all deviations are recorded amendments.
- The spec lives with the repository (or is linked from it), not in a chat scroll or a closed window.
