# Migration Practices Collection — Common (Common Practices)

Common practices that apply to migration/modernization projects in general, regardless
of domain or language, are accumulated here in `CP-N` form. Domain-specific practices
are recorded in each Playbook's own `practices.md`, in `DP-N` form.

---

## About This Document

### Purpose
- Accumulate migration practices common to all domains, in `CP-N` form (this file
  belongs to the method layer).

### How to Read This (for AI agents — important)

**By default an agent reads only the "Summary" table.** Open the body only when you hit the
relevant theme. The body may go into detail with real-world examples, anti-patterns and code
(**the body is the layer humans read to understand**; making it short is not the goal). This
two-layer structure is the mechanism that reconciles context load with explanatory power.

Likewise, **do not read `worklog.md` chronologically.** Recover the previous state from
`session-context.md` (worklog is append-only and grows without bound).

### Numbering Rules

1. **Common practices use the `CP-N` form, with a single sequence managed centrally in
   this file** (use the next available number).
2. **Domain-specific practices use the `DP-N` form in each Playbook's practices.md,
   with a sequence managed centrally within that Playbook.**
   Because `CP-N` and `DP-N` use different prefixes, their number spaces are
   independent (no need to worry about collisions).
3. **`DP-N` numbers MAY repeat across different Playbooks** (e.g., DP-3 in the clang
   Playbook and DP-3 in the java Playbook are unrelated).
   Since a single project only pulls in the common practices plus one Playbook, this
   never causes a collision at runtime.
   When referring across Playbooks, state the origin explicitly, e.g.
   "DP-N of the 〈domain name〉 Playbook."

#### Numbering Authority (separating the framework from projects)

**Only the framework itself may assign an unprefixed `CP-N` / `DP-N`.**
The knowledge files copied under a project's `docs/knowledge/` are for reference plus
**appending in the project's namespace**; they must not take the next unprefixed number.

| Who assigns | Form used | Example |
|-------------|-----------|---------|
| The framework itself | `CP-N` / `DP-N` (unprefixed) | `CP-13`, `DP-10` |
| An individual project | `CP-<project>-N` / `DP-<project>-N` | `DP-myapp-1` |

Project knowledge is fed back into the framework on completion, and receives an unprefixed
number there. **Gaps are preserved and never reused.**

> This is a countermeasure against a real incident. A running project assigned its own `DP-5`,
> which **collided with a different `DP-5`** in the Playbook itself.
> A "measure, then take a number" approach breaks as long as there is a gap between measuring
> and taking, so the namespaces are separated structurally.

### Rules for Adding Entries

1. Insert new entries **immediately before** the `ENTRIES END` marker (a single HTML comment line at the end of this file) at the
   end of this file (this marker itself must not be moved).
2. Each entry follows the `## CP-N: <Title>` format, with the following consistent
   section structure:
   `### Purpose` / `### Rule` / `### How to Check` / `### Anti-patterns` / optionally
   `### Real-world Example (project name)`
3. Add a row for the new entry to the "Summary" table.
4. General knowledge gained within a project is appended to that project's
   `docs/knowledge/practices-common.md` **in the project namespace**, and fed back into
   this file once the project is complete.

### Quantitative Discipline (mechanically checked by `./verify.sh knowledge`)

Prose rules slip through on self-report, so quantities are bounded by numbers and checked by a
gate. The defaults are based on measurement (the observed distribution across this file and the
two Playbooks is 29-72 body lines and 175-215 bytes per summary row).

| Target | Default limit | What to do when exceeded |
|--------|---------------|--------------------------|
| One summary row | 300 bytes | If it does not fit in one line, it belongs in the body |
| One entry's body | 80 lines | Split the detail into `docs/reference/` and leave the essentials plus a pointer |
| Entries per file | 15 | Consider consolidating or deleting (see below) |

- The limits are adjustable in the project's `verify.sh` (`KNOWLEDGE_MAX_*`)
- **A line-count limit is not language-neutral** (for the same content, English runs about
  1.4x the lines of Japanese). The defaults leave headroom for the English side
- **Exceeding the entry count is the trigger that forces consolidation.** If you decide not to
  consolidate, record the reason at the top of the file:
  `<!-- KNOWLEDGE-REVIEWED: YYYY-MM-DD (N entries, consolidation deferred: <reason>) -->`
  With that record the gate passes (**only an unrecorded excess is rejected**).
  This is designed to prevent the state where stock-taking at phase gates and retrospectives
  is only ever proposed and never carried out

### Vocabulary for the Coverage Baseline (do not call it a "denominator")

When referring to the mechanism that guarantees coverage numerically, use these terms. To avoid
forcing readers to learn new jargon, prefer the existing vocabulary and **do not use the word
"denominator"**.

| Target | Term | What it is |
|--------|------|------------|
| Artifacts (executables, libraries, war/jar, etc.) | **expected list** | `EXPECTED_ARTIFACTS` in `verify.sh` (CP-7) |
| Sites that must be touched by the migration | **adaptation ledger** | `01-plan/adaptation-ledger.md` (with dispositions; what is counted is the applicable perspectives = CP-11) |
| When speaking conceptually | **coverage baseline** | "an independently countable list of what must be accounted for" |
| When actually doing statistical sampling | **population** | A statistics term. This flow does no random sampling, so it should not appear |

The count of ledger rows left untouched is called the **unaddressed count**,
and driving it to zero is the metric.

---

## Summary

| ID | Title | One-liner |
|----|---------|------|
| CP-1 | Investigating behavioral changes in dependent libraries | API compatibility ≠ behavioral compatibility. Detect changes upfront via CHANGES/NEWS |
| CP-2 | Rules for the investigation process | Re-verify until final success. Don't prematurely commit to a single root cause |
| CP-3 | Handling AI analysis results | AI output is a hypothesis. Verify against the real code before including it in the plan |
| CP-4 | Completion criteria for code fixes | Build success ≠ complete. Not complete until confirmed by an observation test |
| CP-5 | Baseline Behavior Tests | Record the old behavior before migration, and detect diffs after migration |
| CP-6 | Exact match between the verification gate and the success-criteria table | Include all criteria in the automated tests. Don't rely on manual checks |
| CP-7 | Register every in-scope binary into the verification gate on day one | Anything unregistered is treated as "not existing." Make failures visible even as FAIL |
| CP-8 | Confirm the root cause only through demonstrated causality (hypothesis log) | Stays a "hypothesis" until the symptom reproduces/disappears when toggled ON/OFF. One hypothesis-log line per attempt |
| CP-9 | Review official migration guides exhaustively before planning the conversion | A multi-step major-version jump has multiple guides too. Transcribe breaking changes into the plan and record the source URLs |
| CP-10 | Pre-validate the target stack (EOL / compatibility matrix / PoC) | Validate the target combination before starting the conversion. Compatibility contradictions cause large rework later |
| CP-11 | Make "perspectives" the adaptation ledger's coverage baseline; get counts during the work with detectors | Never count in advance what the toolchain enumerates. Every perspective carries a detection command. The coverage baseline is a per-migration-route asset |
| CP-12 | Write verification tools so they never ask the host environment | Do not delegate existence checks to the filesystem; compare strictly against a primary source. No GNU-only options. A count being produced is not evidence of correctness |
| CP-13 | Give every detector a negative test | "Zero findings" reads as "none exist" AND as "cannot detect". Detection power is unproven until you break it and confirm EXIT != 0 |

---

## CP-1: Prior Investigation When Dependent Libraries Have a Major Version Difference

### Purpose
Catch cases where the API still exists but its behavior (semantics) has changed,
before getting stuck during behavior verification.

### Rule
1. Identify libraries whose major version changes from the migration source to the
   migration target.
2. Read each library's CHANGES/NEWS (covering every major-version boundary crossed)
   as a primary source:
   - **Enumerate newly introduced compatibility options/flags, and check why each was
     added** → a newly introduced option = "a switch to restore the old behavior" =
     a signal that "some behavior is broken"
   - **Prioritize identifying items whose default value changed**
3. For each item above, identify which parts of this codebase are affected.
4. If possible, create a "diff test between both versions" while the old environment
   is still alive.

### How to Check
```bash
# Phrase the search query around the "symptom":
# ✅ "OpenSSL 3.0 SSL_read returns 0 behavior change"
# ❌ "OpenSSL 3.0 migration guide" (thin on behavioral changes)
```

### Reporting Format
| Library | Change | Old behavior | New behavior | Compatibility option | Affected location |
|-----------|---------|--------|--------|--------------|---------|
| (example) OpenSSL 3.x | unexpected EOF handling | SSL_ERROR_WANT_READ | SSL_ERROR_SSL | SSL_OP_IGNORE_UNEXPECTED_EOF | ssl_recv() |

### Difficulty of Detecting Behavioral Changes

| Type | Ease of detection |
|------|--------------|
| API removal/signature change | Detected automatically at compile/link time |
| **Behavioral change** | Compiles fine, partially works. Only surfaces in specific states |

### Anti-patterns
- ❌ Judging a dependent library "compatible" simply because the build passes
- ❌ Reading only the migration guide and concluding "no behavioral changes"
- ❌ Waiting to write tests until after the old environment has been decommissioned

---

## CP-2: Rules for the Investigation Process

### Purpose
Reach the root cause efficiently when a problem occurs.

### Rule
1. **Start from the premise that "code you didn't change is correct."** Split files
   touched vs. untouched via the git diff; if a problem appears in an untouched file,
   treat an environmental behavioral difference as the primary suspect.
2. **After making one fix, re-verify all the way to final success.** Do not declare
   "resolved" based on an intermediate signal (e.g., a change in error code).
3. **Change the observation method when the nature of the symptom changes:**
   - Error → debug log + library error queue
   - Delay/hang → `strace -T` (syscall duration)
   - Event problem → event registration/deregistration in the debug log
4. **Look at the syscall layer, the library layer, and the application layer
   simultaneously.**
5. **The more plausible a hypothesis looks, the earlier it should be killed with
   primary evidence.**
6. **Do not prematurely commit to "there is exactly one true cause."** If the symptom
   remains after a fix, another bug lies deeper.

### How to Check
```bash
# List of changed files
git diff --name-only HEAD~N
# Observing the syscall layer
strace -T -e trace=network -p <pid>
# Library error queue
openssl errstr <error_code>
```

### Anti-patterns
- ❌ Judging "the symptom changed after the fix" as equivalent to "resolved"
- ❌ Pursuing the single most plausible hypothesis as the sole cause, ruling out other
  possibilities
- ❌ Looking only at error logs without checking the syscall layer

---

## CP-3: Handling AI Analysis Results

### Purpose
Avoid taking the analysis results of AI tools (Amazon Q Transform / Kiro / Claude Code
/ Cursor / GitHub Copilot, etc.) at face value, and ensure they are cross-checked
against the real code.

### Rule
1. **An AI analysis result is a "generic finding" and does not guarantee the actual
   state of the code.** It may not reflect the codebase's history or customizations.
2. Before an item from the AI analysis results is included in the work-plan, it
   **MUST first be confirmed by grepping/reading the actual source code**, before it
   is reflected in effort estimates.
3. Output the confirmation results as an "AI finding vs. actual code state" comparison
   table.
4. Include only items where the issue was actually confirmed in the work-plan.

### Instruction Template (common across AI tools)
```
Using the AI analysis results as a starting point, create the work plan following
these steps:
1. Extract the "list of items likely needing fixes" from the analysis results
2. For each item, confirm it against the actual source code via grep/reading
3. Output the confirmation results as an "AI finding vs. actual code state"
   comparison table
4. Include only items where the issue was actually confirmed in the work plan
5. Follow the other PB rules
```

### Anti-patterns
- ❌ "Create the work plan based on the AI analysis results" (skips the
  verification step)
- ❌ Using the source OS's config.h as-is and only adding headers
- ❌ Judging a dependent library "compatible" simply because the build passes
- ❌ Reflecting "7-8 fixes are needed" straight into the effort estimate just because
  the AI analysis said so

---

## CP-4: Completion Criteria for Code Fixes

### Purpose
Prevent the gap between "fixed it" and "it actually works correctly."

### Rule
1. A code fix is complete only when "the expected output has been confirmed by a
   test." A successful build is not a completion criterion.
2. For each fix, define "what must be observed to confirm correctness" **before making
   the fix**:

   | Type of fix | How to observe |
   |-----------|---------|
   | HTTP header value change | Check the header with `curl -I` |
   | Cookie value change | Check Set-Cookie with `curl -I` |
   | Error message change | Trigger the error condition and check the log |
   | Configuration default change | Check behavior with the setting omitted |
   | Numeric constant change | Exercise the path that uses the constant and check the output |
   | SSL/TLS-related change | Check with `curl -v https://...`, including the handshake |

3. Items marked "completed in a previous session" are also treated as unverified
   unless a record of the test result exists.
4. Be especially careful with fixed-string fixes: confirming via grep alone is not
   sufficient. A test that actually exercises the path where the string appears in the
   response is required.

### How to Check
```bash
# Run the observation command defined before the fix
# Example: curl -I https://localhost/ | grep "Set-Cookie"
# Save the result to 02-test/test-results/
```

### Anti-patterns
- ❌ Recording "fix complete" based on a successful build
- ❌ Deferring verification to a later session instead of doing it within the same
  session as the fix
- ❌ Verifying code with only one branch of a conditional using only the normal-path
  test

---

## CP-5: Baseline Behavior Tests (Recording Pre-Migration Behavior)

### Purpose
Record "correct behavior" on the old environment before migration, to guarantee the
same output is obtained after migration. Build a mechanism to detect regressions as
"diffs."

### Rule
1. Record correct behavior on the old environment **after Phase 2 (analysis) completes,
   before Phase 3 (implementation) begins**.
2. Some data can only be captured while the old environment is still alive. Treat this
   as top priority.
3. Save the recordings under `02-test/test-results/baseline/`.
4. After migration, run the same commands and compare the diff against the baseline.

### Items to Capture (select based on the type of application)

| Category | Example capture command | Purpose |
|---------|--------------|------|
| HTTP response | Full output of `curl -v http://host/` | Confirm response format/header consistency |
| HTTPS response | Full output of `curl -v https://host/` | Confirm correctness including the TLS handshake |
| Cookie/session | `curl -I http://host/path` | Confirm the format of values like expires |
| Error log (normal operation) | Copy of error.log | Understand the normal debug-log pattern |
| syscall trace | `strace -e trace=network -p <pid>` for one request | Normal syscall sequence pattern |
| Configuration default | Startup output with no configuration file | Understand default-value behavior |
| Performance | `time curl ...` / `ab`, etc. | Baseline for detecting performance degradation |

### How to Check
```bash
# Post-migration comparison
diff 02-test/test-results/baseline/http-response.txt \
     02-test/test-results/phase3/http-response.txt
```

### Anti-patterns
- ❌ Starting to think about test cases only after the old environment has been
  decommissioned
- ❌ Skipping this with "I already know the normal behavior, no need to record it"
- ❌ Declaring "behavior should be the same as before migration" without a baseline
  recording

---

## CP-6: Exact Match Between the Verification Gate and the Success-Criteria Table

### Purpose
Prevent verification gaps caused by items defined in the success-criteria table not
being included in the verification gate (automated tests).

### Rule
1. Include **every item** of the success-criteria table (required and recommended) as
   an executable automated test in the verification gate. Do not leave them as a
   manual checklist only.
2. When implementing the verification gate, perform a **bidirectional reconciliation**
   against the success-criteria table:
   - For each table item → does a corresponding test exist?
   - For each test → is there a corresponding entry in the table?
3. Place the verification-gate files somewhere the build system will not overwrite,
   under a distinct name (e.g., `verify.mk`, `scripts/verify.sh`, `ci/gate.mk`).
4. Before declaring a Step complete, include in the record that "the verification
   gate was run and all items were observed to PASS."

### How to Check
```bash
# Number of items in the success-criteria table
grep -c "^| M\|^| R" 01-plan/work-plan.md

# Number of test targets in the verification gate
ls 02-test/integration/*.sh | wc -l   # example: count of registered integration tests

# Confirm the two counts match
```

### Anti-patterns
- ❌ Defining the success-criteria table but implementing only part of it in the
  verification gate
- ❌ Short-circuiting with "make verify PASS = all criteria cleared" and skipping the
  reconciliation against the table
- ❌ Writing verification logic into a file the build system overwrites (e.g.,
  Makefile)
- ❌ Excluding recommended criteria from testing on the grounds that "recommended means
  optional"

---

## CP-7: Register All In-Scope Binaries into the Verification Gate on Day One

### Rule

- Every build target defined as in-scope in the work plan MUST be registered in
  full into the verification gate (verify.sh, etc.), **regardless of whether it
  currently builds**
- Anything that doesn't build yet is made visible as a FAIL; if it is to be skipped,
  state the reason explicitly as a comment
- Implicit "deal with it later" skipping is not allowed — a skip MUST be recorded as
  an explicit decision
- Periodically reconcile the number of items in the verification gate against the
  scope definition in the work-plan (a concrete application of CP-6)

### Why This Is Needed

Migration work tends to run long, and focus shifts over time. Anything not registered in
the verification gate is equivalent to "not existing" — the gap goes undetected until
the completion check. This applies equally to build targets, test targets, and
configuration files.

### When to Apply

- Immediately after creating the work-plan (at Phase 1 completion)
- Whenever the scope changes, reconcile against the verification gate's expectation
  list

### Anti-patterns
- Deciding verbally, "the build stalled from a missing header → deal with it later,"
  without registering it in the verification gate
- Declaring completion with all items PASSing, when in fact part of the scope was
  never in the verification target to begin with

---

## CP-8: Confirm the Root Cause Only Through Demonstrated Causality (Hypothesis Log)

### Purpose
Prevent the misdiagnosis, in troubleshooting, of mistaking a plausible-sounding
explanation for the confirmed root cause.
A misdiagnosis does not manifest as "repeated failure," so counting attempts alone
cannot detect it. By placing the bar for confirmation at "demonstrated causality," the
judgment is based on observed fact rather than the persuasiveness of an explanation.

### Rule
1. **"Root cause identified" may only be recorded once causality has been
   demonstrated** — that is, only once it has been observed that "toggling the cause
   ON/OFF reproduces/removes the symptom." Until then, it MUST always be labeled a
   "hypothesis."
2. For each fix attempt addressing unexpected behavior, **record one hypothesis-log
   line per attempt**:

   | # | Hypothesis | Prediction (what this fix should change) | Observed result | Verdict |
   |---|------|--------------------------------|---------|------|

   The verdict is one of "Resolved (causality demonstrated) / Hypothesis rejected /
   Continuing."
3. Attempting a fix without recording it is a violation of the recording obligation.
   Using the hypothesis-log line count as the denominator for escalation (stopping at a
   defined line count to report to a human and propose splitting into a subtask)
   structurally solves the problem of self-reported attempt counts.
4. Also keep rejected hypotheses and their reasons (to prevent re-running the same
   failed route).
5. When observing a crash or failure, always confirm the executed command,
   environment, and exit code (e.g., 124 = timeout survival, 139 = a true SIGSEGV,
   127 = missing library).
6. **An observation is evidence only if it actually exercised the claim.** Before relying on a
   pass/fail or ON/OFF result, confirm:
   - **Deployment check**: the change was really rebuilt/redeployed (an overlay, cache, prebuilt
     artifact, or dependency resolution is not serving a stale copy). You are not measuring an old
     artifact while believing you changed the source.
   - **Precondition and ordering**: the scenario reproduces the bug's precondition and the real
     user-flow ordering. A "green" that skips the precondition is not evidence of "no bug."
   - **Validity of the instrument**: the grep pattern, selector, etc. are not hiding the result.
7. **Measure UI/rendering defects in the browser** (DevTools / JS-exec for computed style, DOM,
   console). Treat "HTTP 200, no exception, empty/invisible output" as a silently-blocked hardened
   security default until proven otherwise.
8. Keep the hypothesis log's verdicts updated for **rejected** rows too (do not leave a rejected one
   as "Resolved"). A fix is accepted not merely when "the cause OFF removes the symptom," but only
   when "it is fixed with the protection kept ON, using a minimal setting."
9. For behavior that cannot be reliably reproduced in-harness, take the **user's manual reproduction
   plus code inspection as ground truth**, and push the permanent guard to a feasible separate layer.
   **Do not add a non-discriminating test (one that stays green even when the bug is present).**

### How to Check
- Confirm that a hypothesis-log table exists in worklog / investigation.md, and that
  the row with a "Resolved" verdict is tied to observed facts (command, output, exit
  code).
- Grep for the term "root cause" appearing in an entry before a "Resolved" verdict.

### Anti-patterns
- ❌ Declaring "the root cause has been identified" from code-structure analysis
  alone (no reproduction test)
- ❌ Confirming causality solely because the symptom disappeared after a fix (without
  ruling out a change in environmental factors)
- ❌ Recording trial-and-error sporadically in free-form notes, making it impossible
  to reconstruct the sequence of attempts afterward

### Real-world Example
For a "SEGFAULT" in a certain daemon process, a plausible-sounding root cause —
"a collision between ELF copy relocation and a C++ static constructor" — was once
recorded as confirmed. On re-investigation, the SEGFAULT itself turned out not to
reproduce at all; the true cause was (1) an unset shared-library search path
(rc=127), and (2) malfunction caused by a prerequisite daemon not having started.
Had demonstrated causality (a reproduction test) been the bar for confirmation, the
initial misdiagnosis would have been caught immediately.

## CP-9: Review Official Migration Guides Exhaustively Before Planning the Conversion

### Purpose
Most runtime failures that occur from a major-version upgrade of a framework/library
are already documented in the official migration guide. Reviewing the guide
exhaustively **before** writing the conversion plan (work-plan / Transformation
Definition) prevents failures proactively.
This is the framework/library-oriented, strengthened form of CP-1 (changelog
investigation).

### Rule
1. Identify the current version and the target version
2. Collect **all** official migration guides spanning that range
   (**for a multi-step major-version jump, there is a separate guide per version
   boundary**. Example: Struts 2.5→7.1 has two guides, "2.5→6.0" and "6.x→7.x")
3. Extract every breaking change from each guide, and count how many places in the
   existing code are affected
4. Incorporate the necessary configuration changes/code fixes into the work-plan / TD
5. Record the guide URLs in the plan as references
6. **Pay particular attention to default-value changes tied to security hardening.**
   These often become **silent failures** — the feature stops working without a compile
   error and without a runtime exception (e.g., an OGNL allowlist returning an empty
   string, or parameter binding failing to fire with no exception)

### How to Check
- The work-plan / TD has a "Reference Guides" section listing a URL per version
  boundary
- Every breaking change listed in a guide is tied to either "how it was addressed" or
  "not applicable (reason)"

### Anti-patterns
- ❌ Running the conversion first, and only discovering the guide while investigating
  a runtime failure afterward
- ❌ Reading only the guide for the latest version, skipping the guides for
  intermediate versions
- ❌ Treating a successful compile as proof the upgrade is complete (missing a silent
  failure)

### Real-world Example
For an upgrade spanning two major versions of a certain web application framework, the
runtime failures encountered (an NPE from parameter binding not firing, a blank page
title from a silent failure of the server-side expression language, changes to
generated HTML element IDs, and a silent failure of file upload) were **almost all
already documented across the two official guides**. Reviewing them beforehand would
have prevented these.

## CP-10: Pre-validate the Migration Target Stack (EOL / Compatibility Matrix / PoC)

### Purpose
Starting the conversion after choosing an incompatible combination of
libraries/frameworks causes large rework later. Establish a phase to validate the
soundness of the target stack **before** beginning conversion work.

### Rule
1. **Check EOL / LTS status:** Tabulate whether each candidate component of the
   migration target is within its support window, and when its next EOL falls
2. **Build a compatibility matrix:** Enumerate the mandatory dependencies between
   frameworks and confirm there is no contradiction
   (e.g., check for gaps in a chain such as "Framework A vX requires runtime
   foundation B vY or later")
3. **Analyze dependency depth in the existing code:** Quantify the blast radius of
   changing the migration target (e.g., count affected files via grep, etc.)
4. **Minimal-configuration PoC:** Confirm that basic flows — build, a minimal
   page/feature, authentication, etc. — work with the selected combination
5. **Estimate migration cost from the number of breaking changes:** Estimate effort
   from the breaking-change list in the official guide (CP-9) × the number of
   affected files, and decide whether to proceed in stages or all at once

### How to Check
- The work-plan includes the EOL table, compatibility matrix, and dependency-depth
  analysis results
- The PoC outcomes (build log, startup confirmation) are recorded in 00-analysis or
  the worklog

### Anti-patterns
- ❌ Starting the conversion without validation, assuming "the latest combination
  should work"
- ❌ Jumping into a multi-step major-version leap without quantifying its impact via
  the count of breaking changes

### Real-world Example
An all-at-once migration that modernized the language runtime, web framework, DI
container, and namespace convention simultaneously. Because the compatibility chain
(e.g., "new version of Framework A → requires namespace convention B," "new version of
the security module → requires the new version of the DI container") was never checked,
and breaking changes were never extracted upfront (CP-9), numerous runtime failures
occurred after conversion.
The lessons-learned entry placed this pre-validation phase at the very top (Step 0) of
the recommended workflow.

## CP-11: Make "perspectives" the adaptation ledger's coverage baseline, and obtain the counts during the migration work with detectors

### Purpose

Mechanically enumerate "the places the platform change required you to fix and you forgot", and drive
the unaddressed count to zero. The expected list (CP-7) counts **whether artifacts exist**; it cannot
detect a site **inside** an artifact that already exists but was never fixed.

### Rules

1. **Make the coverage baseline "the perspectives in the Playbook's perspective table
   (`analysis-appendix.md`) that apply to this target".** Never use a code scan's hit count.
   **One ledger row = one perspective**
2. **Do not count in advance the perspectives the toolchain enumerates (① it enforces)** — namespace
   replacements, project file formats, API renames. **A static scan pre-empting the build adds nothing**
3. **What you hold in advance is only the "② silent" and "③ misleading" perspectives**
   (② silent: the build succeeds and it breaks only at runtime or in production. ③ misleading: the build fails, but the straightforward fix breaks something else)
4. **Every perspective carries its own detection command.** Prose alone never yields the full count:
   unless you know "the target is case-sensitive", path mismatches stay at **zero forever** — **the work never surfaces them**
5. **Every perspective's detector carries a negative test** (CP-13)
6. **Obtain the counts during the work by running the detectors** (run → N hits → fix → re-run to zero →
   freeze in verify). **Do not quantify everything at planning time as the denominator of completion**
7. **Record the detection methods re-runnably** (for example `00-analysis/detection/`). Phase 4 re-scans, so losing them makes the verification impossible to reproduce
8. **Give every row a perspective ID (`MP-N`) and `path:line` evidence** (CP-3: never rely on an AI
   summary alone). A perspective absent from the table may be opened with no `MP-`, but return it in Phase 4
9. **`not_required` and `replaced` require a reason.** If functionality is lost, HOLD-1 + an ADR
10. **Make zero `unaddressed` a completion condition of Phase 4** (what you count is **perspectives**)
11. **Assume the perspective table misses things.** Never write "we covered everything". A newly
    encountered perspective **must not end with this project — return it to the Playbook's table**

### Why a scan hit count is not the coverage baseline (measured)

On one project the count was corrected **three times** (**412 → 418 → 428 → 464**) — always by external
refutation; the producer never noticed on its own. **The counting unit differed per perspective**
(lines / unique paths / files), so **increases and decreases could not be compared**. Of the 41 rows
opened, **about 24 were enumerated by the build in seconds**, and once the build passed the unaddressed
count fell 41 → 9, where **all 9 remaining rows were items the build stays silent about**.
A scan hit count is unstable, incomparable, project-specific and disposable.
**Making one ledger row one perspective removes the mixed-unit problem entirely** (the code hit count
becomes a field inside the row).

### The format of a perspective, and how the coverage baseline is chosen

Every perspective carries an **ID (`MP-N`) / risk / kind (②③) / why it is not detected / detection
command / the observation that lets you call it correct (CP-4) / a negative test (CP-13)**. See
[docs/authoring-playbook.md](../docs/authoring-playbook.md), "How to write the perspective table".

**Which** perspectives apply varies with the migration, so that choice is not fixed. Instead the
framework **requires you to state which perspectives you chose** (`./verify.sh adaptation` checks it exists).
**Never use a list of specs or rules extracted by an AI as the coverage baseline** — an extract's errors are
caught by corroborating against real code (CP-3), but what it **never wrote** stays missing and nobody
notices, and recall cannot be rescued by corroboration.

### When it applies

| Phase | What to do |
|-------|-----------|
| 0b | **Pick the applicable perspectives from the table** (to show scale and risk). Do not count code |
| 2 | Prepare a **detection command and a negative test** per perspective. Open the ledger together with the work-plan |
| 3 | **Run the detector to obtain that perspective's full count**, fix, and move rows to `addressed` at each Step |
| 4 | Re-run every detector and confirm `unaddressed` is zero. **Return newly encountered perspectives to the Playbook's table** |

### How to check

```bash
./verify.sh adaptation
```

### Anti-patterns

- **Counting the perspectives the build enumerates (①) in advance with a static scan** — less precise, and the build produces the same information in seconds
- **Quantifying everything at planning time and using it as the denominator of completion** — mixed units make the arithmetic meaningless
- **Leaving a perspective without a detection command** — the full count never surfaces even while you work, and the count stays at zero forever
- **Pulling in every item from the perspective table** — rows that match nothing dilute the ledger and create a false sense of coverage
- **Treating the detection methods as disposable** — the Phase 4 re-verification cannot be reproduced
- **Letting a newly encountered perspective end inside the project** — the next project repeats the same discovery from scratch
- Opening ledger rows while the coverage baseline definition is still blank — later nobody can tell what was counted

---

## CP-12: Write verification tools so that they never ask the host environment

### Purpose

The central task of a migration is **detecting the differences** between source and target. If the
detection tool is **affected by which environment it happens to run on**, its results cannot be
trusted. This prevents the failure where "the tool that detects a difference is itself disabled by
that very difference".

### Rules

1. **Never delegate existence or identity judgments to the host filesystem.** Judge by a **strict
   string comparison** against a **primary source** instead (the `git ls-files` listing, a config
   file, a manifest)
2. Typical ways host dependence creeps in: `test -e` / `test -d` / path resolution / letter case /
   line endings / locale-dependent sorting / `realpath`. **Every one of them asks the host**
3. **Do not use GNU-only options** (the working host may be macOS, where BSD behavior differs):

   | Forbidden | Portable alternative |
   |-----------|----------------------|
   | `sed -i` (without a suffix) | Go through a temp file (`sed ... > tmp && mv tmp f`) or `perl -pi -e` |
   | `grep -P` | `grep -E` (POSIX ERE) or `perl -ne` |
   | `readlink -f` | Treat the path as a string (do not normalize) or use `python3 -c` |
   | `date -d` | Compute it with `python3 -c` |
   | `stat -c` | Substitute `wc -c`, `git ls-files -s`, etc. |
   | `sort -V` | Expand into `sort -t. -k1,1n -k2,2n ...` |

4. **Never take "a count came out" as evidence of correctness.** A count can be wrong in both
   directions — inflated and under-reported
5. **Give the Playbook's difference catalog a column for "could the tool that detects this difference
   be affected by the same difference?"**

### How to check

```bash
# Surface host-dependent patterns inside the detection scripts
grep -nE 'test -[ed]|\[ -[ed] |realpath|readlink -f|grep -P|sed -i |date -d |stat -c |sort -V' \
  00-analysis/detection/*.sh
# Derive the expected count independently from the primary source and reconcile it with the output
```

### Anti-patterns

- ❌ Judging that a file exists with `test -e` (a false negative on a case-insensitive filesystem)
- ❌ Treating the fact that a count was produced as evidence that detection works
- ❌ Reusing a script that worked locally (macOS) as the judgment for the target (Linux)

### Example

For a category that detects static-asset reference paths whose letter case does not match the real
files — and therefore 404 on Linux — the first implementation judged existence with
`[ -e "app/Bookstore.Web/$rel" ]`. macOS's default filesystem is case-insensitive, so it judged
`Content/images/...` to "exist" and **detected nothing**. Worse, a separate bug (treating `grep -n`
line numbers as paths) **produced an inflated count of 21, so it "looked like detection was
working"**. The fact that a number came out delayed finding the error. Switching to a strict
comparison against the real filenames from `git ls-files` (`grep -qFx`) correctly detected 4.
The same project also tripped over `grep -P` (BSD grep has no `-P`).

---

## CP-13: Give every detector a negative test (replace human independent verification with a machine check)

### Purpose

**"Zero findings" reads as "none exist" AND as "the detector cannot detect".** Detection power is
unproven until you break the detector and check. Making this mandatory **replaces what human
independent verification was for (doubting the verifier itself) with a mechanical, re-runnable form.**

CP-12 covers *how a detector is written* (never asking the host environment). CP-13 covers *whether it
can actually detect* (proof of capability). CP-8's causal proof aims at **confirming a root cause**;
this one targets **the capability of the checker**.

### Rules

1. **Give every detector at least one negative test.** Deliberately create the state that should be
   detected and **confirm EXIT != 0 (or that the count rises)**
2. **Run the negative test at the same analysis stage as the failure you are measuring.** To measure a
   compiler's detection power, inject a **semantic error, not a syntax error** (a syntax error is
   reported at parse time and proves nothing about reaching semantic analysis)
3. **Record the result.** Not "we did it" but **what you broke, how, and what came out**. The record
   goes in the "Negative Test Record" section of `docs/decisions/decisions.md`, with the perspective ID (`MP-N`)
4. **Doubt the checker itself.** A negative test measures **the checker's capability**, not the subject
5. **Before declaring `unaddressed` zero, require a negative-test record for every perspective in the
   ledger** (`./verify.sh adaptation` compares the two sets of perspective IDs)

### What to doubt (the verification-validity checklist)

A negative test confirms the detector can discriminate the claim. Accidents concentrate here.

- **Are ON and OFF measuring the same artifact?** (artifact overlays, an already-installed old artifact, caches)
- **Is the observation itself sound?** Does the grep break at a boundary and misread success as "blank"? Is there a **non-empty assertion**?
- **Does the test satisfy the bug's firing condition?** Does it reproduce the **order and preconditions** of the real user path?
- **Was it fixed with the protection left ON?** (never adopt a fix made by disabling a security mechanism wholesale)

### Why it can replace human independent verification

Independent verification (having an isolated refuter try to show a declaration false) does find defects,
but it is expensive and **runs only once**. A negative test does the same job and **keeps running forever.**

| | Human independent verification | Detector negative test |
|---|---|---|
| Cost | Preparing, running, adjudicating, recording a refuter | One command |
| Re-run | **Impossible** (one shot) | **Infinitely re-runnable** |
| Subject | Documents and numbers | **The detector's detection power itself** |
| Record | Thousands of characters | An exit code |

**Measured**: of roughly 29 findings from human independent verification, **about 15 were "bookkeeping
mistakes in the up-front analysis artifacts"** (wrong counts, ID collisions, a gap in the coverage baseline,
inconsistent units) — defects that existed only because heavy up-front analysis had been produced.
The CP-11 revision makes those artifacts disappear. On the same project the negative tests found the
coverage checker's false negative from `pipefail` × SIGPIPE (**reported as 11% when it was really 100%**),
a scan pattern's omission, **a defect in the consistency checker itself** (it was picking up the
documentation's own example as real data), and that the compiler flagged only **1 of 3** type mismatches.

**Human independent verification is kept for exactly two things: the migration completion declaration
and a HOLD-1 functionality exclusion**
(the procedure is in [harness/skills/migration-adversarial-review](../harness/skills/migration-adversarial-review/SKILL.md)).
Building the perspective table for a new migration route is **primary-source research, not review** —
a detector cannot discover it.

### How to check

```bash
# Break the detector and confirm EXIT != 0 (a 0 means no detection power = a defect in the detector)
cp detector.sh /tmp/neg.sh   # deliberately break the expected value or the pattern
bash /tmp/neg.sh; echo "EXIT=$?"

./verify.sh adaptation       # reconcile the ledger's perspective IDs with the negative-test records
```

### Anti-patterns

- **Using zero findings as the basis for "addressed"** — it may just mean nothing was detected
- **Confirming that semantic analysis was reached with a syntax error** — the wrong stage proves nothing
- **The detector's author settling for "it should work"** — a checker's defects surface only in a negative test
- **Recording only "we ran the negative test"** — what was broken, how, and what came out is not reproducible



<!-- ENTRIES END -->
