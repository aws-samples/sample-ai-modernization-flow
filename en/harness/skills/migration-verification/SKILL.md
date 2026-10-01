---
name: migration-verification
description: Operational details for the verification gate (verify.sh) and rules for recording tests. Reference when configuring/extending verify.sh, judging Step completion, or conducting, recording, and promoting ad-hoc tests.
---

# Verification Gate Operational Details

## All eight gates

The gates fall into two groups. **Applicability is switched by a machine-readable marker in `work-plan.md`.**

```
<!-- WORK-PLAN-STATUS: DRAFT     -->  → group 1 below reports "not applicable" and exits 0
<!-- WORK-PLAN-STATUS: CONFIRMED -->  → they apply for real; an empty expected list FAILs build (CP-7)
```

Check applicability with `./verify.sh status`.

**`./verify.sh assessment`** is separate from the eight gates above: it **checks the Phase 0a completion
conditions mechanically**. It **runs automatically from `all`, conditionally**: if
`00-analysis/analysis-runs.md` holds at least one recorded analysis run (i.e. Phase 0a has started) it
runs; with zero rows it does not (putting it in unconditionally would make it fail from day one and breed
the habit of "of course it fails"). `./verify.sh status` shows whether it applies.
It looks at whether the inventory is filled in, that
exclusions carry a reason, the 0a-2 user confirmation, the exit code and output location of each analysis
run, the git restoration, the entry point to the results, and that the records were updated.
On an engagement that will proceed to migration ("Assessment only" = `no` in `migration-project.md`),
**it replaces the human confirmation at the end of 0a and 0b follows directly.**

### Group 1: switched by work-plan confirmation (artifacts and behaviour)

| Gate | Content | Implementation timing |
|--------|------|---------|
| build | Confirms existence of expected deliverables (expected-list approach) | Registered fully at work-plan finalization (day one) |
| smoke | Startup and basic behavior (e.g., CLI --help, process liveness, dependency resolution. See Playbook's verify-snippets.md for implementation examples) | **At Step 1 completion (mandatory)** |
| integration | Integration/E2E behavior (invokes 02-test/integration/*.sh). With `REQUIRE_GOLDEN_PATH=1`, a golden-path E2E is mandatory | Added at each Step |
| nonfunc | Non-functional (opt-in. Only when Phase 1's ADR decision marks it "in scope") | After the in-scope items are finalized |

### Group 2: always applying (records and discipline)

These are in force from Phase 0 regardless of the work-plan state. The design **rejects only an
unrecorded violation**: recording the reason lets it pass (the judgment stays with the human).

| Gate | Content | Marker that lets it pass |
|--------|------|------------------------|
| repo-sync | Uncommitted sync across the records repo and every modernized tree, unrecorded dirty, leftover committed `DIAG-`/`STUB-`, forbidden patterns, commit-time divergence | `REPO-SYNC-DIVERGENCE-OK` |
| knowledge | Volume of the knowledge files (300 bytes per summary row / 80 body lines / 15 entries) | `KNOWLEDGE-REVIEWED` |
| adaptation | Adaptation ledger (missing coverage baseline definition, missing `path:line` evidence, missing reason on not_required/replaced, report of the unaddressed count). Requires **the independent-verification record** and **a negative-test record for every perspective in the ledger** once unaddressed reaches zero (CP-13) | — |
| project | Provenance of the project information (no `⟨inferred⟩` after the work-plan is confirmed) | `INFERRED-REMAINS-OK` |

## Principles of the Expected List (CP-7)

- **Register all deliverables within scope when the work-plan is finalized.** Register even those that cannot yet be built
  (for an unregistered deliverable, the very fact that it has "not been built" goes undetected)
- Changing the expected list = changing scope = HOLD-3 (Tier 2 / stop-and-confirm zone)
- For excluded deliverables, leave a comment with the reason (ADR-N)

## Rules for Judging Completion

- Do not record something as "complete" unless `./verify.sh` fully PASSes (CP-4, CP-6)
- At Step completion, cross-check against the success-criteria table in the work-plan to confirm no test is missing (CP-6)
- Name verification gate files so they are not overwritten by the build system (`verify.sh` + `make -f`)

## Changes That Cannot Be Called "Complete" Until Confirmed by Testing

- Changes to fixed strings or constant values
- Code where only one branch of a conditional is ever executed
- Changes to default configuration values
- SSL/TLS-related changes

## Recording and Promoting Ad-hoc Tests

When performing individual tests outside verify.sh (startup checks, strace, property checks, etc.):

1. Create a results file under `02-test/test-results/` (`<stepN>-<test-name>.md`)
   - Content: test date/time, purpose, prerequisites, procedure (in a copy-paste-executable form), results table, and verdict
2. If reproducible, create a reproduction script under `02-test/integration/`
   - The script should be self-contained: "set up prerequisites → execute → observe → PASS/FAIL verdict (rc=0 is PASS)"
3. **Once scripted, register it in verify.sh's INTEGRATION_TESTS** (promote prompt-dependent verification to a gate)

Criteria for recording:
- Recording is required when confirming something beyond "build succeeded" (process startup, RPC registration, output verification, etc.)
- Recording is not required when the verify.sh execution result alone suffices for judgment (e.g., binary existence check)

## Test Environment Prerequisites

- Prerequisites needed for testing (daemon startup, environment variables, directories, permissions) must be documented explicitly in the
  "Prerequisites" section of `02-test/test-procedures.md`. Volatile prerequisites (those lost on restart) must also be included in the session start procedure.
