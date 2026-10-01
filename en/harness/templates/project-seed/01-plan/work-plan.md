# Work Plan

<!-- Create this following the procedure in analysis-procedure.md upon completion of Phase 2 -->

<!-- WORK-PLAN-STATUS: DRAFT -->
<!-- ↑ verify.sh uses this marker to decide whether the verification gates apply
     (machine-readable; do not change the format).
     Once this plan is approved at the Phase 2 phase gate (HOLD-8), rewrite it to CONFIRMED.
     From the moment it becomes CONFIRMED the build/smoke/integration gates apply for real,
     and they FAIL if the expected list is still empty (CP-7). -->

## Overview

| Item | Value |
|------|---|
| Migration target | <PRODUCT_NAME> |
| Migration source | <SOURCE_OS> (<SOURCE_ARCH>) |
| Migration target | <TARGET_OS> (<TARGET_ARCH>) |
| Start date | YYYY-MM-DD |
| baseline mode | A (measure on the old environment) / B (define by reading the code) / C (reuse the existing tests) ← fixed in Phase 1 (1-2) |

## Non-Functional Requirements Scope (reflects the decision from Phase 1 (1-3))

| Item | In scope / Out of scope | ADR | Verification method (if in scope) |
|------|-----------|-----|---------------------|
| Performance | | ADR-N | verify-nonfunc (nonfunc-perf) |
| Resource leaks | | ADR-N | verify-nonfunc (nonfunc-leak) |
| Fault tolerance | | ADR-N | 02-test/integration/ |
| Security | | ADR-N | |
