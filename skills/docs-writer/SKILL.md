---
name: docs-writer
description: Use when writing or updating READMEs, onboarding guides, or ADRs, and whenever behavior changes in ways docs describe — write for the newcomer and prevent doc drift.
---

# Documentation Craft

Documentation is code for humans, with one brutal difference: docs cannot fail CI when they are wrong. Wrong docs are worse than missing docs, because readers trust them. This skill covers README craft, Architecture Decision Records (ADRs), and the anti-drift discipline that keeps writing true: docs live with code, update in the same change, and get deleted when they stop being true.

## When to use

- Creating or rewriting a project README (repo root, service, library, or internal package).
- Recording an architectural or tradeoff decision: ADR.
- Onboarding docs: "how to build/run/test this", environment setup, glossary.
- Any code change that alters behavior a document describes (endpoints, flags, defaults, CLI, config) — doc updates belong to that change, not "later".
- Finding and fixing doc rot during other work.

Do NOT use for: one-off notes to self (keep them out of the repo, or in clearly-marked scratch), duplicating what the type system/linter already enforces, or writing comprehensive docs for throwaway prototypes. Docs cost writing time once and reading time forever — earn both.

## Protocol

1. **Write for an explicit reader.** Before writing a line, name the reader: "a competent engineer, new to THIS repo, on their first day, with the repo cloned and nothing else." Every choice follows: what is obvious to them (git, their language's tooling) versus what is not (your service topology, internal jargon, the quirk in step 3 of setup). Never write for "everyone"; a doc for everyone is a doc for no one.

2. **README craft — the first screen does the work.** A reader decides in thirty seconds whether this is usable. Structure, top to bottom:
   - **Name + one-line description**: what this is, in the language of the problem it solves ("Kafka-to-Postgres change-data-capture daemon" — not "a tool written in Go").
   - **Badges/status**: build, license — only truthful, current ones.
   - **What it does / why it exists**: three sentences or five bullets. Include who it is for and when NOT to use it.
   - **Quick start**: the fastest honest path from clone to running. Every command copy-pasteable in order; every prerequisite named; expected output shown. If the path has a fork (OS, package manager), pick a default and link the alternative.
   - **Usage**: the main workflows with real examples — real flags, realistic inputs, actual output. One good example beats three paragraphs of description.
   - **Configuration**: the knobs that matter, defaults, and the consequence of changing each.
   - **Development**: build, test, lint, where tests live, how to run one test.
   - **Where to go next**: link design docs/ADRs, the glossary, contributing guide.
   - Order is load-bearing: nobody reads top-to-bottom; they scan for their current question. Answer questions in descending frequency.

3. **Run every command you write.** Before publishing a quick start, execute it verbatim in a clean-ish environment (fresh shell, empty cache where feasible). Docs drift starts at publication; only verified commands start true. For commands that need real values, use clearly-fake placeholder values (`API_KEY=your-key-here`) and say what replacing them does.

4. **Record decisions as ADRs.** For any decision with real tradeoffs (framework choice, data model shape, build-vs-buy, "why we don't use X"), write one ADR:
   ```markdown
   # ADR-NNNN: <Decision title>

   Status: Proposed | Accepted | Superseded by ADR-MMMM
   Date: YYYY-MM-DD

   ## Context
   <The forces at play: constraints, requirements, what made this
   a real decision rather than an obvious one. Facts only.>

   ## Decision
   <One to three sentences, active voice: "We will use Postgres and
   accept single-region writes." Include the "we will NOT" halves.>

   ## Consequences
   <What becomes easier, what becomes harder, what we accepted by
   choosing this — including the costs. Honest: this section is the
   entire value of the document.>
   ```
   Number sequentially, never edit Accepted ADRs (supersede with a new one that links back), keep them in `docs/adr/`. The un-written decision is re-litigated quarterly; the ADR ends the meeting.

5. **Kill jargon or define it.** Every internal term (service names, acronyms, domain words with special meaning) either is obvious from context or gets defined at first use — and repeated non-obvious domain vocabulary belongs in a short glossary. Newcomers lack the vocabulary to ask about vocabulary; the glossary is how they self-rescue.

6. **Prevent drift structurally.** Drift is not a character flaw; it is an unowned process. Counter it mechanically:
   - Docs live NEXT to what they describe (`docs/` in-repo, versioned with code), never in a separate wiki that updates on a different schedule than reality.
   - The PR that changes behavior includes the doc update — reviewers check docs like code (a doc-goes-stale clause in the PR checklist is how teams make this real).
   - Each long-lived doc carries a `Last verified: YYYY-MM-DD` line and an owner; stale-ness becomes visible and auditable.
   - Link-check in CI where feasible; dead links are the first symptom of abandoned docs.
   - Prefer docs that CANNOT lie: tables generated from code, examples executed as tests (`docexamples` run in CI), config docs generated from the flag definitions. A generated doc that is wrong fails a build; a hand-copied one silently misleads.

7. **Delete or mark stale docs ruthlessly.** A document you suspect is wrong gets one of three treatments, the same day:
   - verified true → update `Last verified` and move on;
   - verified false → fix it now, in this sitting;
   - unverifiable / describes a dead system → delete it (git keeps history) or mark `**STALE — do not trust, see X**` at the very top if deletion is politically blocked. A quietly-wrong doc is the single most expensive kind, because it is trusted.

8. **Edit like an engineer.** First draft long, final draft short. Cut every sentence that survives only by being unobjectionable. Prefer concrete examples over adjectives ("handles load" → "sustains 10k req/s on 2 vCPU in the load test"). Use the present tense and active voice. Read it aloud in your head; where you stumble, the reader face-plants.

## README skeleton (copy, then fill honestly)

```markdown
# <name>
<one line: what it is, in problem language>

[badges — only truthful, current ones]

## What and why
<3 sentences or 5 bullets. Include "when NOT to use this".>

## Quick start
Prerequisites: <exact versions>
<commands 1..n, each verified, in order, with expected output snippets>

## Usage
### <workflow 1>
<real command with real flags + real output>
### <workflow 2>
...

## Configuration
| Flag / var | Default | What it does |
|---|---|---|
| ... | ... | ... |

## Development
Build: <cmd> · Test all: <cmd> · Test one: <cmd> · Lint: <cmd>

## Further reading
docs/adr/ · docs/glossary.md · CONTRIBUTING.md
```

## ADR, filled in (what a good one looks like)

```markdown
# ADR-0007: Use Postgres for event storage, not Kafka

Status: Accepted (2026-03-14)
Date: 2026-03-14

## Context
Events arrive at ~200/s peak, must be queryable by support for 90 days,
and the team already operates Postgres at P0 but has zero Kafka experience.
Replay of historical events is required monthly.

## Decision
We will write events to an append-only Postgres table with a logical-slot
consumer. We will NOT introduce Kafka now; we will revisit at sustained
>2,000 events/s or when a second real-time consumer appears.

## Consequences
+ One fewer system to operate; SQL tooling for support queries.
+ Replay is `SELECT ... WHERE ts BETWEEN` — trivial.
- Polling consumers add up to 5s latency; unacceptable for any future
  real-time feature (see revisit triggers above).
- Table growth needs a partitioning job by month; owned by platform team.
```

The "revisit at X" triggers are the most valuable lines in any ADR: they turn
a decision into a falsifiable, scheduled question instead of folklore.

## Checklist

- [ ] Target reader named; content calibrated to them, jargon defined at first use.
- [ ] README first screen: what/why, quick start with verified copy-pasteable commands.
- [ ] Every command in the doc executed at least once before publishing.
- [ ] Realistic usage examples with real flags and shown output.
- [ ] "When NOT to use" stated, not implied.
- [ ] Decisions with tradeoffs captured as ADRs (context/decision/consequences), numbered, superseded-not-edited.
- [ ] Non-obvious domain vocabulary in a glossary.
- [ ] Docs versioned in-repo with behavior changes, updated in the same PR.
- [ ] Long-lived docs carry `Last verified` dates and owners; links checked.
- [ ] Stale docs deleted or clearly marked stale — nothing quietly wrong remains.
- [ ] Generated docs preferred where the doc can be made unable to lie.

## Anti-patterns

- **The TODO README.** "Documentation coming soon" for a year. Publish the honest minimum now; a true skeleton beats a promised cathedral.
- **The museum README.** Docs describing the architecture of two redesigns ago, still linked from the root. Worse than nothing: confidently wrong (see step 7).
- **Essay-first structure.** Six paragraphs of philosophy before the first command. Readers arrive with tasks; give them the command, explain the philosophy to those who scroll.
- **Unrunnable quick starts.** Steps that assume local state ("run the migration" — which one, from where?), missing prerequisites, commands that only work from a particular directory. Every unverified command is drift at birth.
- **Docs as a separate country.** An external wiki updated "when there's time", diverging from the repo on day one. If it matters, it versions with the code.
- **Decision amnesia.** Big architectural calls made in meetings or chats, never recorded, re-argued every quarter by people who lack the original context. That is what ADRs exist to end.
- **Documentation theater.** Exhaustive docs for a prototype; API reference copied from docstrings nobody reads. Volume is not usefulness; answer frequency of questions is.
- **Silent rewrites.** Editing an accepted ADR to match later reality, erasing the fact the team once chose differently and why. Supersede; never retrofit.

## Signals you're done

- A newcomer goes from clone to running using only the README, without asking anyone anything.
- Every command in the docs has been executed, and each doc says when that was last true.
- Every major decision with tradeoffs has an ADR a new team member can read and understand the WHY in two minutes.
- Code review caught a doc update missing from a behavior-change PR — the anti-drift mechanism, not heroics, is doing the work.
- Nobody asks "is this doc still accurate?" — because the answer is visible on its face: date, owner, generation source.
