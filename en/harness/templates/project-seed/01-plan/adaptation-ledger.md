# Adaptation Ledger

<!-- A ledger that enumerates, **one row per perspective**, the places that must be touched because of
     the migration, and drives the unaddressed count to zero.
     The expected list (verify.sh's build gate) counts "artifacts that should exist", but it cannot
     detect "a place the platform change required you to fix and you forgot". This ledger covers that.

     In Phase 0b only [pick] the perspectives (to show scale and risk). Rows are opened in Phase 2,
     together with the work-plan. The counts are obtained in Phase 3 by running the detectors.
     For the procedure see CP-11 / CP-13 in method/practices-common.md. -->

## Definition of the coverage baseline [REQUIRED]

<!-- ★The coverage baseline is "the perspectives in the Playbook's perspective table
     (00-analysis/analysis-appendix.md) that apply to this target". Always state which ones you selected
     and which you did not (CP-11).

     **Never make a code pattern scan's hit count the coverage baseline.** Pre-empting ① (the perspectives
     where the build enumerates the places to fix) with a static scan has no value, and because the
     counting unit differs per perspective the arithmetic does not hold (measured: the count was
     corrected three times, and lines / unique paths / files were mixed so increases and decreases
     could not be compared). Draw only **② the silent perspectives** (the build succeeds and it breaks
     only at run time or in production) and **③ the misleading ones** (the build fails but the
     straightforward fix breaks something else).

     **Do not use a list of specs or rules extracted by an AI as the coverage baseline either.** An extract's
     errors are caught by corroboration against real code (CP-3), but what it never wrote stays missing
     from the coverage baseline and nobody notices.

     Once filled in, place one marker line in this form. The adaptation gate in verify.sh checks that
     it exists:
       <!- - POPULATION-DEFINED: perspectives=9 (silent=6 misleading=3) excluded=4 - ->
     (the example above has its hyphens separated; write it as a normal HTML comment) -->

| Perspective ID | Kind | Selected / not selected | Detection command / why not selected |
|----------------|------|-------------------|----------------------------------|
| MP-1 | | | |

**Keep one row for the perspectives you did not select too** (e.g. "① — the build enumerates it").
"Drawing every item from the perspective table" dilutes the ledger with rows that match nothing and
creates a false sense of coverage.

**Record the detection commands in a re-runnable form** (for example `00-analysis/detection/`).
Phase 4 re-runs them to confirm the unaddressed count is zero, so losing them makes the verification
impossible to reproduce (CP-11).
**Give every detector a negative test and record the result in the "Negative Test Record" section of
`docs/decisions/decisions.md`** (CP-13. `verify.sh adaptation` reconciles the perspective IDs).

## Disposition

| Disposition | Meaning |
|-------------|---------|
| `addressed` | Handled in the modernized implementation (has a matching success criterion SC-N **or** a CP-13 negative-test record) |
| `replaced` | Substituted with another mechanism on the target (**state what it was replaced with**) |
| `not_required` | Needs no action (**a reason is required**. If functionality is lost, HOLD-1 + an ADR) |
| `unaddressed` | Not yet touched |

**Driving `unaddressed` to zero is the completion condition of Phase 4.**

**A defect that exists with identical behaviour on the source as well (a pre-existing bug) is closed
in a single row as `not_required` (reason: pre-existing bug. Not a regression caused by the migration).**
"Fixing it while we are here" is a decision that steps outside the scope of migration fidelity; to fix
it, go through a HOLD-7-level ADR ("why fix a pre-existing bug inside the migration work") first.

**A one-off, local fix does not need an SC-N.** Most of the fixes that independent verification turns up
are not worth promoting to a permanent integration test, so a negative-test record is enough
(`verify.sh`'s check is aligned with this).

## Totals

<!-- Update at each Phase gate. The trend of the unaddressed count indicates whether omissions are shrinking -->

| Point in time | Total | addressed | replaced | not_required | **unaddressed** |
|---------------|-------|-----------|----------|--------------|-----------------|
| End of Phase 0b (perspectives picked only) | | — | — | — | — |
| End of Phase 2 | | | | | |
| End of Phase 4 | | | | | **0** |

## Ledger

<!-- **One row = one perspective.** Write the `MP-N` from the Playbook's perspective table
     (00-analysis/analysis-appendix.md) as the perspective ID. A perspective discovered mid-project
     that is absent from the table may be opened with the `MP-` left empty, but
     **return it to the Playbook's perspective table in Phase 4** (CP-11).

     `Hits` is the count obtained in Phase 3 by running the detector (blank before the work).
     **Do not fill it in at planning time.** Evidence must always be a `path:line`
     (never rely on an AI summary alone = CP-3). -->

| ID | Perspective (MP-N) | Hits | Evidence (path:line) | Disposition | SC / reason |
|----|--------------------|------|---------------------|-------------|-------------|
<!-- Example (remove this comment when entering real data; rows inside a comment are not inspected by the gate)
| AP-1 | MP-3 | 4 | <path:line> | unaddressed | |
-->

## Reasons for not_required and replaced

<!-- A `not_required` that loses functionality falls under HOLD-1 and needs an ADR and user approval.
     Leaving the ADR number here makes it possible to trace later why this site was left unchanged. -->

| ID | Disposition | Reason / what it was replaced with | ADR | Approved on |
|----|-------------|-----------------------------------|-----|-------------|
| | | | ADR-N | |

## Sites that break without symptoms (caution)

<!-- A site that breaks without raising an exception or exiting with an error is not caught by
     build/unit/smoke. Put a golden-path E2E that walks the real usage path in the integration gate,
     and map it to the corresponding rows of this ledger. -->

| ID | Site / path | Covered by a golden-path E2E | Note |
|----|-------------|------------------------------|------|
| | | yes / no (if no, the reason) | |
