---
name: migration-adversarial-review
description: The procedure for independently verifying a declaration with a context-isolated refuter. It applies to exactly two things — the migration completion declaration and a HOLD-1 feature exclusion — and it runs once (it does NOT apply to confirming the work-plan or to Phase boundaries — CP-13's detector negative tests replace it mechanically). How to isolate the context, the no-fabrication instruction, how to close the findings in the ledger, graceful degradation, and how to leave the record. Consult it before the completion declaration and before approving a HOLD-1 exclusion.
---

# Independent Verification (limited to the completion declaration and feature exclusions)

`verify.sh` guarantees **formal soundness** (artifacts exist, patterns are absent, tests pass).
This skill guarantees **the two things only human eyes can judge**.
**Run it once `verify.sh` is all-PASS** (verifying content while the form is still unmet just produces rework).

## Scope — exactly two declarations

| # | Declaration | When | What to do |
|---|-------------|------|-----------|
| 1 | **The migration completion declaration** | The end of Phase 4 | **Confirm the coverage of the perspective table** (look at the perspective table, not the code). **It runs once.** The findings are closed in the ledger |
| 2 | **Finalizing a feature exclusion / disabling (HOLD-1)** | Before approving the exclusion ADR | **A light, per-item second opinion.** Do not sweep everything |

(1) is the shipping decision itself. (2) drops functionality, and that needs human eyes.
**The moment the adaptation ledger's unaddressed count reaches zero amounts to (1).**
`./verify.sh adaptation` FAILs if unaddressed is zero and there is no **independent-verification record**,
or no **negative-test record for every perspective in the ledger**.

## Where it does not apply — CP-13's detector negative tests replace it

| Boundary | What guarantees it instead |
|----------|--------------------------|
| **Confirming the work-plan (Phase 2→3)** | Work-plan rows can be added or changed in Phase 3, so this is **not irreversible**. A planning error is exposed with far greater precision by **Phase 3's build and golden-path E2E** |
| 0a→0b, 0b→1, 1→2, 3→4 | Each perspective's **detector plus its negative test** (CP-13). For 3→4, the Phase 4 completion declaration re-checks everything |

**Why it was narrowed (measured).** On one project, of roughly 29 findings from independent verification
**the largest category (about 15) was "bookkeeping mistakes in the up-front analysis artifacts"**
(wrong counts, ID collisions, a gap in the coverage baseline, inconsistent units). Those defects existed only
because heavy up-front analysis had been produced, and the CP-11 revision (putting the coverage baseline in the
perspective table) **makes the audited subject itself disappear.** The findings that remain are facts
about the route, and they surface mechanically next time as a perspective plus a detector.
The old lens B (verification validity) **was moved into CP-13's negative tests** — a machine check that
runs forever is cheaper and stronger than a one-shot human audit.

Findings left over at a reversible boundary are carried into the adaptation ledger as `unaddressed` rows
(with `path:line` evidence). **Pinning the carry-over destination to the ledger is the point.**
"Keeping it in mind" is a synonym for "forgetting it".

## The essence is context isolation

What works is not separating role names but **the verifier never seeing the producer's reasoning**.
A self-review inside the same context only re-confirms your own premises.

**What to hand over**: the declaration under verification, plus the checklists and numbers offered as its
grounds / the location of the primary sources (the target source paths / the perspective table / the
adaptation ledger / the success criteria table / the verify results / the modernized tree paths)

**What not to hand over**: the producer's reasoning or summaries / `worklog.md` / `session-context.md` /
the history of judgments such as "this part is fine"

**Shared instruction:**
> Your task is refutation, not confirmation. Try to show that this declaration is false, and when in
> doubt, fall on the side of refutation.
> **If you cannot read a primary source, do not fill the gap with a guess — report `FAILED: <reason>`**
> (fabrication is the worst possible failure).
> Output `{lens, verdict: REFUTED|UPHELD, findings: [{what, evidence}]}`.

**Never omit the no-fabrication sentence.** If a refuter fills in a primary source it could not read with
a guess, **you end up believing it was verified while the content is false**. In a measured case, a
refuter with no file I/O honestly returned `FAILED` on all six items, which is how the mistake was caught.
Without that sentence it would not have been.

## Lenses (two for the completion declaration; a second opinion only for HOLD-1)

| Lens | What to doubt |
|------|--------------|
| **Lost functionality** | Independently search the modernized tree for stubs, mocks and disabled code (do not rely on the `STUB-` markers). Take the **difference** between the ledger's `addressed` rows and the implementation. **Prioritize rows touching screens and UI** ("no exception, HTTP 200, blank screen" is the hardest to see) |
| **Scope** | Are the items that **disappeared or were deferred** from the success criteria table approved as an ADR? Are the reasons for the ledger's `not_required` / `replaced` rows sound (does the replacement actually exist)? |
| ~~Verification validity~~ | **Moved into CP-13's negative tests.** Done mechanically, by breaking the detector and confirming EXIT != 0 |

**The lenses only cover the modernized tree and its runtime behaviour.** The format of the adaptation
ledger, where the ADRs sit, and defects in `verify.sh` itself are not findings — when you notice one, leave
a one-line `LL-N` and add to `verify.sh`, once only, whatever can become a machine check (do not re-open it
as a ledger row). **Including the records in the scope means findings grow as the records grow, and the
completion decision drifts away from what it is supposed to measure.**

**A defect that exists with identical behaviour on the source as well (a pre-existing bug) is not a finding
either.** It is not a regression caused by the migration.

**If even one lens is refuted with concrete findings, the declaration does not stand until those findings
are processed.** Do not dilute it by majority vote. If a finding is suspected to be the refuter's own error,
open the primary source and adjudicate, then
**record why it was confusing and clarify the wording in question.**

## It runs once. The findings are closed in the adaptation ledger

**Independent verification of the completion declaration runs exactly once. The lenses are not swept again.**
Open a row in the adaptation ledger for each finding and close it, one at a time, with a disposition:

| How the finding is handled | Disposition | What else is required |
|---------------------------|-------------|----------------------|
| Fix it | `addressed` | An observation that says the fix is right (an SC-N or a CP-13 negative-test record) |
| Do not fix it | `not_required` (a reason is required) | The reason. **If functionality is lost, HOLD-1 + an ADR (human approval)** |

**Re-verify the fixes with `verify.sh` and with the golden-path / negative test that matches the fix.**
Rather than running a human lens a second time, convert it into a check that a machine runs and freeze it there.

**Why once (measured).** On one project that ran five rounds, the defects in the target application fell
8→5→6→2→1 while the total number of findings **plateaued** at 16→12→17→8→8. From round 3 onward most of the
findings were about the ledger's totals, where the ADRs sat, and bugs in the detectors themselves (all out of
the lenses' scope, as above), and **"re-run until nothing can be refuted" does not converge.** Deciding on
one round and closing the findings in the ledger is cheaper than leaving the cut-off to human judgment, and
what remains open stays visible in the ledger.

## Graceful Degradation (tool-independent)

| Step | Means | Degree of isolation |
|------|-------|--------------------|
| 1 | Have another agent (a sub-agent) refute it | High |
| 2 | **Re-verify in a separate session** (without reading the previous session's reasoning) | Medium |
| 3 | A human sign-off (a human opens the primary sources and confirms) | Depends on who does it |

**At step 1, test with a single item before the real dispatch.** The tools a sub-agent is granted
**change with the role you specify**. Choose a role without the file I/O needed to read primary sources
and the refuter can read nothing, so the verification does not hold (measured: a batch of six was
dispatched and all six failed). The test only has to confirm "could it read one primary-source file?".

**The record is mandatory on every path.** An independent verification with no record is the same as none.

## The Record (this skill's mandatory responsibility)

Regardless of the outcome, append to the "Independent Verification Record" section of
`docs/decisions/decisions.md`. The section carries the machine-readable marker
`<!-- INDEPENDENT-VERIFICATION -->`, and `./verify.sh adaptation` checks that **a row containing a date exists**.

Columns to record: the declaration (the migration completion declaration / a feature exclusion (ADR-N)) /
the date / the round / the means (another agent's refutation, a separate-session re-verification, a human
sign-off) / the verdict per lens (lost functionality, scope) / **the verification scope** (what coverage baseline,
how many items — **leaving it blank is a violation**) / what was sent back

**A record that only says "it was done" is a violation.** Without the verification scope, there is no way
to tell "we looked at 10 items and declared the whole" from "we looked at all of them".

## Notes

- The target source is read-only (never change its contents)
- **If findings are zero, suspect that the lenses are designed too softly.** It only runs once, so the
  design of that one round decides the quality
- **For a layer that produced serious findings, do not stop at the individual fixes.** Record **why the
  producer's own review did not reach there** as an LL or CP, and make it something a detector (CP-13) can
  catch next time. Never dismiss it as "the independent verification is working well"
- Independent verification is work that exercises judgment. **Even when delegated to a sub-agent, never
  drop to a lighter model** (see "Model Assignment" in the core discipline)
