# Compatibility Switches: Index and Usage (.NET Framework → Modern .NET)

The primary-source URLs are consolidated in [runtime-generation-differences.md](runtime-generation-differences.md) §7.

## How to use this document — switches are an index of changes

> **The existence of a compatibility switch is proof that the behavior changed.**

Before reading the changelog, **consult the compatibility switch list** to surface breaking changes
quickly. It is faster to look at "what was made reversible" than to search exhaustively for "what
changed". Switch names function as an **index** into changes.

**The inverse also holds.** A difference for which **no switch exists** has **no way to revert**.
It cannot be absorbed by a compatibility shim, so the only options are to fix the code or change the
success criteria (→ this tends to require an ADR-level decision).

## Switch list

| Switch | Scope | What change it proves | Usage guidance |
|--------|-------|----------------------|---------------|
| `InvariantGlobalization`<br>(`System.Globalization.Invariant` / `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT`) | Runtime | That the implementation of culture-dependent data has become the default. Default: `false` | ⚠️ **Do not enable carelessly.** When enabled, `Compare` / `IndexOf` / `LastIndexOf` behave as **ordinal regardless of comparison options specified**, and sort keys also become ordinal. This is a **third behavior**, neither ICU nor NLS. Time zone ID cross-resolution also breaks (it requires ICU) |
| `System.Globalization.UseNls`<br>(`DOTNET_SYSTEM_GLOBALIZATION_USENLS`) | Runtime | That **ICU became the default** (.NET 5) | **Meaningless on Linux** (Windows only). An escape hatch for Windows-only upgrade projects that need to preserve current sort order. From .NET 9 onward the environment variable takes highest precedence |
| `DOTNET_ICU_VERSION_OVERRIDE` | Runtime | That **ICU version differences can change behavior**. On Linux, the system ICU is loaded by default; if no version is specified, it falls back to the latest | Not for regular use. Record it as a tool for **when reproducibility across ICU versions is needed**. ⚠️ **The environment variable name changed in .NET 10** (formerly `CLR_ICU_VERSION_OVERRIDE`); old procedure docs used verbatim will not work |
| `UseLazyLoadingProxies()` | EF Core | That **lazy loading defaulted to OFF** (EF6 defaulted to ON) | Requires adding the proxy package + `virtual` navigation properties. **Whether to "enable to match current behavior" or "rewrite to explicit `Include`" is an ADR-level decision** |
| `ConfigureWarnings` | EF Core | That **some differences are only warned, not thrown** | **Elevating warnings to exceptions in the development environment is effective** (catches missing `Include` for lazy loading and row-limiting operations without `OrderBy` at runtime). Whether to enable in production is a separate decision |
| `AsSplitQuery()` / `QuerySplittingBehavior` | EF Core | That `Include` expansion was **consolidated into a single query** (EF Core 3.0) | The fallback when the default (single query) produces Cartesian product row-count explosions. **Symptomless at low load, surfaces only under production load** — measure performance characteristics before deciding |
| `UseRelationalNulls(true)` | EF Core | That **EF Core automatically adds correction terms to null comparisons** | ⚠️ **Enabling this applies raw SQL three-valued logic and changes results.** Do not move the default (`false`) |
| Request localization middleware | ASP.NET Core | That **per-request culture determination does not happen by default** | **Use it to fix the default culture explicitly.** Without it, the process default culture (environment-dependent) is used. "Leave it to the container's default" becomes a silent failure when the migration target's environment changes |
| `MvcOptions.SuppressAsyncSuffixInActionNames` | ASP.NET Core MVC | That the `Async` suffix is **automatically stripped from action names** (default `true`) | Setting `false` preserves current URLs, but **deviates from framework convention**. Replacing hard-coded URL strings with `Url.Action` is cleaner (→ perspective MP-6) |
| MSBuild property controlling native library copy | Native-dependent packages | That **there is a known issue where native assets are not copied to the output** | Before relying on a workaround property, **add the presence of native assets in the build output to the expected list in the verification gate** (CP-7). Capture "it exists" mechanically, not just "it worked" |
| CA1307 / CA1309 / CA1310 | Analyzers | That **the implementation of culture-dependent comparison APIs changed** | ⚠️ **Still off by default as of .NET 10.** Opt-in is required (`AnalysisMode=All` + `WarningsAsErrors`). **Without enabling these, "zero warnings" does not mean "no issues"** |

## Discipline when working with switches

1. **Do not make "revert via a compatibility switch" the default solution.** Switches are temporary
   scaffolding to get a migration through; if kept, **write in an ADR why they are kept**. Without
   this, the next maintainer will ask "why are we deviating from the default?"
2. **When a switch is flipped, pin what it changed in the verification gate.**
   Example: if invariant mode is enabled, add assertions for screens that depend on sort order
3. **Switch names and default values change across generations** (real example: the ICU version
   env-var was renamed in .NET 10). **Do not copy old procedure docs.** Verify names and defaults
   in the documentation for the version you adopt
4. **For analyzer-type switches, remember that disabled means warnings do not appear.**
   A count of zero with the detector disabled is indistinguishable from "nothing to detect" (CP-13)

## Primary sources

The source URLs for this document are consolidated in
[runtime-generation-differences.md §7](runtime-generation-differences.md) (with retrieval dates).
**Not duplicated here.**
