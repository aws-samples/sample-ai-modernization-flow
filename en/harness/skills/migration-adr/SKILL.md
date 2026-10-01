---
name: migration-adr
description: Drafting ADRs (Architecture Decision Records) and the lightweight hold protocol, the feature-exclusion flow (HOLD-1), the standard Phase-gate confirmation (HOLD-8), and Decision Queue operation. Refer to this when making design decisions, excluding features, or passing a Phase boundary.
---

# ADR / Tier 2 (HOLD) Hold Procedure

## Standard ADR Draft (Lightweight Hold Protocol)

When holding at HOLD-1/HOLD-2/HOLD-7, present a draft with the following standard 4 sections.
Summarize it at a granularity the user can approve, revise, or reject in a single remark:

```markdown
## ADR Draft: <Title>

- **Background**: <Why this decision became necessary. Based on observed facts>
- **Options**: (1) ... (2) ... (3) ... (one line each on impact, whether functionality is lost, and compatibility for each option)
- **Proposed decision**: Recommend (N). Reason: <why>
- **Impact**: <Constraints this decision imposes on subsequent work. Future cost of change>
```

- Once approved, record it formally in `docs/decisions/decisions.md` immediately before the `ENTRIES END` marker
  (use `grep -n '^<!-- ENTRIES END -->$'` to locate the exact line)
  (add the decision date and phase; numbering is the existing maximum + 1)
- **When in doubt, write an ADR and hold. Having too many ADRs is never a fault** (not writing one is the problem)
- **While waiting for a decision, you may proceed with other work that doesn't depend on it (record maintenance, preparing the next Step, etc.)**

## Decision Queue Operation

Manage pending decisions in the Decision Queue table in `session-context.md`:

| # | Decision item | ADR draft presented on | Status | Blocked work |
|---|---------|-----------------|------|-------------------|

- Once a decision is made, record it formally in decisions.md and remove the row
- If the Queue has unresolved items at the end of a session, state this explicitly in the end-of-session report

## HOLD-1: Feature Exclusion Flow

Before disabling or removing a feature to resolve a build error or similar issue, you MUST always go through the following:

- a. Describe the facts of the problem (what doesn't work, and why)
- b. Enumerate the options (fix / alternative implementation / exclude / stub out)
- c. State the impact of each option explicitly (whether functionality is lost, compatibility)
- d. **Confirm with the user** ("Is it acceptable to exclude this feature?")
- e. Record the decision outcome in an ADR before proceeding to implementation

Exceptions and principles:
- "Choosing an alternative implementation path" (achieving equivalent functionality by another means, with no loss of functionality) does not require confirmation. However, the reason must still be explained
- If the functionality itself would be lost, confirmation is always required
- **When in doubt, err on the side of "exclude" and confirm**
- For excluded items, leave the reason (with the ADR-N reference) in the work-plan's out-of-scope table and in the verify.sh comments

- **Set the disposition of the corresponding adaptation-ledger row to `not_required` (reason required).**
  An exclusion not reflected in the ledger is FAILed by `./verify.sh adaptation` as "no reason"
- If you settle for a temporary stub, tag it `// STUB-<id>:` (repo-sync FAILs if it survives into a commit)
- **Verify independently before finalizing an exclusion** (skills/migration-adversarial-review);
  an exclusion is an irreversible declaration. **A light, per-item second opinion is enough** — do not sweep everything

## HOLD-8: Standard Phase-Gate Confirmation

Hold at Phase boundaries (0a→0b→1→2→3→4) and present the following:

1. **Result of checking against the Phase completion criteria checklist** (completion criteria from analysis-procedure / work-plan)
2. **Surfacing implicit decisions**: Self-check whether "anything was implicitly decided during this Phase (a decision not recorded as an ADR)".
   Look for traces of decisions in the worklog, commit log, and exclusion table.
   If any are found, present an ADR draft (record it even after the fact — retroactive record maintenance is a legitimate procedure)
3. **ADR track-record review**: Present the Decision Queue and the ADR log. If there is a category where the human has
   kept approving without modification, propose downgrading it to Tier 1 (draft creation + batch review).
   Any relaxation must always be made as an explicit rule change based on track-record data (never automate by drift)
4. **Knowledge stocktaking**: Propose consolidating/removing old or duplicate entries in the playbook / lessons-learned
   (`./verify.sh knowledge` mechanically detects an over-limit condition. If it is over, either
   consolidate or record the reason for not consolidating as `KNOWLEDGE-REVIEWED`)
5. **State of the adaptation ledger**: present the output of `./verify.sh adaptation` (total, unaddressed count)
6. **The results of the detector negative tests** (CP-13): append the record of having broken each
   perspective's detector and confirmed EXIT != 0 to the "Negative Test Record" in
   `docs/decisions/decisions.md`, and present a summary of it.
   **Human independent verification is not performed at a Phase boundary** — it applies only to the
   **migration completion declaration** and a **HOLD-1 feature exclusion**
   (skills/migration-adversarial-review).
   Findings left over at a reversible boundary are carried into the adaptation ledger as `unaddressed`
   rows (**state the count and the IDs in the report**).
   For either record, "it was done" alone is a violation (write what you broke and what came out /
   the verification scope)

## Criteria for Whether Something Warrants an ADR (HOLD-7)

- "If this decision is changed in the future, will it ripple beyond a single code fix?"
- "Would a future maintainer ask 'why was it done this way'?"

If the answer to either is Yes, it warrants an ADR. Example: a change to a library's packaging structure (slib consolidation)
looks like a local build fix at first glance, but it created the lasting constraint that "all utilities from now on
must not use static linking" (ADR required).
