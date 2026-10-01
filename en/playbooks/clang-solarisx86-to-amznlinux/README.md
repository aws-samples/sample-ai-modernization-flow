# Playbook: C / Solaris x86 → Amazon Linux (clang/gcc)

A **Playbook (mid-tier, practical documentation layer)** for porting C-language products from
Solaris (SPARC/x86, ILP32) to Amazon Linux (x86_64, LP64). It provides migration-domain-specific
knowledge, perspectives, and implementation examples.

> For the flow (Phase 0-4), the three exit points and items requiring user judgment, see
> `../../method/flow.md`. For AI execution discipline, see `../../harness/`. Setup is performed via
> `install.sh` at the repository root.

## Structure

| File | Content | Copy destination in project |
|---------|------|------------------------|
| `practices.md` | Migration practices collection (DP-N format; added to and grown during work) | `docs/knowledge/practices.md` |
| `analysis-appendix.md` | Domain-specific analysis perspectives (macro value man-page verification, libc ABI, LP64, Y2038, etc.) | `00-analysis/analysis-appendix.md` |
| `baseline-themes.md` | Test patterns for behaviors prone to breakage in this domain (boundary-year scans, struct layout, etc.) | `02-test/baseline-themes.md` |
| `verify-snippets.md` | C/Unix implementation examples for each verify.sh gate (ldd, daemon liveness, valgrind, etc.) | `02-test/verify-snippets.md` |
| `modernized-gitignore.template` | Ignore rules for build artifacts (*.o/*.a/*.so, etc.) | Project root (used by setup-modernized.sh) |
| `transform-config-cca-template.yaml` | Configuration template for ATX structural analysis (CCA) | `00-analysis/transform-config-cca-template.yaml` (instantiated as `00-analysis/<repo-id>/transform-config-cca.yaml` in Phase 0a-4) |
| `reference/solaris_linux_differences.md` | Knowledge of OS differences (also used for ATX import) | `docs/reference/` |
| `reference/longrun_server_migration_considerations.md` | 64-bit conversion, Year 2038 problem, test strategy, etc. | `docs/reference/` |
| `reference/ilp32-to-lp64-struct-layout.md` | Struct layout changes for ILP32→LP64 (DP-7 detail) | `docs/reference/` |

## Quick Start

At the workspace root (the parent directory holding the source tree):

```bash
cd /path/to/workspace
/path/to/sample-ai-modernization-flow/install.sh --project <product-version> \
    --playbook clang-solarisx86-to-amznlinux
```

Then launch the AI agent at the workspace root, give it the path to your source tree and instruct
it to "start the assessment from Phase 0a."
The `<PLACEHOLDER>` values are filled in by the agent during the startup interview (you do not have
to fill them in by hand). The `transform-config` is instantiated per repository in Phase 0a-4.

## Distinctive Issues in This Domain

- **ILP32 → LP64**: pointer↔int casts (conversion to intptr_t), struct layout changes (DP-3, DP-7)
- **Y2038**: hardcoding that assumes a 32-bit time_t, verification by layer at the display layer and range-calculation layer (DP-5, DP-6)
- **RPC wire compatibility**: maintaining compatibility with external 32-bit clients (xdr_time_t_compat pattern)
- **Build systems**: reproducibility of legacy build systems such as imake is ensured at the template layer (avoid editing generated artifacts directly)
- **Runtime environment pitfalls**: beware of "false SEGFAULTs" caused by LD_LIBRARY_PATH and prerequisite daemons (e.g., rpcbind) (CP-8)

For details, see `practices.md` (DP-1 through DP-9) and the `reference/` directory.

## Information to Include in Instructions

| Item | Example |
|------|---|
| Source code path | `/path/to/<product>/` |
| Target environment | Amazon Linux 2023 x86-64 (SSH: `ssh <host>`) |
| Dependent libraries and versions | OpenSSL 3.x, PCRE 8.44, zlib, etc. |
| Source environment information | Solaris x86 32bit, OpenSSL 1.x, Sun Studio, etc. |
| Configure/build commands | `./configure ...` / `make` |
| Constraints (if any) | e.g., "Do not reference past git commits" |

## Past Project Examples

- Desktop environment software (C language, Solaris/SPARC/x86 32bit → Amazon Linux 64bit):
  all 13 Steps completed, verify 37/37 PASS. The DP-N in practices.md are knowledge gained from
  multiple porting cases: DP-1 originates from an nginx-family server case (DP-3 through DP-7 were
  added mainly during this project).
