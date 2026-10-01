# Analysis Perspectives Appendix — C / Solaris x86 → Amazon Linux

A collection of perspectives specific to this domain, supplementing the Method's common analysis
procedure (analysis-procedure.md).

**The "Perspective Table" below is the source of the adaptation ledger's coverage baseline** (CP-11).
Pick the applicable perspectives in Phase 0b, prepare a detection command and a negative test in
Phase 2, and run the detectors in Phase 3 to obtain the counts.
`install.sh` installs this file as `00-analysis/analysis-appendix.md`.
It also serves as the input to Phase 0b's 0b-1 (cross-cutting environment differences table) and
Phase 1's 1-1 (changelog investigation).

For how to write it see [docs/authoring-playbook.md](../../docs/authoring-playbook.md),
"How to write the perspective table".

## Perspective Table (the source of the coverage baseline)

**Kind**: ② the build succeeds and it breaks only at run time or in production / ③ the build fails but
the straightforward fix breaks something else. ① (the compiler or linker enumerates the places to fix)
is not selected for the coverage baseline — those go under "Analysis Inputs" below.

| ID | Perspective | Kind | Detection command | Reference |
|----|------|------|------------|------|
| MP-1 | **Carrying a feature macro's value over from the migration source as-is misbehaves symptomlessly** (`*_HAVE_*` / `*_USE_*` in `config.h` etc. compile fine, and a wrong value selects a different branch with no error) | ② | Produce the full list with `grep -rnE '^#define[[:space:]]+[A-Z_]*(HAVE\|USE)_' --include='config.h' --include='*.h' .`, then **corroborate each one against man** (do not reuse the copy-source OS's values) | DP-8 |
| MP-2 | **ILP32 → LP64 pointer↔integer casts only produce warnings, so the build passes** (the same applies to the size change of `long` / `time_t`) | ② | Add `-Wpointer-to-int-cast -Wint-to-pointer-cast -Wconversion` to the build and count the warnings (the toolchain warning is the detector) | DP-3, DP-7, reference/longrun_server_migration_considerations.md §3 |
| MP-3 | **Hard-coded assumptions of a 32-bit `time_t` (Y2038)** — an upper bound on the year, or truncation through `xdr_long` during serialization | ② | `grep -rnE '\b(xdr_long\|2038\|0x7[Ff]{7}[Ff])\b' .` | DP-5, DP-6, reference/longrun_server_migration_considerations.md §4 |
| MP-4 | **When a wire format or persisted data contains values derived from `time_t`, `long` or a pointer**, LP64 changes the layout and **old data stops being readable as a silent failure** (subject to HOLD-2) | ② | List the places that `write`/`send` a struct directly: `grep -rnE '(write\|fwrite\|send\|sendto)[[:space:]]*\([^,]*,[[:space:]]*&' .` | reference/ilp32-to-lp64-struct-layout.md |
| MP-5 | **SMF → systemd never appears in the build** (the service definition goes unmigrated while "the build succeeds") | ② | `grep -rlE 'service_bundle\|svcadm\|svccfg\|/lib/svc/' .` (if there are hits but no systemd unit, it is unaddressed) | reference/solaris_linux_differences.md §2.9 |

**"The observation that lets you call it correct" (CP-4) and "the negative test" (CP-13) live in
[verify-snippets.md](verify-snippets.md).** For perspectives whose detection means is a test, see
[baseline-themes.md](baseline-themes.md).

## Analysis Inputs (not selected for the coverage baseline)

Perspectives the compiler or linker enumerates (①), plus material for deciding the target.
Do not open ledger rows for these.

| Perspective | Kind | Content | How to verify |
|------|------|------|---------|
| libc ABI differences | ① | Functions missing when moving from Solaris libc to glibc (strlcpy, getpassphrase, cftime, gethrtime, closefrom, etc.) → whether a compat layer is needed | Link errors produce the accurate list. Whether to build a compat layer is decision material |
| Replacing linked libraries | ① | Drop `-lsocket -lnsl`, add `-ltirpc` (`-I/usr/include/tirpc`), `-pthread` | The linker enumerates them as undefined references. reference/solaris_linux_differences.md §1.10 |
| Compiler differences | ① | Sun Studio → gcc/clang: `-fcommon` (GCC 10+), implicit-function-declaration (GCC 14+) | Each becomes an error on the respective version and later. Do not count in advance |
| Solaris-specific APIs | ① | door/kstat/port_create/gethrtime etc. | **Corroborate against the real code instead of taking an ATX finding at face value** (CP-3): `grep -rnE '\b(door_create\|kstat_open\|port_create\|gethrtime)\b' .`. Multi-platform software depends on OS-specific APIs less than expected |

## Items to Include in the Environment Differences Table (0b-1)

From the perspective table and the analysis inputs above, expand **those that carry concrete migration
source and migration target values** into the "Domain-specific difference perspectives" section of
`01-plan/environment-diff-table.md` (key macro values, which libc functions exist, the data model,
the service-management mechanism).

## Libraries to Prioritize in Changelog Investigation (1-1)

- libtirpc (header path changes, AUTH_DES removal, deprecated APIs: registerrpc/pmap_set)
- OpenSSL 1.x → 3.x (only for the affected products. Many behavioral changes)
- Motif / X11 family (GUI products only. 2.1→2.3 is source compatible)
- PAM (Solaris PAM → Linux-PAM: a difference in how the conversation function's pointer is interpreted)

## Notes During Analysis

- Always **corroborate ATX's Solaris-specific API findings against the real code with grep** (CP-3).
  For the specifics, check your own project's lessons-learned.md
- **Return newly encountered perspectives to the perspective table** (CP-11). Do not let them end as a project record
