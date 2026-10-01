# Test Patterns by Migration Theme — C / Solaris x86 → Amazon Linux

A collection of test patterns for behaviors that tend to break in this domain, which should be
**systematically** incorporated into the baseline (Characterization Test) and the verify integration gate.
(For the common framework, see the harness's baseline-behavior.md template)

| Theme | Test Pattern | Reference |
|--------|--------------|------|
| Y2038 / time_t 64-bit conversion | **Boundary year scan**: Verify date display, storage, retrieval, and round-tripping across all years before and after boundaries, such as 2036–2040 and 2050. Scan a range rather than a single point (discrepancies only become visible around the boundary) | DP-5, DP-6 |
| ILP32→LP64 | **Struct layout comparison**: Compare sizeof/offsetof for structs used in wire/persistence formats between old and new. Verify value consistency for pointer round-trips (store → retrieve) | DP-3, DP-7 |
| RPC/wire protocol | **32-bit serialization round-trip test** equivalent to the old client. Fix the byte sequence of the encoded result | ADR example: xdr_time_t_compat |
| Locale / TZ | Fix output for representative locales/timezones (glibc and the old OS interpret TZ strings differently. `TZ=UTC0UTC` has glibc apply US Eastern DST rules, yielding EST/EDT offsets outside the range of the transition table) | DP-4 |
| Shared libraries | Resolution of soname links (zero "not found" from ldd), presence/absence of duplicate symbol loading | (a lesson learned repeatedly across past migration projects) |
| Daemon startup | Fix observation points in the startup sequence: process survival (timeout rc=124 = alive), RPC registration (rpcinfo), and externally visible state such as X properties. **Explicitly state prerequisite daemons (e.g., rpcbind) and environment variables (LD_LIBRARY_PATH) as test preconditions** | CP-4 |
