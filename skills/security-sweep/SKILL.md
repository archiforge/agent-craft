---
name: security-sweep
description: Use before merging changes that touch user input, data access, auth, external calls, or dependencies, to run a read-only OWASP-mapped security review with severity-tagged findings.
---

# Pre-Merge Security Sweep

A focused, read-only security pass over a diff or a feature area, mapped to the OWASP Top 10 categories that actually appear in day-to-day code review: injection, broken access control, secrets, vulnerable dependencies, unsafe deserialization, and input validation failures. The sweep reports findings with severity; it does not fix them. Fixing mid-survey truncates the search at the first finding — the second vulnerability then ships. Survey fully, then fix deliberately.

## When to use

- Before merging anything that touches: user input of any kind, database queries, shell/process execution, file paths, authentication or authorization, external HTTP calls, serialization formats, or dependency manifests/lockfiles.
- Before first exposure of new endpoints, webhooks, admin surfaces, or file-upload paths.
- Periodic re-sweeps of security-critical areas (auth, payments, tenant isolation) even without a diff.
- Reviewing an agent's output before merge — agents will happily interpolate user input into SQL strings with the best of intentions.

Do NOT use for: full penetration testing, threat modeling a new system from scratch (do that at design time), or compliance audits. Those are different disciplines; this is the disciplined pre-merge pass.

## Ground rules

- **Read-only.** During the sweep you change nothing: no edits, no commits, no dependency upgrades. Findings get recorded; fixes happen after the survey completes, prioritized.
- **Follow the data.** Security bugs live where data crosses trust boundaries. Trace each piece of external input to every place it lands; examine every landing site.
- **Assume the attacker is a user.** Not a wizard: an authenticated, ordinary user who is curious, malicious, and has curl. Ask "what can a legitimate user make this code do that it was never meant to do?"

## Protocol

1. **Scope the sweep.** List what is in bounds: the diff's files plus their blast radius (every caller of changed functions, every consumer of changed endpoints/tables). Note the trust boundaries in play: HTTP entry points, message queues, file uploads, third-party callbacks, background jobs, CLI args. Write the list — an unswept boundary discovered at review time is a finding against the sweep itself.

2. **Map external input to landing sites.** For each input source (request params, bodies, headers — including spoofable ones like `X-Forwarded-For` — cookies, URLs, uploaded files, queue messages, environment config), trace the flow and mark each use: query, template, command, path, redirect, log line, stored value rendered later (stored XSS), URL fetched (SSRF). This map IS the sweep's worklist.

3. **Run the category checks** (OWASP-mapped), in this order — likelihood-first for typical code:

   **A03: Injection.**
   - SQL/NoSQL: any string-concatenated or interpolated query? Parameterized everywhere, including dynamic ORDER BY / LIMIT / IN-clauses (the classic hiding spots)? ORM `raw()` calls audited line by line?
   - OS commands: `exec`, `system`, shell-out with interpolated input? Pass argument arrays, never shell strings; if a shell is unavoidable, an allowlist of permitted characters — not a denylist of "dangerous" ones.
   - Template injection: user input in template SOURCE (not template variables) — `render(user_string)` is code execution.
   - Path traversal: filenames/paths from users joined into filesystem paths? `../` normalized away? `realpath` confined to the intended base directory? Same class for archive extraction (zip-slip) and include paths.
   - Log injection: raw user input into logs on lines that ops tools render (newline smuggling, ANSI escapes)?

   **A01: Broken access control.** (The highest-impact category; slow down here.)
   - Every endpoint/handler: does it check authentication AND authorization — WHO may act on WHICH specific object?
   - Object-level checks on every ID from the request: fetching order 1042 — is it THIS user's order 1042? (IDOR is the most common serious web vuln.)
   - Admin/internal routes gated by role, not by obscurity (unlisted URL, nonstandard port, "frontend never links to it").
   - Tenant isolation in queries: scoped by tenant in the WHERE clause, not by a post-fetch filter.
   - Mass assignment: request bodies bound wholesale to models that contain privilege fields (`role`, `tenant_id`, `price`).
   - CSRF on state-changing browser-reachable routes; missing `SameSite` considerations for auth cookies.

   **A07: Identification & authentication failures.**
   - Sessions/tokens: generated from a cryptographic RNG, unguessable, expired and rotated properly, invalidated on logout/password change.
   - New auth code paths: timing-safe comparison for secrets, no user-enumeration signals (different errors/timings for "no such user" vs "wrong password").

   **A02: Cryptographic failures.**
   - Plain HTTP for anything crossing a boundary; secrets in URLs (they land in logs, referrers, browser history).
   - Right primitives: bcrypt/argon2 for passwords, AES-GCM for data at rest, no home-rolled crypto, no MD5/SHA1 for security purposes, no ECB.

   **A05: Security misconfiguration.**
   - Debug endpoints, stack traces, `/metrics` or admin surfaces exposed by default? New config defaults safe for production (fail closed: deny when the flag is missing)?
   - Permissive CORS (`*` with credentials), missing security headers on HTML routes.

   **A06: Vulnerable and outdated components.**
   - Diff touches dependency manifests or lockfiles: what changed and why? New dependency — is it maintained, does it have known advisories? Version pinning exact or floating (`^`/`latest` — floating is a finding)?
   - Check advisories for the versions being added (OSV/npm audit/GitHub advisories, or your scanner's output) — as of the sweep, not from memory.

   **A08: Software and data integrity failures.**
   - Unsafe deserialization: native object deserialization (`pickle`, Java native, PHP `unserialize`, Node `node-serialize`) on user-controlled bytes is an automatic P0 unless provably confined.
   - `yaml.load` without safe-loader, `eval`-family on external input, template engines compiling strings.
   - Install/build scripts fetching code over HTTP or from unverified sources; lockfile integrity hashes present and enforced.

   **A04: Insecure design & A10: logging failures** (cross-cutting).
   - Security events (auth failures, authz denials, validation rejections) logged with enough context to investigate, WITHOUT logging credentials, tokens, card data, or full PII.
   - Rate limiting / abuse controls considered on new public endpoints (design-level, note as finding if absent).

   **A09: SSRF (server-side request forgery).**
   - Server fetches a URL derived from user input (webhooks, "import from URL", avatar-by-URL, PDF generation)? Validate scheme+host against an allowlist, block link-local/metadata IPs (169.254.169.254 — cloud metadata), resolve-then-check (DNS rebinding), follow no redirects to unvalidated hosts.

4. **Hunt secrets.** Grep the diff and the repo for credential shapes: `password=`, `api_key`, `secret`, `token`, `AKIA`, `-----BEGIN`, high-entropy strings in config. Check test fixtures (real creds in tests are real creds) and `.env` files are gitignored — AND check git history if this is the repo's first sweep: a secret in history is a live secret regardless of HEAD. Found one? It is rotated, not merely deleted (deletion leaves it in history forever).

5. **Check validation — at the right boundary, once.**
   - Every external input validated at the trust boundary: type, length, range, format, charset — with allowlists.
   - Validation happens where input ENTERS (and output encoding happens where data LEAVES — encoding for the destination context: HTML, attribute, JS, URL).
   - Watch for validation drift: checked in the controller, then re-read from the raw request later; or validated client-side only.

6. **Severity-tag findings** using the same scale as `pr-reviewer`:
   - **P0**: exploitable now by an ordinary user — injection, missing authz on a data path, live secret, unsafe deserialization, SSRF to internal networks. Blocks merge. If already deployed: rotate/patch immediately.
   - **P1**: exploitable with plausible effort or conditions — weak token handling, missing rate limits on credential endpoints, dependency with a known exploited advisory, tenant isolation relying on post-filtering.
   - **P2**: hardening debt — missing headers, floating dependency versions, verbose error responses, incomplete security logging.
   - **P3**: informational — naming, docs of security behavior, minor hygiene.
   Each finding: location, category (OWASP ref), concrete attack sketch (who does what, what breaks), and the fix direction. No theoretical lectures; every finding names its path.

7. **Write the report.** Order by severity. Include the scope from step 1 and explicit "checked, clean" notes for high-risk categories — silence about authz in a security review is indistinguishable from not having checked it. End with the merge recommendation.

8. **After the sweep: fixes, re-sweep the deltas.** Fixes for P0/P1 land before merge, each with a test proving the vulnerability is closed (a request that should be rejected, a payload that must not execute). Re-run the sweep on the fix diffs — security fixes regress too, and their regressions are the most expensive kind.

## Fast greps for the mechanical checks

Secrets and injection sinks have text shapes; grep the diff and its blast
radius first, then verify each hit by reading (greps find candidates, reading
convicts or acquits):

```bash
# Credential-shaped strings in the change
git diff -U0 | grep -Eni '(password|secret|token|api[_-]?key|private[_-]?key)\s*[=:]'
grep -rEn '(AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY)' .

# Common injection sinks (inspect every hit)
grep -rEn '(\.raw\(|exec\(|system\(|Runtime\.getRuntime|os\.system|subprocess\.)' src/
grep -rEn 'SELECT .*" \+|".*SELECT' --include=*.java --include=*.py src/

# Unsafe deserialization
grep -rEn '(pickle\.loads|yaml\.load\(|unserialize|readObject|node-serialize)' src/

# Outbound fetches whose URL may carry user input (SSRF candidates)
grep -rEn '(requests\.get|http\.Get|fetch\(|curl_exec|axios\.get)' src/
```

## Worked finding (the format in action)

```markdown
**[P0] SSRF via webhook URL — WebhooksController.register (A10)**
What: register-webhook stores any user-supplied URL; the dispatcher fetches it
with redirects followed.
Attack: URL `http://169.254.169.254/latest/meta-data/iam/...` (redirect via an
attacker-controlled 302) makes OUR server fetch cloud metadata and, with
response forwarding in the "test webhook" feature, hands the body back.
Fix direction: allowlist scheme (https) + resolve host, reject
private/link-local ranges AFTER DNS resolution, do not follow redirects to
unvalidated hosts, strip response bodies from the test-ping result.
Test: webhookTest_urlPointingAtMetadata_isRejected.
```

## Checklist

- [ ] Scope written: files, callers, consumers, trust boundaries.
- [ ] Every external input traced to every landing site.
- [ ] Injection checked: SQL, OS commands, templates, paths, logs.
- [ ] Authorization checked per endpoint, object-level (IDOR), tenant-scoped, role-gated; mass assignment and CSRF considered.
- [ ] Auth/session/token handling: generation, expiry, rotation, timing-safe compares, no user enumeration.
- [ ] Crypto: right primitives, no secrets in URLs, no home-rolled crypto.
- [ ] Config defaults fail closed; debug/admin surfaces not exposed; CORS sane.
- [ ] Dependency deltas justified, advisories checked, versions pinned.
- [ ] No unsafe deserialization / eval-family on external input.
- [ ] SSRF checks on all user-influenced outbound URLs (metadata IPs blocked).
- [ ] Secrets scan of diff (and history, on first sweep); findings rotated, not just deleted.
- [ ] Severity tags with concrete attack sketches; "checked-clean" noted for high-risk categories.
- [ ] Sweep stayed read-only; fixes came after, each with a regression test.

## Anti-patterns

- **Scan-and-declare.** Running a SAST tool, seeing green, and calling it secure. Scanners catch the mechanical third of these categories; the load-bearing third (authz logic, business rules, design) is human review. Tools are one input, not the verdict.
- **Fix-as-you-find.** Repairing the first injection and ending the sweep. The report exists because the survey must complete before triage; otherwise every sweep finds exactly one bug.
- **Denylist thinking.** "We block quotes and angle brackets." Attack encodings outnumber denylists forever; allowlist structure (parameterized SQL, context-aware encoding, typed fields) or accept the treadmill.
- **Trusting internal callers.** "That endpoint is internal-only" — internal-only is a routing fact, not an access control; routes become external during refactors, incidents, and misconfigurations. Enforce authz anyway.
- **Secrets treated as text.** Deleting the leaked key from the file. The commit history IS the leak; only rotation closes it.
- **Client-side validation as security.** It is UX. Server validates everything, always, as if the client were curl (because it is).
- **Severity inflation/deflation.** Tagging everything P0 (review fatigue sets in, real P0s drown) or talking yourself down from a P0 because "an attacker would have to know the ID format" (IDs leak; assume they know).
- **The theoretical lecture.** Findings that cite OWASP but cannot name the request that exploits them. If you cannot sketch the attack path, it is a P2 hardening note, not a vulnerability — say so honestly.

## Signals you're done

- Every trust boundary in scope was crossed deliberately: you can list them, and what guards each.
- Every finding has a location, category, concrete attack sketch, severity, and fix direction.
- P0/P1 fixes have tests that fail open and pass closed.
- High-risk categories show explicit clean/finding status — no silent gaps.
- The next sweep of this area starts from your scope list, not from zero.
