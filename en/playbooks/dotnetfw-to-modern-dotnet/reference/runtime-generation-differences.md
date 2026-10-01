# .NET Framework → Modern .NET: Runtime Generation Differences

This document is the **rationale** behind sections C (MP-13–MP-15) and D (MP-16–MP-21) of the
Playbook's `analysis-appendix.md` perspective table. The perspective table holds only "what to
suspect" and the detection commands; primary sources and details are separated into this file
(volume discipline for knowledge entries).

## How to read this document (read first)

**Primary-source URLs carry a retrieval date.** Primary sources are revised. If the retrieval date
is old, **re-fetch before using the information as a planning assumption** (CP-3). Dropping the
retrieval date turns the information into unverifiable hearsay.

**Items where no difference was found are also recorded as concrete values** (§5). Showing the
absence of a difference requires exhaustive primary-source coverage, and **the cost of re-verifying
absence is higher than for presence**. If they are not recorded, the next project repeats the same
investigation.

**⚠️ Many differences in this section stem from the "runtime generation", not from "Windows → Linux".**
Framing them as OS differences causes perspectives to be dropped in projects that simply upgrade
.NET Framework to a modern .NET on Windows.

---

## 1. Verdict summary — conventional wisdom vs. reality

Six hypotheses formed before the migration, corroborated against primary sources.
**All six had an error or had become stale.** Items 3, 4, and 5 are non-existent risks, while items 1, 2, and 6 kept their risk direction but rested on wrong reasoning.

| # | Perspective | Conventional wisdom (pre-migration hypothesis) | Actual finding (confirmed from primary source) | Verdict |
|---|-------------|-----------------------------------------------|-----------------------------------------------|---------|
| 1 | Default culture for string comparison | The default shifts toward **ordinal comparison** | **The default does not change** (it was always culture-dependent). What changes is that the **implementation moves from NLS → ICU**, so results change as a silent failure | **CORRECTION** |
| 2 | String sort order | OS difference: **Windows=NLS / Linux=ICU** | On .NET 5+, **target Windows also defaults to ICU**. The real difference is a **runtime-generation gap: .NET Framework (always NLS) → modern .NET (defaults to ICU)** | **CORRECTION** |
| 3 | `DateTime` and time zones | Windows-format IDs cannot be used on Linux and are incompatible | **Wrong for .NET 6+.** Both Windows-format and IANA-format IDs can be resolved. **Code changes are generally not needed** | **CORRECTION** |
| 4 | Decimal rounding and formatting | `decimal` rounding rules and format change | **They do not change.** The .NET Core 3.0 floating-point format change applies only to `Double`/`Single`, not `Decimal`. **However, a separate real risk was discovered** (§3) | **CORRECTION** |
| 5 | EF query translation | Returns different results without raising an exception | **Direction is reversed.** From EF Core 3.0 onward, untranslatable expressions **throw an exception** (it was EF6 / EF Core 2.2 and earlier that silently evaluated on the client). **The primary risk is actually default-value changes** (§4) | **CORRECTION** |
| 6 | Native-dependent image processing | Output bytes change | Linux operation works (static linking). However, **the basis for "bytes change" was wrong** — only SVG renderer differences are documented. **At the same time, no statement guaranteeing byte-identical output exists** (absence of documentation) → direction of conclusion is maintained | **CORRECTION** |

**Lesson (a real-world CP-3 example):** Without corroboration, planning assumptions can
**waste effort on non-existent risks and miss real ones**. Items 3, 4, and 5 above were
non-existent risks; the corroboration process surfaced **real risks not in the original hypotheses**
(the model-binding asymmetry in §3 and the lazy-loading-off-by-default in §4).

---

## 2. Globalization (NLS → ICU)

### 2-1. What changes

.NET Framework implements culture-dependent comparison using Windows **NLS**. Modern .NET uses
**ICU** on all platforms (.NET 5+, including target Windows by default). **Because ICU and NLS have
different logic, the results of culture-dependent comparison APIs can differ between .NET Framework
and modern .NET.**

**The default comparison type does not change. The implementation does.** Confusing these two leads
to counting the wrong things.

| API | Default | Changes across generations? |
|-----|---------|----------------------------|
| `String.Compare` / `CompareTo` | **Culture-dependent** | ✅ **Result can change** (NLS→ICU) |
| `String.IndexOf(string)` / `LastIndexOf(string)` | **Culture-dependent** | ✅ Same |
| `String.StartsWith(string)` / `EndsWith(string)` | **Culture-dependent** | ✅ Same |
| `ToLower` / `ToUpper` / `TextInfo` / `CompareInfo` | Culture-dependent | ✅ Same |
| `ToLowerInvariant` / `ToUpperInvariant` | **Invariant culture** | Does not depend on the current culture (distinguish from the row above) |
| `Array.Sort` (string arrays) / `List<T>.Sort()` (string elements) / `SortedDictionary` / `SortedList` / `SortedSet` (string keys) | Culture-dependent | ✅ **Listed explicitly as "Affected API" in official documentation** |
| `String.Equals` | **Ordinal** | ❌ Does not change |
| `String.Contains` (both `char` and `string`) | **Ordinal** | ❌ Does not change |
| `String.IndexOf(char)` / `StartsWith(char)` / `EndsWith(char)` | **Ordinal** | ❌ Does not change (the default differs from the `string`-argument version — **this inconsistency has existed in both generations**) |

**Concrete example (from official documentation):** ICU's default (`CompareOptions.None`) behaves
like `StringSort`, placing non-alphanumeric characters before alphanumeric ones →
**`"bill's"` sorts before `"bills"`**.

### 2-2. Static analysis is off by default

There are three analyzers that detect omitted `StringComparison`, but **none of them are enabled by
default as of .NET 10** ("Enabled by default in .NET 10: No"). **Opt-in is required.**

| Rule | What it detects |
|------|----------------|
| CA1307 | Detects **all** omitted `StringComparison` (regardless of default; high noise) |
| CA1309 | Recommends ordinal `StringComparison` |
| CA1310 | **Only** methods where the default is culture-dependent comparison (dedicated rule; low noise) |

The official documentation recommends enabling with `AnalysisMode=All` + adding the three rules to
`WarningsAsErrors`. **For migration projects, using CA1310 as primary and CA1307 as supplementary
is practical** (CA1310 targets exactly the APIs with culture-dependent defaults, matching MP-13).

### 2-3. Security implications

With the default (culture-dependent) comparison in `string.IndexOf(string)`, **`IndexOf` may return
`-1` (not found) even for strings containing literal `'<'` or `'&'`**. Code that implements
sanitization or filtering via `IndexOf` can break toward **allowing input through** after migration.

---

## 3. Model-binding culture asymmetry (ASP.NET Core)

**ASP.NET Core treats culture differently for route data / query strings vs. form data.**
This is an intentional spec change from MVC5 — a **deliberate asymmetry** by design (to allow URLs
to be shared across locales).

| Source | Culture handling |
|--------|----------------|
| Route value provider / query string value provider | Always interpreted as **invariant culture** |
| Form data | Undergoes **culture-dependent conversion** |

**Risk pattern:** Where monetary amounts or quantities are passed via query string, **off-by-one
accounting errors occur without raising an exception**. Values sent via form and values sent via
query are interpreted differently.

**Furthermore, the default culture resolution becomes environment-dependent.** Without explicitly
composing the localization middleware, per-request culture switching does not happen, and the
**process default culture** (invariant culture, or the OS / container default) is used. If no
provider can determine a culture, `DefaultRequestCulture` is used.

**Remedy:** Configure request localization explicitly to **fix the default culture**.
"Leave it to the container's default" becomes a silent failure when the migration target's
environment changes.

---

## 4. EF6 → EF Core

**The danger lies in default-value changes, not in "change in client-evaluation semantics".**

### 4-1. Lazy-loading default (most important)

| | EF6 | EF Core |
|---|---|---|
| Lazy loading | **Default `true`** (`DbContextConfiguration.LazyLoadingEnabled`) | **Disabled by default (opt-in)** |
| How to enable | — | Add the proxy package + explicitly call `UseLazyLoadingProxies()` + mark navigation properties `virtual` |

**Risk pattern:** A missing `Include` during migration causes **no N+1, no exception — just `null`
or an empty collection** (silent data loss). The page renders with HTTP 200, so **HTTP status and
page-render assertions pass** → **value-level assertions are needed**.

**Development aid:** Enable the setting that elevates warnings to exceptions
(`ConfigureWarnings`) in the development environment.

### 4-2. Client evaluation (direction is reversed)

From EF Core 3.0 onward, an untranslatable expression anywhere other than the **final top-level
projection (the last `Select()`)** causes a **runtime exception**. Before 3.0, client evaluation
was supported anywhere in a query.

**Therefore, the migration symptom is not "silently returns different results" but "a query that
worked in EF6 throws an exception".** This is detectable by regression tests (not a silent failure).
**Static detection during migration is difficult**; it is not known until the query is executed.

Note: `String.Equals(String, StringComparison)` has **no equivalent database function and cannot
be translated**, does not fall back to client evaluation, and becomes an exception.

### 4-3. Row-limiting operations without `OrderBy` (warning only)

Using `First` / `FirstOrDefault` / `Single` / `Skip` / `Take` without `OrderBy` (and without
filtering) causes EF Core to **emit only a warning, not an exception**. Execution continues, and
**the returned rows can vary depending on the DB query plan**.

| Warning event | Status |
|---------------|--------|
| `CoreEventId.FirstWithoutOrderByAndFilterWarning` | **Marked Obsolete** |
| `CoreEventId.RowLimitingOperationWithoutOrderByWarning` | Current as of efcore-9.0 |

⚠️ **Warning event ID names have been reorganized across generations.** When designing a system
that monitors warnings in logs, **verify that the warning actually fires in the version you adopt**
(CP-4) before using it as a test assumption.

**Nature of the symptom:** **Different rows are returned without an exception**, depending on the
SQL execution plan or index changes. **Results can be non-reproducible**, so pinning paging
boundary tests is the reliable approach.

### 4-4. `Include` expansion mode

From EF Core 3.0 onward, multiple `Include` calls (collection navigations) are by default
consolidated into a **single SQL statement (JOIN)**. EF6 could generate multiple SQL statements.

**The result set is logically identical, but Cartesian product explosions can cause client-side
row counts to blow up.** There is a way to revert to split queries (`AsSplitQuery()`).
**Symptomless at low load, but manifests in production under real load**.

### 4-5. `GroupBy`

From EF Core 7.0 onward, `GroupBy` **without aggregation** that cannot be translated to a SQL
`GROUP BY` **reconstructs the grouping on the client side after retrieving results (no exception)**.
`GroupBy` with aggregation (e.g., `Count()`) is translated to SQL `GROUP BY`.

**The content of the results is the same, but the row-retrieval count and performance
characteristics change.** Check whether this applies to large tables.

### 4-6. Three-valued logic for null comparisons

EF Core **automatically adds correction terms** (e.g., `OR [col] IS NULL`) for `!=` comparisons to
match C# equality semantics. Disabling this with `UseRelationalNulls(true)` causes the
**raw SQL three-valued logic** to apply, changing results.

**Unless the default is changed, results before and after migration should be the same**, but
primary documentation corroborating EF6's corresponding behavior has not been obtained
(see §7 for limitations).

### 4-7. Who applies the schema (EF6 initializers have no equivalent)

| | EF6 | EF Core |
|---|-----|---------|
| Who applies it | **The framework.** `Database.SetInitializer` fires **on the first DB access** (not at startup) | **Somebody calls it explicitly**: `Migrate()` / `MigrateAsync()` / `dotnet ef database update` |
| Provider dependence | None (same for SQL Server and LocalDB) | None (but **the branch that calls it easily becomes environment-dependent**) |
| When it is not applied | — | **The app starts, the health check passes, and only DB-backed screens return HTTP 500** |

- **`EnsureCreated()` and `Migrate()` cannot be combined.** `EnsureCreated()` does not create
  `__EFMigrationsHistory`, so **you cannot switch to `Migrate()` later** (an existing schema cannot be
  brought under migration management).
- Measured symptom: starting the app against a DB with no tables makes **Kestrel startup, the health check,
  and the auth pages all succeed, while only DB-backed screens return HTTP 500**.
  **"It starts" is not evidence of an application route** (→ MP-24).
- **Primary-source status**: this section was confirmed **from the real code and runtime results**, not from
  migration-guide text. It has no corresponding URL in the §7 list.

---

## 5. Items confirmed from primary sources to have no difference

**This section has the highest reuse value in this document.** These are items cited as conventional
wisdom that turn out to have no actual difference.

### 5-1. Time zone IDs (code changes generally not needed)

| Claim | Reality |
|-------|---------|
| "Windows-format IDs (`Tokyo Standard Time`) cannot be used on Linux" | **Wrong for .NET 6+.** `TimeZoneInfo.FindSystemTimeZoneById` can resolve **either** Windows-format IDs or IANA-format IDs |

**Mechanism:** When direct ID resolution fails, it falls back to **alternative ID resolution** based
on ICU's CLDR `windowsZones` mapping and, if successful, creates and caches an equivalent
`TimeZoneInfo`. On Windows, .NET 6+ also supports IANA-format IDs.

**What stays the same:** If an ID is not found, an **exception** (`TimeZoneNotFoundException`) is
thrown. "Silently returns a different value" is not documented behavior.

**Precondition:** **ICU must be available.** The conversion APIs (`TryConvertWindowsIdToIanaId`,
etc.) are **only supported when ICU is used** → they fail in invariant mode or NLS mode.
**Therefore, enabling the "disable ICU" setting (see `compat-switches.md`) invalidates the
conclusion of this section.**

**Accompanying change:** From .NET 8 onward, `FindSystemTimeZoneById` **returns a cached instance**
(does not create a new object). This is not a breaking change to the ID-resolution logic itself,
but code that relies on reference equality is affected.

### 5-2. `decimal` rounding and formatting (no change)

| Claim | Reality |
|-------|---------|
| "`decimal` rounding rules change" | **They do not change.** The default for `Math.Round` / `Decimal.Round` is `MidpointRounding.ToEven` in both generations. No version-change entries exist |
| "The .NET Core 3.0 floating-point format change affects monetary calculations" | **`Decimal` is not affected.** The affected APIs are only `Double.ToString` / `Single.ToString` / `Double.Parse` / `Double.TryParse` / `Single.Parse` / `Single.TryParse` |
| "Currency symbol and decimal separator formats change across generations" | **The "Behavioral differences" list for globalization does not enumerate currency or decimal separator format changes.** The fact that `Decimal.ToString()` uses the current culture's default format is unchanged from the MVC5 era |

⚠️ **However, "the format does not change" and "the display does not change" are different things.**
**The culture itself changes** (Windows system locale → container invariant culture), so the output
of `ToString("C")` changes. The cause is **a change in the default culture**, not a change in the
format rules (→ perspective MP-12; remedy is explicit fixation via request localization).

**Missing this distinction leads to concluding "no difference" after investigating rounding rules,
while missing the breakdown of currency display.**

---

## 6. Native-dependent libraries (image processing as an example)

### 6-1. A generalizable way to read the situation

| Aspect | How to read it |
|--------|---------------|
| Bundled target RIDs | Confirm **which RIDs the package bundles native binaries for**. Having `linux-x64` but not `linux-musl-arm64` is common (→ **Alpine base images and architecture selection cannot be decided simultaneously**) |
| Static vs. dynamic linking | A statically linked build does not need the library installed on the OS side. "Install the library in the container" can be **unnecessary or even wrong** |
| Accompanying libraries | Even with static linking, **fonts and character-encoding libraries may need to be installed on the OS side**. If you're not using the relevant features, they're not needed → **confirm actual feature usage first** |
| Target notation | ⚠️ **If the NuGet target notation is "computed" (compatibility inference) only, the package does not explicitly target that TFM.** There is no official compatibility statement, so **testing on real hardware is required** (CP-4) |
| Output reproducibility | **If no statement guarantees "same input → same byte sequence", treat it as having no guarantee.** Not explicitly stating "not guaranteed" must not be read as "guaranteed" |
| Cross-architecture differences | Check whether the upstream (native library) has **known reports of differing output between aarch64 and x86_64** |

### 6-2. Concrete measured example (`Magick.NET-Q8-AnyCPU`, retrieved 2026-09-03)

- **Linux native binaries are statically linked** and bundled → designed to work without additional
  installation on standard glibc-based distributions. **No need to install ImageMagick in the
  container** (stated explicitly by the maintainer in an Issue)
- **AnyCPU coverage:** windows(x64/arm64/x86) / **linux(x64/arm64)** / **linux-musl(x64 only)** /
  macOS(x64/arm64). **arm64 is not available for musl**
- **Fonts:** On Linux / macOS, `fontconfig` must be installed on the OS side (running `fc-cache` may
  also be needed). → **Not needed if you are not using text-rendering APIs**. Confirm actual usage
  first
- **OpenMP is not included in the AnyCPU package** (C++ redistributables are statically linked and
  OpenMP cannot be statically linked). OpenMP support is in a separate package
- **Some formats and features may be absent from the Linux build** due to incompatible licenses etc.
- **SVG-to-bitmap conversion uses different renderers on different platforms** (Windows: librsvg /
  Linux and macOS: ImageMagick built-in) → **a known difference in output across platforms**
  (acknowledged by the maintainer)
- **NuGet targets are `net8.0` and `netstandard2.0`.** Newer TFMs show "computed" compatibility only
  → **real-hardware verification is required**
- **No guarantee or denial of byte-identical output exists in primary sources** (absence of
  documentation confirmed) → **do not use byte-identical comparison**
- There are known upstream ImageMagick reports of **differing output between aarch64 and x86_64**
  (text-rendering cases; not generalizable to simple resize, but establishes the possibility exists).
  Non-determinism in resize output is flagged as an **OpenCL issue**

**Implication for test design:** Design **perceptual-difference verification** rather than
byte-identical comparison (→ `baseline-themes.md`).

---

## 7. Primary sources (URL + retrieval date)

**All retrieved 2026-09-03.** Re-fetch before using as a planning assumption, as they may have been
revised.

### Globalization / strings

| Content | URL |
|---------|-----|
| Best practices for string comparison (defaults for each API) | https://learn.microsoft.com/en-us/dotnet/standard/base-types/best-practices-strings |
| Differences between .NET and .NET Framework (enumeration of affected APIs) | https://learn.microsoft.com/en-us/dotnet/standard/base-types/string-comparison-net-5-plus#differences-between-net-and-net-framework |
| ICU globalization (target OS / sort order differences / specifying ICU version on Linux) | https://learn.microsoft.com/en-us/dotnet/standard/globalization-localization/globalization-icu |
| Breaking changes catalog for ICU default (includes `Array.Sort` etc. in Affected APIs) | https://learn.microsoft.com/en-us/dotnet/core/compatibility/globalization/5.0/icu-globalization-api |
| Globalization runtime settings (`UseNls` / `Invariant`) | https://learn.microsoft.com/en-us/dotnet/core/runtime-config/globalization |
| Invariant mode spec (always ordinal) | https://github.com/dotnet/runtime/blob/main/docs/design/features/globalization-invariant-mode.md |
| CA1307 / CA1309 / CA1310 (off by default) | https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1307 · https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1309 · https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1310 |
| .NET 10 breaking changes list (Globalization: only env-var rename) | https://learn.microsoft.com/en-us/dotnet/core/compatibility/10.0 |

### ASP.NET Core

| Content | URL |
|---------|-----|
| Globalization behavior of model binding (route/query: invariant; form: culture-dependent) | https://learn.microsoft.com/en-us/aspnet/core/mvc/models/model-binding#globalization-behavior-of-model-binding-route-data-and-query-strings |
| Request culture determination (default when middleware is not configured) | https://learn.microsoft.com/en-us/aspnet/core/fundamentals/localization/select-language-culture |

### EF6 → EF Core

| Content | URL |
|---------|-----|
| EF6 → EF Core migration guide | https://learn.microsoft.com/en-us/ef/efcore-and-ef6/porting/ |
| Behavioral differences between EF6 and EF Core | https://learn.microsoft.com/en-us/ef/efcore-and-ef6/porting/port-behavior |
| Detailed migration cases | https://learn.microsoft.com/en-us/ef/efcore-and-ef6/porting/port-detailed-cases |
| EF Core 3.x new features (LINQ overhaul / client evaluation restriction) | https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-3.0/ |
| EF Core 3.x breaking changes (including single-query consolidation) | https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-3.0/breaking-changes |
| Client evaluation vs. server evaluation | https://learn.microsoft.com/en-us/ef/core/querying/client-eval |
| Lazy loading (EF Core, opt-in) | https://learn.microsoft.com/en-us/ef/core/querying/related-data/lazy |
| `LazyLoadingEnabled` (EF6, default true) | https://learn.microsoft.com/en-us/dotnet/api/system.data.entity.infrastructure.dbcontextconfiguration.lazyloadingenabled?view=entity-framework-6.2.0 |
| Null comparison semantics | https://learn.microsoft.com/en-us/ef/core/querying/null-comparisons |
| Complex query operators (`GroupBy` translation rules) | https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators |
| Database functions (`string.Equals(StringComparison)` cannot be translated) | https://learn.microsoft.com/en-us/ef/core/querying/database-functions |
| Transactions (`SaveChanges` default) | https://learn.microsoft.com/en-us/ef/core/saving/transactions |
| `FirstWithoutOrderByAndFilterWarning` (Obsolete) | https://learn.microsoft.com/en-us/dotnet/api/microsoft.entityframeworkcore.diagnostics.coreeventid.firstwithoutorderbyandfilterwarning?view=efcore-8.0 |
| `RowLimitingOperationWithoutOrderByWarning` (current) | https://learn.microsoft.com/en-us/dotnet/api/microsoft.entityframeworkcore.diagnostics.coreeventid.rowlimitingoperationwithoutorderbywarning?view=efcore-9.0 |

### Time zones / numerics

| Content | URL |
|---------|-----|
| `FindSystemTimeZoneById` (IANA support in .NET 6+, exception behavior) | https://learn.microsoft.com/en-us/dotnet/api/system.timezoneinfo.findsystemtimezonebyid |
| `TryConvertWindowsIdToIanaId` / `TryConvertIanaIdToWindowsId` (requires ICU) | https://learn.microsoft.com/en-us/dotnet/api/system.timezoneinfo.tryconvertwindowsidtoianaid · https://learn.microsoft.com/en-us/dotnet/api/system.timezoneinfo.tryconvertianaidtowindowsid |
| Alternative ID resolution implementation (`TryGetTimeZone` / `GetAlternativeId`) | https://raw.githubusercontent.com/dotnet/runtime/main/src/libraries/System.Private.CoreLib/src/System/TimeZoneInfo.cs |
| How to instantiate `TimeZoneInfo` | https://learn.microsoft.com/en-us/dotnet/standard/datetime/instantiate-time-zone-info |
| .NET 8: `FindSystemTimeZoneById` returns cached instances | https://learn.microsoft.com/en-us/dotnet/core/compatibility/core-libraries/8.0/timezoneinfo-object |
| .NET Core 3.0 floating-point format change (`Double`/`Single` only) | https://learn.microsoft.com/en-us/dotnet/core/compatibility/3.0#core-net-libraries |
| `Math.Round` default | https://learn.microsoft.com/en-us/dotnet/api/system.math.round |
| `Decimal.Round` default | https://learn.microsoft.com/en-us/dotnet/api/system.decimal.round |
| `Decimal.ToString()` culture dependency | https://learn.microsoft.com/en-us/dotnet/api/system.decimal.tostring |

### Native dependencies (image processing example)

| Content | URL |
|---------|-----|
| Bundled RID list / no OpenMP | https://github.com/dlemstra/Magick.NET |
| Cross-platform (static linking / `fontconfig` / unsupported formats) | https://github.com/dlemstra/Magick.NET/blob/main/docs/CrossPlatform.md |
| NuGet target TFMs (how to identify "computed" compatibility) | https://www.nuget.org/packages/Magick.NET-Q8-AnyCPU |
| SVG renderer difference (Windows: librsvg / Linux: built-in) | https://github.com/dlemstra/Magick.NET/issues/493 |
| No need to install the library in the container | https://github.com/dlemstra/Magick.NET/issues/464 |
| Known reports of differing output between aarch64 and x86_64 | https://github.com/ImageMagick/ImageMagick/issues/6151 |
| Non-determinism in resize output (OpenCL) | https://github.com/ImageMagick/ImageMagick/discussions/3047 |

---

## 8. Limitations of this document (known open items)

**This section exists so that what is not written is not read as "does not exist".**

- **Primary source coverage for EF6 is incomplete for some items.** Migration-target (EF Core)
  behavior was confirmed with high confidence, but official documentation corroborating the
  corresponding migration-source (EF6) behavior was not obtained for: the ordering guarantee (or
  lack thereof) for `First`/`Single`/`Skip`/`Take` / `GroupBy` translation rules / null-comparison
  three-valued-logic correction / canonical function mapping for `string.Compare` / default
  transaction for `SaveChanges`. **Statements of "this is how EF6 behaved" contain inference from
  EF Core documentation**
- **Warning event IDs for `First`-family usage without `OrderBy` have been reorganized across
  generations.** Whether the warning actually fires in the version you adopt has not been verified.
  **Verify by observation before using as an assumption** (CP-4)
- **Breaking changes in EF Core versions 4–9 have not been individually and exhaustively checked.**
  The core focus (EF Core 3.0's client-evaluation change) and the latest delta were covered in depth.
  **The possibility of other "silently changed results" in between cannot be ruled out**
- **Change tracking is outside the scope of this document.** Differences in graph-tracking behavior
  on `Attach`/`Add` (entity state transitions for entities with generated keys) are a change-tracking
  problem, not a query problem, and require separate investigation
- **No primary source was found that directly states "ICU is irrelevant as long as DB-side sorting
  is used in EF Core".** The general principle (server-side evaluation preferred; untranslatable
  causes exception) is confirmed, but **identifying in-memory sort locations depends on measured
  observation during implementation** (→ perspective MP-14)
- **The official .NET 10 breaking changes list carries a caveat that it is "work in progress".**
  It is not a complete list
