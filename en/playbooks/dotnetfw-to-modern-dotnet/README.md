# Playbook: .NET Framework → Modern .NET Migration

A **Playbook (middle layer, practitioner documentation)** for migrating applications running on
.NET Framework (4.x family) — ASP.NET MVC 5 / OWIN / EF6 / IIS-hosted — to modern .NET
(cross-platform, Linux-runnable).

> For the flow (Phase 0-4), three stop points, and user decision items, see `../../method/flow.md`.
> For AI execution discipline, see `../../harness/`. For setup, run `install.sh` at the repository root.

## Domain Characteristics (Differences from Other Playbooks)

- **ATX is used only for analysis (CCA).** Code conversion is performed by direct agent edits, as
  the flow's common policy dictates. ATX work centers on running long analysis jobs, so interruption
  and resumption are handled per DP-2.
- **Existing test assets are often absent.** **Mode B (define by reading the code)** is the primary
  baseline candidate. In that case, **include not only `.cs` but also `.cshtml` and `.config` in the
  coverage baseline** — an omission found and stepped on in practice (`baseline-themes.md`).
- **Silent failure is the primary failure mode.** Replacing a type disables validation attributes;
  a default-value change causes data to go missing as a silent failure — "green build, no exception,
  wrong result" failures dominate. **8 of the 26 perspectives in the table are ③ (the straightforward
  fix breaks something else)**.
- **The source tree may be unbuildable.** On a macOS / Linux host, .NET Framework MSBuild cannot
  run, making it structurally impossible to obtain toolchain warnings from the migration source.
  Plan on having one fewer input to the adaptation ledger
  (`analysis-appendix.md`, "Analysis Inputs").
- **Target versions go stale quickly.** .NET rotates versions every November and LTS support ends
  after three years. Automated analysis and LLM recommendations can easily be one or two generations
  behind the current optimum at the time of work (DP-1).

## Structure

| File | Content | Installed project path |
|------|---------|-----------------------|
| `practices.md` | .NET domain practice collection (`DP-1`–`DP-9`) | `docs/knowledge/practices.md` |
| `analysis-appendix.md` | **Perspective table (`MP-1`–`MP-26`; section F covers the deployment route and configuration injection)**. Source of the adaptation ledger's coverage baseline | `00-analysis/analysis-appendix.md` |
| `baseline-themes.md` | Test patterns for behavior that tends to break (15 themes) | `02-test/baseline-themes.md` |
| `verify-snippets.md` | .NET-specific implementations for each `verify.sh` gate + **negative-test procedures** + forbidden patterns | `02-test/verify-snippets.md` |
| `modernized-gitignore.template` | Ignore rules for build artifacts (`bin/`, `obj/`, etc.) | Root of the records repository (`setup-modernized.sh` reads it and applies it to the modernized tree's `.gitignore`) |
| `transform-config-cca-template.yaml` | AWS Transform custom (ATX) structural analysis (CCA) configuration | `00-analysis/transform-config-cca-template.yaml` (materialized per repository as `00-analysis/<repo-id>/transform-config-cca.yaml` in Phase 0a-4) |
| `reference/runtime-generation-differences.md` | **Primary-source difference catalog** (NLS→ICU / EF6→EF Core / items with no difference) | `docs/reference/` |
| `reference/compat-switches.md` | Compatibility switch list and how to read it | `docs/reference/` |

## Quick Start

```bash
cd /path/to/workspace
/path/to/sample-ai-modernization-flow/install.sh --project <product-version> \
    --playbook dotnetfw-to-modern-dotnet
```

## Key Discussion Points for This Domain

- **Some places cannot use "same as the current behavior" as the success criterion.** `asp-*`
  attributes left in MVC 5 are inert; the migration activates them and **broken functionality
  starts working**. Applying equivalence mechanically makes "reproducing the broken state" the
  correct answer → an ADR to define the expected behavior per site is required (DP-3 / MP-3).
- **Replacing a type makes validation a silent failure across the board.** The boilerplate swap of
  `HttpPostedFileBase` → `IFormFile` causes all custom validation attributes to pass. **Static
  inspection cannot claim "it actually rejects input"** → add a runtime negative test in the same
  Step (DP-6 / MP-2).
- **NLS → ICU is a runtime generation difference, not an OS difference.** "Safe on Windows" is
  wrong: even a project that only upgrades from .NET Framework on Windows will see changes in string
  comparison and sort order (`reference/runtime-generation-differences.md` §2).
- **The most dangerous EF6 → EF Core change is the default-value shift.** Lazy loading is off by
  default, so missing `Include` calls result in **`null` / empty collections with no exception**
  (`reference/` §4-1).
- **Static files return 404 for two distinct reasons.** The `UseStaticFiles` default without a
  `wwwroot` configuration (MP-7) and Linux case-sensitivity (MP-9). **The detector for the latter
  must not query the filesystem** (CP-12).
- **Record items confirmed via primary sources to have no difference.** Time-zone ID incompatibilities
  and `decimal` rounding changes are **conventional wisdom, not facts**. The cost of re-investigating
  "absence" is higher than "presence", so record the verified values (`reference/` §5).

## Information to Include in the Prompt

| Item | Example |
|------|---------|
| Source code path | `/path/to/<product>/` |
| Current stack (example) | .NET Framework 4.8, ASP.NET MVC 5, OWIN self-host, EF6, Autofac + FW integration packages |
| Target stack | **May be left undecided** (decided as an ADR in Phase 0b; do not write it in `transform-config` either) |
| Target OS / execution platform | Example: Amazon Linux (execution platform EC2/ECS/Lambda may be undecided) |
| Build command | `dotnet build <Solution>.sln -c Release` (**also note whether the migration source can be built**) |
| Test execution | Whether existing tests exist. If not, choose baseline Mode B (define by reading the code) |
| Constraints (if any) | Whether the DB schema may be changed / which legacy features may be removed / target architecture (x64 / arm64) |

## Real-world Example (measured on a public sample)

- **ASP.NET MVC 5 + EF6 + OWIN / .NET Framework 4.8 → .NET 10 on Linux container**
  (5 projects: Web / Data / Domain / Common / IaC, approximately 8,400 lines, zero test assets,
  no live production environment, macOS work host). The target is Bob's Used Bookstore, a public
  AWS sample application. The perspective table, practices, and difference catalog in this Playbook
  were extracted from that public sample's measurements (adaptation ledger, ADRs, lessons-learned).
  In practice: of the 41 ledger rows, **about 24 were items the build enumerates**; after the TFM
  switch the unaddressed count fell 41→9, and **all 9 remaining rows were ② or ③
  (the build stays silent / misleads)**.
