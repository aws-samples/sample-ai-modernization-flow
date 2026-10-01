# Repository Inventory

<!-- Created in Phase 0a-1. The ledger used to fix the scope of the analysis.
     Do not rely on the presence of .git alone; also detect build roots (pom.xml / package.json /
     Makefile / CMakeLists.txt / go.mod / *.csproj / requirements.txt etc.).
     Do not dig deep (leave detailed structural analysis to ATX). -->

## Target root

- **Source root:** <PATH_TO_SOURCE_ROOT>
- **Scanned on:** YYYY-MM-DD
- **User confirmation:** pending / done (YYYY-MM-DD)  ← the stop point in Phase 0a-2

## Repositories

<!-- The ID is the identifier used by every downstream artifact. Keep it aligned with the
     analysis output location 00-analysis/<repo-id>/.
     Always write a reason for "out of scope" (never leave an exclusion invisible). -->

| ID | Path | Git-managed | Build system | Presumed role | Rough size | In scope | Reason |
|----|------|-------------|--------------|---------------|------------|----------|--------|
| <repo-id> | <relative path> | yes / no | <maven / npm / make etc.> | frontend / backend / batch / shared / tooling | <files, LOC> | yes / no | <reason when out of scope; blank when in scope> |

## Component layout (only for monorepos)

<!-- Fill this in when one repository contains multiple components.
     ATX can analyse a subdirectory, but **it cannot run in parallel within one git work tree**
     (ATX runs git checkout -b in the work tree). To parallelise, split the work tree with
     git worktree or a clone. -->

| Repository ID | Component | Sub-path | Build system | Analysis unit |
|---------------|-----------|----------|--------------|---------------|
| <repo-id> | <component> | <sub/path> | <maven etc.> | whole repository / individual subdirectory |

## Relationships between repositories (overview)

<!-- Overview only. The detailed contract inventory is done in Phase 0b-2 -->

| Caller | Callee | Kind | Notes |
|--------|--------|------|-------|
| <repo-id> | <repo-id> | REST / event / shared DB / shared file | |

## Excluded from the scan

<!-- Vendor directories, build output, copies of third-party code, etc. -->

| Path | Reason for exclusion |
|------|----------------------|
| | |
