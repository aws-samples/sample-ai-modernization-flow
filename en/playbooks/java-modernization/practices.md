# Migration Practices Collection — Java Modernization

This file accumulates practices specific to the Java modernization domain, in `DP-N` format.
For domain-agnostic common practices, see `practices-common.md` (Method layer, `CP-N` format).

---

## About This Document

### Purpose
- Accumulate practices specific to this Playbook (Java modernization).

### Numbering Rules
1. Use **`DP-N` format, with sequential numbers managed centrally in this file** (use the next available number).
2. `DP-N` here is unrelated to the `DP-N` in other Playbooks (e.g., clang-solarisx86-to-amznlinux). Duplicate numbers are not a problem.
3. **Only the framework itself may assign an unprefixed `DP-N`.** Additions made in a project's
   copied `docs/knowledge/practices.md` use the `DP-<project>-N` namespace and are fed back into
   the framework on completion (for the details and the incident behind it, see
   "Numbering Authority" in `practices-common.md`).
4. **Gaps are preserved and never reused.**

### How to Read This, and the Quantitative Discipline

**By default an AI agent reads only the "Summary" table.** Open the body only when you hit the
relevant theme. The limits (300 bytes per summary row / 80 body lines / 15 entries) and what to do
when they are exceeded follow "Quantitative Discipline" in `practices-common.md`, and are
mechanically checked by `./verify.sh knowledge`.
Knowledge whose body exceeds the limit is split into `docs/reference/`, leaving the essentials plus
a pointer in the body.

### Rules for Adding Entries
1. Insert new entries **immediately before** the `ENTRIES END` marker (a single HTML comment line at the end of this file; this marker must not be moved).
2. Each entry follows the `## DP-N: <Title>` format, with the following section structure:
   - `### Purpose` / `### Rule` / `### How to Check` / `### Anti-patterns` / optionally `### Real-world Example (project name)`
3. Add a row for the new entry to the "Summary" table.

---

## Summary

| ID | Title | One-liner |
|----|---------|------|
| DP-1 | Verification commands must include test-compile | `mvn clean install -DskipTests`. `compile` cannot detect leftover tests for deleted classes |
| DP-2 | Suspect silent failure whenever security defaults change | Without exception, it "becomes empty / fails to fire." Detect it via diagnostic logging and E2E |
| DP-3 | Enabling CSRF must be paired with a full survey of all forms | Login, anonymous POST, and multipart each require individual handling |
| DP-4 | E2E selectors must not depend on framework-generated IDs | Generation algorithms change across major versions. Prefer CSS class/attribute selectors |
| DP-5 | **A real-browser golden-path E2E MUST be in the integration gate for a UI-rendering app [MANDATORY]** | UI-layer silent failure is caught only by a real browser path. Mechanically enforced with `REQUIRE_GOLDEN_PATH=1` |

---

## DP-1: Verification commands must include test-compile

### Purpose
For transformations that involve class deletion (e.g., legacy feature removal), detect — during the
transformation's verification stage — the failure mode where the corresponding test files under
`src/test/java/` remain and cause compile errors.

### Rule
1. The verification command for the verify build gate uses
   `mvn clean install -DskipTests` (including an explicit `JAVA_HOME` specification).
2. Do not use `mvn clean compile` as the verification command:

   | Command | Main code | Test code | Detects leftover tests |
   |---------|:---:|:---:|:---:|
   | `mvn clean compile` | ✅ | ❌ | ❌ |
   | `mvn clean test-compile` | ✅ | ✅ | ✅ |
   | `mvn clean install -DskipTests` | ✅ | ✅ | ✅ |

3. For transformations that delete classes or interfaces, state it explicitly in the work-plan Step:
   "The corresponding test classes must also be deleted" + verification: `grep -r "<deleted class name>" src/test/`

### How to Check
- verify.sh's BUILD_CMD is `install -DskipTests` (or `test-compile` or stronger)

### Anti-patterns
- ❌ Judging the build "successful" based on `mvn clean compile`
- ❌ Building with the system default (different-version) JDK because JAVA_HOME was left unspecified

### Real-world Example
In all three transformations — removal of OAuth 1.0 / XML-RPC / the CSRF filter — leftover test files
caused compile errors that were only discovered after the transformation. This was resolved by
improving the verification command to `install -DskipTests`.

## DP-2: Suspect silent failure whenever security defaults change

### Purpose
Hardened security defaults introduced by a framework's major upgrade often **disable functionality
without raising any exception or error log**. Rather than "it doesn't work," include the correct
causal category in your hypotheses from the start for symptoms of "becomes empty / fails to fire,
with no exception."

### Rule
1. After a framework upgrade, treat the following symptoms with **a security-default change as the primary hypothesis**:
   - Dynamic content or a title renders as an empty string (e.g., the Struts OGNL allowlist)
   - Form parameters are not bound to the Action / NPE occurs (e.g., `struts.parameters.requireAnnotations`)
   - File upload fails to fire with no exception (e.g., the Struts 7 `UploadedFilesAware` API migration)
2. Enable diagnostic logging to observe (use it as the observation column of the hypothesis log):
   Example: `struts.ognl.logMissingProperties=true`
3. Choose a remediation direction — "disable the new default" (revert to old behavior via configuration)
   or "conform to the new API" (add annotations, set up an allowlist) — and record the rationale in an
   ADR (conforming to the new API is recommended for production).
4. These are documented in the official migration guide (this is preventable if CP-9 was performed beforehand).

### How to Check
- The E2E tests include **non-empty assertions** on the page title and dynamic content
- Side-effecting features such as file upload have a "verify the result exists" test (to detect silent failure)

### Anti-patterns
- ❌ Concluding "no problem" based on the absence of errors in the logs
- ❌ Declaring the upgrade complete based on successful compilation and passing unit tests (CP-4)

### Real-world Example
During a major web framework upgrade, three kinds of silent failure occurred: (1) a page title was
empty due to the server-side expression language allowlist, (2) user registration threw an NPE due to
the introduction of a required parameter-binding annotation, and (3) media file storage failed to fire
with no exception due to a change in the upload API. All three were documented in the official guide.

## DP-3: Enabling CSRF must be paired with a full survey of all forms

### Purpose
Enabling something like Spring Security CSRF looks like "one line of configuration," but it actually
requires handling **every POST path** in the application. Any path that is missed only manifests at
runtime, as a 403 Access Denied.

### Rule
1. Before enabling, enumerate all POST forms exhaustively: `grep -rn '<form.*method="post"' --include='*.jsp' -i`
   (target every template engine, not just JSP — Velocity, Thymeleaf, etc.)
2. Individually verify the paths that are especially easy to miss:
   - **Login forms** (often located in a JSP separate from the main application)
   - **POST requests from anonymous users** (e.g., comment submission; these must be excluded since they cannot hold a token)
   - **multipart/form-data** (CsrfFilter cannot read the token from the body → use the URL query parameter approach)
3. Do not rely on `security="none"` for path exclusion (it disables the entire filter chain, including
   authentication information; matching is also unreliable under FORWARD dispatch). Instead, combine
   `<csrf request-matcher-ref>` with `AndRequestMatcher` to "reproduce the default HTTP-method filter
   while adding path exclusion."
4. Note that `request-matcher-ref` **completely overrides the default GET/HEAD/TRACE/OPTIONS exclusion**.

### How to Check
- E2E tests pass through the full path: "login → page requiring authentication → form submission →
  anonymous POST (if applicable) → file upload"

### Anti-patterns
- ❌ Enabling CSRF configuration and calling it done after only confirming GET screen display
- ❌ Applying the hidden-field approach to multipart forms as well (it will not be read)

### Real-world Example
CSRF handling gaps surfaced at runtime across three areas: the login form (403), anonymous comment
submission (resolved after four rounds of trial and error, using `AndRequestMatcher`), and media upload
(resolved with the query-parameter approach).

## DP-4: E2E selectors must not depend on framework-generated IDs

### Purpose
The algorithm a UI framework (e.g., Struts tags) uses to generate HTML element IDs changes across major
versions. E2E selectors that hardcode generated IDs break with every upgrade.

### Rule
1. Selector priority order: `data-*` attributes > stable CSS class + attribute > hand-written ID > generated ID (last resort)
2. After a framework's major upgrade, audit ID changes on tag-generated elements (submit/link/input, etc.)
3. During a CSS framework migration (e.g., Bootstrap), a layout change can push buttons outside the
   viewport. Make `scrollIntoView` before clicking a common routine of the Page Object.
4. For JS-integrated UI such as modals, check both framework API changes (e.g., jQuery → native API)
   and DOM placement constraints (stacking context).

### How to Check
- No selectors using a generated-ID pattern (e.g., a templated ID like `entry_%{...}`) remain in the E2E code

### Anti-patterns
- ❌ Copying the current version's generated ID directly into a selector
- ❌ Running headless tests without fixing the resolution and locale
  (the locale defaults to the JVM default: `MAVEN_OPTS="-Duser.language=en -Duser.country=US"`)

### Real-world Example
During a major web framework upgrade, the submit button's generated ID changed and the target button
could no longer be found by its selector. This was resolved by switching to a stable CSS class +
attribute selector. A click being blocked by a layout change from a major CSS framework upgrade was
resolved with `scrollIntoView`.

## DP-5: A real-browser golden-path E2E must be in the integration gate for a UI-rendering app [MANDATORY]

**This is mandatory, not a recommendation.** It is enforced mechanically by `verify.sh`'s
`REQUIRE_GOLDEN_PATH=1` plus registration in `GOLDEN_PATH_TESTS` (the integration gate FAILs if none is registered).

For a migration with a web UI, build/unit/smoke alone cannot catch UI-layer silent failures (no
exception, HTTP 200, rendering is empty/invisible). Wire a **real-browser (Selenium, etc.) E2E of the
path a real user always takes** (register → login → core CRUD; ideally image upload → insert → view →
comment, etc.) into the integration gate early. Do not call build/unit/smoke alone "verification."
(For the diagnostic heuristic and observation validity, see CP-8 in practices-common.md. Measure UI
defects with the equivalent of browser DevTools.)

<!-- ENTRIES END -->
