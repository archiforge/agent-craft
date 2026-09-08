# Agent Craft

Explicit working protocols — spec-driven development, test-first discipline, systematic debugging, rigorous review — packaged as installable skills for autonomous AI coding agents.

![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Shell: Bash](https://img.shields.io/badge/shell-bash-4EAA25.svg)
![Skills: 8 free](https://img.shields.io/badge/skills-8_free-6E4AE9.svg)

## What it is

Agent Craft is a pack of 8 skill files (and counting) that give an autonomous coding agent — Claude Code, ZCode, Codex CLI, Cursor-style CLIs, or any tool that loads skills from YAML-frontmatter markdown — the **process discipline of a senior engineer**: write the spec before the code, the test before the implementation, the hypothesis before the fix, the review before the merge.

## Why it exists

Raw model skill is not the bottleneck; unmanaged process is. An agent with talent and no protocol will happily:

- implement a feature nobody specified, then write tests that justify the implementation,
- fix a symptom by catching the exception, mark it resolved, and move on,
- mix a refactor with a behavior change in one unreviewable commit,
- ship a diff that interpolates user input into a query string.

Every skill in this pack is a compact, enforceable protocol that prevents one of those failure modes. Each is dense, opinionated, and grounded in established engineering practice — TDD, root-cause analysis, Conventional Commits, ADRs, the OWASP Top 10, strangler-fig migrations. No filler, no hype.

## Quick start

```bash
git clone https://github.com/mohamed-bashir-dev/agent-craft.git agent-craft
cd agent-craft
./install.sh
```

That installs all 8 skills to `~/.agent-skills/skills/` (override with `INSTALL_DIR` — see below). Your agent picks them up according to its skill loader; each skill is self-contained and states clearly when it applies.

To verify your checkout:

```bash
./validate.sh
```

## The 8 free skills

| Skill | What it makes the agent do |
|---|---|
| `spec-driven-dev` | Turn a rough idea into a written spec with testable acceptance criteria — approved before implementation starts |
| `test-first` | Write the failing test before any code; minimal implementation; characterization tests for legacy code |
| `debug-loop` | Reproduce → isolate (bisect) → hypothesize (falsifiably) → instrument → verify the cause is dead, with timeboxes |
| `pr-reviewer` | Review diffs in a fixed order (correctness → concurrency → security → tests) with P0–P3 severity-tagged findings |
| `refactor-guard` | Keep refactors behavior-preserving: green before/after, structure and behavior in separate commits, strangler-fig for rewrites |
| `commit-hygiene` | Conventional Commits, atomic commits, imperative subjects ≤72 chars, PR descriptions carrying what/why/testing evidence |
| `docs-writer` | READMEs written for the newcomer, ADRs for decisions, and anti-drift rules so docs stop lying |
| `security-sweep` | Read-only pre-merge security review mapped to the OWASP Top 10, with severity-tagged findings |

## How skills work

Each skill is a single `SKILL.md`:

```markdown
---
name: test-first
description: Use whenever adding or changing behavior, to enforce ...
---

# Test-First Development

## When to use ...
## Protocol ...        (numbered steps)
## Checklist ...       (markdown checkboxes)
## Anti-patterns ...
## Signals you're done ...
```

The format is compatible with agent skill loaders that read YAML frontmatter (`name`, `description`) and load the body as instructions. The `description` tells the agent when to activate the skill; the body is the protocol itself. Nothing executes at load time — these are behavior protocols, not scripts. The only scripts in this repo are the installer, uninstaller, and validator, which you run yourself.

## Install targets

`INSTALL_DIR` controls where skills land (default `~/.agent-skills`):

```bash
# default
./install.sh

# custom root
INSTALL_DIR=~/my-skills ./install.sh
```

| Target | Command |
|---|---|
| Default shared pool | `./install.sh` (→ `~/.agent-skills/skills/`) |
| Custom directory | `INSTALL_DIR=/path/to/dir ./install.sh` |
| Per-user agent dir | point `INSTALL_DIR` at your tool's skills directory |

<!-- Detection hints for common layouts (kept as comments so this table
     stays accurate without naming tools we cannot test on every release):
     - Claude Code-style loaders: INSTALL_DIR=~/.claude  (skills land in ~/.claude/skills/)
     - Generic agents dir:        INSTALL_DIR=~/.agents  (skills land in ~/.agents/skills/)
     - Project-local:             INSTALL_DIR=.agent     (skills land in ./.agent/skills/)
     Check your tool's docs for where it loads skills from, then set INSTALL_DIR
     so that $INSTALL_DIR/skills/<name>/SKILL.md matches its expected layout. -->

Re-running `install.sh` is safe: identical files are skipped, and differing files are refused unless you pass `--force` (existing files get a `.bak.TIMESTAMP` backup first).

## Uninstall

```bash
./uninstall.sh
```

Removes only the skills that shipped with this pack (by name), from the same `INSTALL_DIR` you installed to. It never touches unrelated skills in the same directory.

## Pro Pack

There is also a **Pro Pack**: 5 advanced skills — codebase onboarding, migration planning, performance profiling, incident response, estimation realism — plus "The Agent Craft Playbook", a book-length guide to turning an AI coding agent into a senior engineer with a 30-day team adoption plan.

Get the Pro Pack here: <!-- GUMROAD_LINK -->

The free pack above is complete and useful on its own; the Pro Pack exists if you want the advanced material.

## Contributing

Issues and PRs are welcome. Skill files must pass `./validate.sh` (frontmatter, name/directory match, description ≤ 200 chars, required sections). Keep skills protocol-shaped: When to use / Protocol / Checklist / Anti-patterns / Signals you're done.

## License

[MIT](LICENSE) — © 2026 Mohamed Bashir. Use them, fork them, ship better software.
