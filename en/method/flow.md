# Method — Migration Flow (Phase 0-4)

The pattern (methodology) for migration and modernization. Domain- and tool-independent.
Domain-specific viewpoints come from each Playbook (`../playbooks/<domain>/`), and AI execution
discipline comes from the Harness (`../harness/`).

## Flow Overview

Passing each Phase boundary is Tier 2 (a synchronous gate): reconcile against the Phase completion
conditions, surface implicit decisions, review the ADR track record, and take stock of knowledge
(harness core discipline "HOLD-8" = Tier 2, the stop-and-confirm zone).

**Independent verification (skills/migration-adversarial-review) is limited to the "migration completion
declaration" and a "HOLD-1 feature exclusion", and it runs exactly once** (findings are opened in the
adaptation ledger and closed with a disposition; the lenses are not swept again).
At every other boundary a **detector negative test** (CP-13) does the same job mechanically, and in a
re-runnable form. In particular it **does not apply to confirming the work-plan (Phase 2→3)** —
work-plan rows can be added or changed in Phase 3, so this is not irreversible, and a planning error is
exposed with far greater precision by Phase 3's build and golden-path E2E.
Findings left over at a reversible boundary are carried into the adaptation ledger as `unaddressed`
rows and work moves on.

**All you need to start is "the root path of the source tree" and the "off-limits" list.** The current
stack is revealed by the Phase 0a analysis, and the migration target stack is decided in Phase 0b.
Everything else about the project is filled in by the agent during the startup interview
(harness core discipline "Startup Interview").

```
Phase 0a: Assessment — running the code analysis   ★ you can stop here (stop point 1)
  → Repository inventory: enumerate every repository / build root under the target root and
     record them in repository-inventory.md (do not rely on the presence of .git alone)
  → **Decide how to proceed (do this first)**: if the analysis results already exist, use them.
     Skip the git preparation, the transform-config creation and running ATX entirely (0a-0)
  → Confirm the analysis scope (a light stop point. Default is all of them; the user says what to drop)
  → Per-repository git preparation: git init if unmanaged (only the permitted operations),
     or record the branch name and HEAD before the run if already managed
  → Create the transform-config (per repository. Within 4096 bytes. The Playbook provides templates)
  → Run the ATX analysis: **AWS/comprehensive-codebase-analysis (structure, technical debt),
     one per repository**. Parallel across repositories
     * The unit of parallelism is the git work tree. Parallel runs inside one work tree are impossible
     * When using results that already exist, this step itself is not performed (0a-2b). Not knowing the
       commit the analysis saw is the default and is covered by the Phase 2 corroboration (CP-3).
       Never stop for that confirmation
  → Record provenance, exit codes and the source-branch return check in analysis-runs.md
  → Generate 00-analysis/README.md (the entry point to the deliverables)
  == Phase gate == the completion conditions are checked mechanically by `./verify.sh assessment`
     Whether to stop is decided by "Assessment only" in migration-project.md:
       yes (default) -> stop and confirm. The deliverable is "the analysis results themselves"
       no            -> do not stop; go straight to 0b (nothing for the user to decide between 0a and 0b)

Phase 0b: Consolidating the assessment results   ★ you can stop here (stop point 2)
  → Cross-repository integration: system-wide diagram, cross-cutting environment diff table
     * **With a single target repository the diagram and the contract inventory are N/A** (record the grounds in the ledger and skip)
  → ★ Fix the migration's coverage baseline: pick **the perspectives in the Playbook's perspective table
     (analysis-appendix.md) that apply to this target** (CP-11). **Never make a code pattern scan's
     hit count the coverage baseline** — pre-empting the perspectives the build enumerates has no value,
     and mixed units make the arithmetic meaningless
  → ★ Inventory of contracts between repositories (API / event / shared DB / shared file)
     — the frontend/backend boundary is subject to HOLD-2 and has the highest back-out cost
  → Organize the technical debt and the candidate migration targets (LTS, support status, compatibility chain)
  → Rough estimate of the work size and the main risks
  → ★ Decide the migration policy (recorded as an ADR. User approval required) — **the target stack is decided here**
  == Phase gate (Tier 2 = HOLD) == the deliverable is "material for the go/no-go decision".
     If you stop here: hand the decision of whether to proceed back to the user

Phase 1: Preparation
  → Investigate the changelogs of dependent libraries (for domain-specific viewpoints see analysis-appendix.md)
  → ★ Fix the baseline mode and capture it (CP-5):
      Mode A (measure on the old environment) = if the old environment is usable, observe the real
        system and turn it into Characterization Tests
      Mode B (define by reading the code) = with no old environment, define the expected behavior by
        code reading (always state the grounds and the confidence)
      Mode C (reuse the existing tests) = modernize the existing unit/E2E tests and run them
        (note that migrating the test infrastructure itself enters the work scope)
  → ★ Decide the scope of the non-functional requirements (record performance / leaks /
      fault tolerance / security as in or out of scope, as an ADR. User approval required)
  == Phase gate (Tier 2 = HOLD) ==

Phase 2: Analysis and planning
  → Corroborate the ATX results against the real code (CP-3). **The more a result was ingested, the more valuable corroboration is**
  → Build the "ATX finding vs. real code" comparison table
  → Code transformation is done by the agent through direct modification. Do not use ATX's Managed
     Transformation (MT) or Transformation Definition (TD) for the conversion. With ATX's transformation
     the decision on each individual change does not come up to the user and no ADR is left behind
     (ATX is used only for the Phase 0a analysis)
  → Create the staged work-plan (minimal configuration → incrementally add functionality).
     With multiple repositories, Steps are assigned per repository and the migration order itself
     becomes an ADR-level decision
  → ★ Prepare a **detection command and a negative test** per perspective (CP-11 / CP-13).
     The counts are obtained in Phase 3 by running the detectors (do not quantify everything at planning time)
  → ★ At the moment the work-plan is finalized, register every in-scope artifact from the
     success-criteria table into verify.sh's expected list (CP-7). Register them even if not built yet
  → ★ Rewrite `WORK-PLAN-STATUS` in work-plan.md to CONFIRMED
     — this makes verify.sh's build/smoke/integration gates apply for real
  → Reflect the knowledge documents (under the Playbook's reference/)
  == Phase gate (Tier 2 = HOLD) == work-plan approval
     ★ **No independent verification.** Work-plan rows can be added or changed in Phase 3, so this is
       not irreversible. Confirm only two things: that the applicable perspectives from the perspective
       table were selected, and that every perspective has a detector and a negative test. The validity
       of the plan itself is verified by Phase 3's build and golden-path E2E

Phase 3: Implementation and verification loop (Tier gate operation — see the harness core discipline)
  → Step 1: Use setup-modernized.sh to prepare the modernized tree (../<product>-modernized)
            Record the starting-point information in session-context.md and work-plan.md
            ★ Implement verify.sh's smoke gate when Step 1 completes
              (proceeding to Step 2 or beyond while it is unimplemented is forbidden)
  → Implement in the Step order of the work-plan:
      Tier 0: work inside the plan runs autonomously as long as verify stays all-PASS
      Tier 1: records, knowledge notes, commits and Step transitions proceed without stopping
              (humans batch-review them later)
      Tier 2: stop on a mechanical trigger (feature exclusion / wire format change /
              three hypothesis-log rows / an ADR-level decision, etc.) and ask for a human
              decision with an ADR draft attached
  → ★ Run the perspective's detector to obtain **that perspective's full count** → fix → re-run to zero → freeze it in verify (CP-11)
  → At each Step run all eight gates of ./verify.sh (build → smoke → integration [→ nonfunc]
     → repo-sync → knowledge → adaptation → project)
     → commit (code on the modernized tree, records on the records repository)
  → Reconcile against the success-criteria table (CP-6)
  → At session end: run the session-end checklist (commit + push + consistency check on both repositories)
  == Phase gate (Tier 2 = HOLD) ==

Phase 4: Final verification
  → Build with all modules enabled, run all tests, check the diff against the baseline
  → Reconcile the adaptation ledger: the unaddressed count must be zero
  → ★ Re-run every perspective's detector and leave the negative-test records (CP-13)
  → ★ Independently verify the migration completion declaration (skills/migration-adversarial-review) —
     it is not settled by the producer's own report. Try to refute it through the two lenses
     (lost functionality / scope), confirm the coverage of the perspective table, and record it
     (./verify.sh adaptation FAILs without the independent-verification and negative-test records)
  → ★ **Independent verification runs once.** Open the findings in the ledger, give each a disposition
     to close it, and re-run `./verify.sh` to confirm all-PASS. **Do not sweep the lenses again**
     (convert them into a machine-runnable check and freeze them)
  → ★ Return the new perspectives you encountered to the Playbook's perspective table (CP-11. Do not let them end with the project)
  → If extra work is needed, do it via "Start subtask: <taskname>"
```

**Follow-on tasks after Phase 4 (out of scope for this flow, for reference only):**
Designing and building the deployment environment (architecture design → automated review → IaC
implementation) is a task that always arises in a real migration. Constraints of the target
environment can also flow back into application changes (real example: migrating from a local
file-based search engine to a managed search service in order to support a multi-instance
configuration). For now this is not included in this flow; plan it separately together with the
infrastructure guardrails of the AI-driven development process (preventive and detective controls).

Note: the completion criterion is always "evidence in the form of test and observation results",
never "approval of a document".
Note: a single repository follows the same procedure as the "N=1 special case" (the inventory is one
row, and no parallelism arises).

## About the Phase Structure (a design note)

Two proposals come up whenever someone tries to shorten the flow. Both were considered and rejected.

**Merge Phase 0 into Phase 1.** Rejected. Phase 0 and Phase 1 **ask the user for decisions of different
weight**. Phase 0 produces the material for deciding *whether* to do this at all, and stopping there is a
legitimate outcome (assessment-only use). Phase 1 decides *how*, after the decision to proceed has been
made, and stopping there is a failure. Merging them **erases that boundary, so an engagement that stopped
at the assessment looks "incomplete"**.

HOLD-8 (the Phase gate standard check) also applies uniformly at Phase boundaries. Merging would put
**two deliverables of different natures — the Phase 0a analysis results and the Phase 0b migration
policy — behind a single gate**, which hollows out the check.

**Phase 1 is thin, so merge it into Phase 2.** Rejected. Phase 1 is thin **by design**. It is not a stage
where work happens; it is the **decision gate** that finalizes the work-plan in light of the Phase 0
analysis. The thinness is a feature, not a defect. Merging them would put finalizing the plan and
starting the implementation in the same Phase, blurring the moment `WORK-PLAN-STATUS: CONFIRMED` is
stamped (and because gate applicability switches on that marker, blurring it hollows out the day-one
registration of the expected list).

**Phase numbers are not renumbered.** They are a shared anchor across the whole document set, and `Phase`
is fixed as a term that is not translated between Japanese and English. Renumbering ripples widely.

## Three Exit Points

The flow is designed so that three ways of using it work through the same path.

| Exit point | Deliverable | Use case |
|------------|-------------|----------|
| **End of Phase 0a** | ATX analysis results (converted to HTML), repository inventory, run ledger | You want the analysis results themselves. Handing over to another team, internal review |
| **End of Phase 0b** | Cross-cutting integration, candidate targets, rough size and risks, migration policy ADR draft | You want to decide whether to migrate |
| **End of Phase 4** | The migrated modernized tree and the verification records | You want to complete the migration |

Even when stopping at Phase 0a/0b, `install.sh` does exactly the same thing (no separate mode).
While the work-plan is unconfirmed, verify.sh's build/smoke/integration gates are "not applicable",
and they switch to applying for real at the moment Phase 2 sets CONFIRMED.

## Items the User Must Decide Explicitly

The following are **not decided automatically by the flow and require an explicit decision from the
user**. Read through them at the start of the project and do not leave the applicable decisions
implicit. Most are recorded as ADRs (= you will be asked for approval at Tier 2).

| # | Decision | When | What happens if you don't decide |
|---|----------|------|----------------------------------|
| 1 | **Fixing the repositories to analyze** (in/out of scope and why) | Phase 0a | The analysis cost grows in proportion to the repository count. "Out of scope" becomes implicit and drifts later |
| 2 | **Migration policy** (target stack, policy for features to exclude) | Phase 0b | Deciding before seeing the analysis gets the premises wrong. Not deciding blocks the Phase 2 plan |
| 3 | **Baseline mode selection** (A = measure on the old environment / B = define by reading the code / C = reuse the existing tests) | Phase 1 | Once the old environment is gone, measurement is impossible. The confidence risk of Mode B (define by reading the code) becomes invisible |
| 4 | **Scope of non-functional requirements** (performance / leaks / fault tolerance / security, in or out of scope) | Phase 1 | "Out of scope" becomes implicit and drifts as a leftover gate late in implementation (there is a real case where the scope of a memory-leak verification tool stayed undecided until late in implementation) |
| 5 | **Migration order across repositories** (backend first, or together) | Phase 2 | The compatibility window for inter-repository contracts is never designed, and integration becomes impossible mid-way |
| 6 | **Plan for long-running tests** (e.g. hour-scale operation tests: who runs them and when) | Phase 1-2 | The executor is never decided and it keeps getting deferred |
| 7 | **Tuning the Tier 2 triggers** (relaxing the criteria when they fire too often, Tier demotion based on the ADR track record) | Phase gates | The gate becomes either a formality or excessive. Relaxation is done explicitly, based on track-record data |
| 8 | **Taking stock of knowledge** (consolidating/deleting practices and LLs) | Phase gates / retrospectives | Knowledge files bloat and become noise |
| 9 | **Guardrails when the AI operates cloud resources** (IAM boundaries, Policy as Code) | When applicable | This framework assumes work within a single host; controls for cloud operations are **not provided**. Set them up separately if needed |
| 10 | **Whether production-like data may be used in tests** (masking and anonymization rules) | When applicable | Compliance risk. Rule-making always stays a human decision (Tier 2) |

## Design Principles

1. **Single Source of Truth**: behavioral discipline lives in the harness; domain knowledge lives in the Playbook (practices.md)
2. **Constraints > Prompts**: rules are enforced mechanically by `./verify.sh`. Do not trust constraints that exist only in prompts
3. **Tier governance**: concentrate human judgment on decisions with a high back-out cost and on the milestones where understanding is formed. Define escalation conditions by mechanical criteria (harness core discipline)
4. **Completion criteria are evidence**: the completion of each Phase/Step is judged by an accumulation of test and observation results, not by document approval
5. **AI output is a hypothesis**: always corroborate AI analysis results against the real code (CP-3). Inferred project settings are treated the same way, and their provenance is distinguished
6. **Build success ≠ done**: not done until observed by a runtime test (CP-4)
7. **Verification gate = the success-criteria table**: include every criterion in automated tests (CP-6). Register every in-scope artifact on day one (CP-7)
8. **Accumulate knowledge**: keep common knowledge in `practices-common.md`, domain knowledge in `practices.md`, and project-specific lessons in `lessons-learned.md`. Record not only the adopted option but also the rejected options and why
9. **Never count in advance what the toolchain can enumerate**: what you hold in advance is "the perspectives the build **stays silent** about or **misleads** you on", not a code scan's hit count. Perspectives are grown across projects in the Playbook (`analysis-appendix.md`) as a per-migration-route asset (CP-11)
10. **A perspective carries its detection command**: a prose-only perspective never yields the full count. Give every detector a **negative test** and show mechanically that "the detector really can detect" (CP-13). At boundaries other than the completion declaration and feature exclusion, this is what replaces independent verification
