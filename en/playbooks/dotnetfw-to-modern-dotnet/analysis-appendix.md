# Analysis Perspective Appendix — .NET Framework → Modern .NET Migration

Domain-specific perspective collection supplementing the common analysis procedure (`analysis-procedure.md`).

**The "Perspective Table" below is the source of the adaptation ledger's coverage baseline** (CP-11). Select the applicable perspectives in Phase 0b, prepare detection commands and negative tests in Phase 2, and run the detectors in Phase 3 to obtain counts.
`install.sh` places this file at `00-analysis/analysis-appendix.md`.
It also serves as input for step 0b-1 (environment diff table) in Phase 0b and step 1-1 (changelog investigation) in Phase 1.

See [docs/authoring-playbook.md](../../docs/authoring-playbook.md), "How to write the perspective table", for authoring guidelines.

**Replace `$SRC` in detection commands with the root of the migration source tree.** In an actual migration, set up the scan target via an environment variable so the same commands can be redirected to the modernized tree in Phase 4.

---

## Perspective Table (source of the coverage baseline)

**Kind**: ② the build succeeds but it breaks only at run time or in production / ③ the build fails but **the straightforward fix breaks something else**.
① (where the build fails and enumerates the places to fix) is not drawn into the coverage baseline — those live under "Analysis Inputs" below.

### A. System.Web / ASP.NET MVC 5 → ASP.NET Core

| ID | Perspective | Kind | Detection command | Reference |
|----|-------------|------|-------------------|-----------|
| MP-1 | **"Authentication required by default" depends on a single global filter line.** When the registration code uses an old-framework-only type, **deleting the entire file makes the build green** — and what disappears is authorization, a cross-cutting concern. An authorization gap stays hidden because the app still "works", making it the most likely silent failure. **The gap also runs the other way**: adding `[AllowAnonymous]` to the login controller stops the 401 from happening, which removes the login route the old OWIN stack provided as a side effect of authorization (→ DP-9). | ③ | `grep -rn 'filters\.Add\|GlobalFilters\|RegisterGlobalFilters' --include='*.cs' $SRC` for the global auth registration. Review `AllowAnonymous` as **a diff of the file set, not a count** (the count can match while the contents are swapped; measured: taking "the same number of exception classes" as the basis let one slip through): `comm -13 <(grep -rl AllowAnonymous $SRC \| sed "s\|$SRC/\|\|" \| sort) <(grep -rl AllowAnonymous $MODERNIZED \| sed "s\|$MODERNIZED/\|\|" \| sort)`. **If anything auth- or login-related appears in the diff, require that `Challenge()` / `SignInAsync()` actually exist.** | **DP-9**, `verify-snippets.md` §nonfunc |
| MP-2 | **Custom validation attributes that assume `HttpPostedFileBase` are silently invalidated the moment the type is changed to `IFormFile`.** The guard `if (!(value is HttpPostedFileBase f)) return base.IsValid(value);` falls through to `base.IsValid(object)`, whose default implementation **returns `true`** — the file-size limit and the extension allowlist both disappear at once, as a silent failure. | ③ | `grep -rn 'is HttpPostedFileBase\|as HttpPostedFileBase' --include='*.cs' $SRC` — then enumerate all `ValidationAttribute` subclasses and visually inspect every type guard inside `IsValid`: `grep -rln ': ValidationAttribute' --include='*.cs' $SRC` | **DP-6**, `verify-snippets.md` §negative-test |
| MP-3 | **`asp-*` attributes left in MVC 5 views are inert (plain HTML attributes); migration activates them, which brings back functionality that was previously broken.** Setting "same as current" as the success criterion makes **reproducing the broken state the correct answer** → define the expected behavior per site (restore / leave broken / maintain as-is / no effect). `_ViewImports.cshtml` applies **only to its own folder and subfolders** (Area subdirectories each need their own). **This is not limited to `asp-*`** — if MVC 5 never called `MapMvcAttributeRoutes()`, `[Route]` is inert as well and gets activated after the migration, changing the routes. Sweep for **declarative mechanisms that were inert in the source** in general. | ③ | `grep -rho 'asp-[a-zA-Z-]*=' --include='*.cshtml' $SRC \| sort \| uniq -c` to enumerate all tokens by category, then cross-check with `find $SRC -name '_ViewImports.cshtml'` to verify **which directories contain one** (check each Area). For attribute routing, take `grep -rn '\[Route(' --include='*.cs' $SRC` and `grep -rn 'MapMvcAttributeRoutes' $SRC`: **if the latter returns 0, all of the former are inert.** <br>⚠️ **Writing `[a-z-]` misses camelCase route parameters such as `asp-route-returnUrl`** (measured: produced 1 false negative; `[a-zA-Z-]` is correct). | **DP-3**, ADR-equivalent judgment required |
| MP-4 | **Tag Helper activation makes previously unreachable code paths reachable.** `if (!ModelState.IsValid) return View();` (no argument) re-renders without passing the model. While the helpers were inert the attributes were never evaluated, so it was harmless — **after activation `Model` is null and throws `NullReferenceException`**. A happy-path E2E cannot reach this by design. **In views that carry reference data, the same path drops `SelectList` and friends** (no exception — the dropdown is simply **empty**). | ③ | Take `grep -rn 'return View();' --include='*.cs' $SRC` and cross-check whether each action's re-render target view references `Model.` anywhere: `grep -rn 'Model\.' --include='*.cshtml' $SRC`. At the same time, check whether the code that builds `ViewBag`/`SelectList` re-runs before the re-render. | Review alongside MP-3 |
| MP-5 | **Some `<form>` elements have no `action`, relying on "POST to the current URL" to recover from missing hidden fields.** Adding `asp-action` helpfully breaks them because route values are dropped (**typical case of a well-meaning clean-up causing a break**). The ASP.NET Core form tag helper generates the action from the current route values, so it appears to work — until you specify one explicitly and lose the values. | ③ | `grep -rn '<form' --include='*.cshtml' $SRC \| grep -v 'action='` to list forms with no action; cross-check with `asp-for`-decorated hidden inputs that carry no `name=` (and therefore are not POSTed): `grep -rn 'type="hidden".*asp-for' --include='*.cshtml' $SRC` | MP-3 category C-3 (maintain as-is) |
| MP-6 | **`MvcOptions.SuppressAsyncSuffixInActionNames` defaults to `true`, so the `Async` suffix is automatically stripped from action names in route names.** Hard-coded URL strings become 404 — but **list pages render normally while only the buttons die**, so it is not caught by smoke tests. Unlike `Url.Action`, these are not detected at compile time. | ② | Cross-check `grep -rnE '(formaction\|href\|action)=.*[A-Za-z]Async[/}"]' --include='*.cshtml' $SRC` against `grep -rnE 'public async Task<[A-Za-z]+> [A-Za-z]+Async\(' --include='*.cs' $SRC`. <br>⚠️ **Writing `="[^"]*Async` returns 0 results** (measured). URLs appear as `formaction="@($"/Admin/.../ApproveAsync/{id}")"` — the Razor interpolation contains a `"` inside, causing `[^"]*` to stop at the opening quote of the interpolation. | — |
| MP-7 | **On a legacy setup that does not use `wwwroot`, `UseStaticFiles()` with its default settings returns 404 for every static file.** The default looks inside `wwwroot/`, so moving an MVC 5 layout that stores assets in `Content/` and `Scripts/` verbatim **makes the build green while every image and stylesheet disappears**. | ② | `test -d $SRC/wwwroot \|\| grep -rn 'UseStaticFiles()' --include='*.cs' $SRC` (match = no `wwwroot` and the call has no arguments; a `PhysicalFileProvider(ContentRootPath)` must be supplied). | **DP-8** |
| MP-8 | **Middleware implemented as `IMiddleware` requires DI registration.** Convention-based middleware (a plain class with an `Invoke` method) needs none, but an `IMiddleware` implementation that lacks `AddTransient<T>()` throws on the first request after startup (the exception type depends on the DI container: `InvalidOperationException` with Microsoft.Extensions.DependencyInjection, `ComponentNotRegisteredException` with Autofac). | ② | **The scan target is the modernized tree** (the migration source has no `IMiddleware`, so 0 results there is expected — **do not read 0 results against the source as "not applicable"**). Cross-check each type from `grep -rln ': IMiddleware' --include='*.cs' $MODERNIZED` against occurrences of `AddTransient\|AddScoped\|AddSingleton`. | **DP-7** |
| MP-26 | **One-off static files that `.csproj` included implicitly through `Content Include` / `None Include` (e.g. `favicon.ico`) disappear silently from the modernized tree.** Moving assets directory by directory never picks them up, and there is no build error and no runtime exception. | ② | Enumerate every static-file reference in the source csproj and cross-check against the real files under the serving root (`wwwroot`, or the `FileProvider` root): `grep -rhoE '<(Content\|None) Include="[^"]*\.(ico\|png\|jpg\|gif\|svg\|css\|js\|txt\|xml)"' --include='*.csproj' $SRC`. Check the file side with `git ls-files` (same reason as MP-9: do not query the FS). | MP-7, MP-9 |

### B. Windows → Linux (OS differences)

| ID | Perspective | Kind | Detection command | Reference |
|----|-------------|------|-------------------|-----------|
| MP-9 | **Case mismatch in static-asset reference paths.** Windows is case-insensitive, so the mismatch is invisible until **Linux returns 404 the first time**. No exception, no error — just "image missing". An `onerror` fallback URL that also has a case mismatch returns 404 too, and the fallback image never appears. API-name grep cannot catch this in principle. | ② | **Strict string comparison between reference paths and real file names.** ⚠️ **Do not use `test -e` for existence checks** — the work host's filesystem (macOS) is also case-insensitive, so the detector itself is affected by the same problem and produces false negatives (CP-12). Compare with `git ls-files` output using `grep -F -x`: <br>`grep -rhoE '/(Content\|images\|Images\|Scripts\|css\|lib)/[A-Za-z0-9_./-]+\.(jpg\|png\|gif\|svg\|css\|js\|ico)' --include='*.cshtml' $SRC` then check each reference strictly against `git ls-files`. | ADR-equivalent (fix the reference side or the file-name side), CP-12 |
| MP-10 | **Physical write path and returned URL are managed separately.** A pattern like saving to `Path.Combine(root, "images", ...)` while returning `/Content/images/...` means **save succeeds with no exception, but display returns 404**. When the storage implementation has a mode switch (local / S3), **the mismatch may only appear in one of the modes**. | ② | `grep -rn 'Path\.Combine' --include='*.cs' $SRC` to enumerate physical paths built up; cross-check one by one with the URL strings returned by the same class. Verify actual directory names via `git ls-files` (same reason as MP-9: do not query the FS). | MP-9 |
| MP-11 | **Windows path separators and `.\` prefixes remain in code, IaC, and deploy scripts.** Fixing the application itself while overlooking the IaC side causes failures at container startup or build time. | ② | `grep -rnE '\\\\\|"\.\\\\\|\.\\\\' --include='*.cs' --include='*.ps1' --include='*.json' $SRC` (remember to include IaC directories in the scan target). | — |
| MP-12 | **Currency, number, and date formats are resolved under the Invariant culture, and the currency symbol becomes `¤`.** The `<globalization>` equivalent from `Web.config` does not exist in the migration target, and **without explicitly configuring request localization** the formatting changes. No exception is thrown. | ② | `grep -rnE 'ToString\("[CcNnDdFfPp]' --include='*.cs' --include='*.cshtml' $SRC` and `grep -rn '<globalization' $SRC` (if the latter returns 0, the source also relies on defaults → explicit configuration is required). | `reference/runtime-generation-differences.md` §5-2, §3 |

### C. Runtime-generation differences (NLS → ICU / .NET Framework → Modern .NET)

**The differences in this section come from a runtime-generation change, not an OS difference.**
.NET Framework always uses Windows NLS; Modern .NET defaults to ICU on all platforms.
Mis-categorizing this as "Windows vs. Linux" causes you to miss these perspectives on a project that only upgrades to .NET 10 on Windows.

| ID | Perspective | Kind | Detection command | Reference |
|----|-------------|------|-------------------|-----------|
| MP-13 | **The culture-sensitive comparison implementation switches from NLS to ICU, so "same culture-sensitive comparison, different result".** What changes is **the culture-sensitive comparison implementation**, not the default comparison kind. Affected APIs: `String.Compare` / `CompareTo` / `IndexOf(string)` / `LastIndexOf(string)` / `StartsWith(string)` / `EndsWith(string)` / `ToLower` / `ToUpper` / `TextInfo` / `CompareInfo` / `Array.Sort`. **`Equals` and `Contains` were already ordinal and do not change** (mis-listing them inflates the scope). | ② | First **enable the static analyzers as an opt-in** (CA1307 / CA1309 / CA1310 are **not enabled by default even in .NET 10**). Add `AnalysisMode=All` plus the three rules as `WarningsAsErrors` in `.editorconfig` or `.csproj` to get a machine-generated list. Supplement: `grep -rnE '\.(Compare\|CompareTo\|IndexOf\|LastIndexOf\|StartsWith\|EndsWith)\("' --include='*.cs' $SRC \| grep -v StringComparison` | `reference/runtime-generation-differences.md` §2, `reference/compat-switches.md` |
| MP-14 | **In-memory sort order changes with ICU, causing record duplication or gaps at paging boundaries.** Sites where server-side `ORDER BY` applies (DB collation applies) differ from sites where sorting happens after `ToList()`/`AsEnumerable()` (ICU applies) — **the impact differs, so count them separately**. | ② | `grep -rnE '\.(ToList\|AsEnumerable)\(\)' --include='*.cs' $SRC` and filter for those followed by `OrderBy`. Also record the DB collation (confirm it has not changed across the migration). | MP-19, `reference/runtime-generation-differences.md` §2-1, `baseline-themes.md` |
| MP-15 | **The output bytes of native-dependent libraries are officially unspecified.** No primary source explicitly states "byte-for-byte identical output under the same input and settings" (and the absence of a guarantee statement does not mean a guarantee exists). Tests that rely on byte-identical comparison may fail after migration. Also **verify per package that native binaries for the target architecture (arm64 / x64) are bundled**. | ② | `grep -rn 'PackageReference' --include='*.csproj' $SRC` to enumerate packages with native dependencies, then verify that each package's `runtimes/` directory includes the target RID (e.g. `linux-arm64`): `find ~/.nuget/packages/<pkg> -type d -name 'linux-*'` | `reference/runtime-generation-differences.md` §6 (verify with perceptual diffs), `baseline-themes.md` |

### D. EF6 → EF Core

| ID | Perspective | Kind | Detection command | Reference |
|----|-------------|------|-------------------|-----------|
| MP-16 | **EF6 nested `Include` does not cause a compile error in EF Core — it causes a runtime exception.** `Include(x => x.Collection.Select(y => y.Nav))` requires `ThenInclude`. **The compiler does not detect this.** | ② | `grep -rnE 'Include\([a-z]+ *=> *[a-z]+\.[A-Za-z]+\.Select\(' --include='*.cs' $SRC` | **DP-5**, `reference/runtime-generation-differences.md` §4-2 |
| MP-17 | **Lazy loading changes from enabled by default (EF6) to opt-in (EF Core), so a missing `Include` silently returns `null` / an empty collection instead of throwing.** The page renders with HTTP 200, so HTTP status and page-render assertions still pass. **Value-level assertions are required.** | ② | Enumerate all navigation property accesses (`.Model.[A-Z][A-Za-z]*\.[A-Z]`-style chain references in `*.cshtml` + the same pattern in the service layer). During development, also use `ConfigureWarnings` to promote lazy-load warnings to exceptions. | `reference/runtime-generation-differences.md` §4-1, `baseline-themes.md`, MP-16 |
| MP-18 | **EF6 database initializers (e.g. `DropCreateDatabaseIfModelChanges`) have no equivalent, and a naive substitute destroys existing data.** Because EF Core uses a different model representation, naively implementing "recreate on model change" **drops production data**. This touches persisted data and requires a HOLD-2-equivalent judgment; **E2E cannot verify this** (attempting to do so destroys the DB). **Zero hits for the old API is still insufficient as detection** — the EF Core side of the application (`Migrate()` / `dotnet ef database update`) only runs if somebody calls it, so the moment the old API is removed **the application route itself is gone** (→ MP-24). | ②③ | `grep -rnE 'DropCreateDatabase\|IDatabaseInitializer\|Database\.SetInitializer\|CreateDatabaseIfNotExists' --include='*.cs' --include='*.config' $SRC`. **The replacement route is covered by MP-24.** | ADR-equivalent (migration to EF Core Migrations), MP-24, `reference/runtime-generation-differences.md` §4-7 |
| MP-19 | **`First` / `Single` / `Skip` / `Take` without `OrderBy` have no stable ordering guarantee in EF Core.** Only a warning is emitted; **results can vary depending on the execution plan and may not reproduce deterministically**. | ② | `grep -rnE '\.(First\|FirstOrDefault\|Single\|SingleOrDefault\|Skip\|Take)\(' --include='*.cs' $SRC` and cross-check whether the same query expression includes `OrderBy`. | MP-14, `reference/runtime-generation-differences.md` §4-3 |
| MP-20 | **Replacing a DI scope incorrectly means DbContext instances are not shared across repositories, breaking the Unit of Work.** The old-framework request scope (`InstancePerRequest()` etc.) causes a build error, so you notice — **but what you replace it with determines whether a silent failure is introduced**: no exception is thrown, only the main entity creation succeeds while the accompanying updates are never committed. | ③ | `grep -rn 'InstancePerRequest\|Autofac\.Integration\.\(Mvc\|Owin\|WebApi\)' --include='*.cs' $SRC`. **After replacement, assert along a complete request path that "1 request = 1 DbContext = 1 SaveChanges saves all changes"** (asserting only main entity creation still passes). | `verify-snippets.md` §integration (no corresponding DP) |
| MP-21 | **Tracking / detached changes cause a currently-inert branch to become active.** Removing one layer of a dual-guard pattern "because it's dead code" without understanding which layer actually fires causes a silent failure (e.g. an `IsModified = false` guard that prevents overwriting empty values, together with a caller-side `if (x != null)` check). | ③ | `grep -rn 'IsModified\|Entry(.*)\.Property\|SetValues\|AsNoTracking' --include='*.cs' $SRC` to enumerate; then trace each guard back to whether the query is tracking or non-tracking to determine **whether each guard actually fires today**. Before deleting "dead" guards, write down the firing condition. | CP-8 (demonstrated causality) |

### E. Meta-perspective (scepticism about the analysis output itself)

| ID | Perspective | Kind | Detection command | Reference |
|----|-------------|------|-------------------|-----------|
| MP-22 | **Items that automated analysis (ATX/CCA etc.) flags as "needing replacement" may in practice be dead code.** **The existence of a declaration is not proof of use.** In one measured case, the bundle mechanism was reported as "no equivalent replacement, HOLD candidate" — but all render calls were 0, making it dead code; if carried over, the scope would have included an unnecessary bundler. The counts also need re-verification (6 of 30 items were wrong). | ② | **Count the declaration side and the use side with separate commands.** Example: `grep -rn 'System\.Web\.Optimization\|BundleTable' --include='*.cs' $SRC` (declarations) and `grep -rn '@Styles\.Render\|@Scripts\.Render' --include='*.cshtml' $SRC` (renders). **If the latter returns 0, it is dead code.** | CP-3, **DP-4** |

### F. Deployment route, configuration injection, runtime platform

**Sections A–E scan the application source; this section scans the IaC, the container, and the configuration-injection route.**
`cdk synth` / `terraform plan` check **template syntax** but never the agreement with the application,
and local verification does not go through the production startup route (container, task definition, configuration injected by the IaC).
**A "missing" route never shows up in a grep that counts what exists.**
For this section, treat **the synthesized output (`cdk synth` / `terraform plan`) rather than the declaration as the basis for judgment.**

| ID | Perspective | Kind | Detection command | Reference |
|----|-------------|------|-------------------|-----------|
| MP-23 | **The CPU architecture declared for the container image, the build output, and the IaC do not agree.** The four places (`RuntimeIdentifier` / the base image / **the image build platform** / the IaC CPU setting) are managed separately, so **both the build and `synth` pass**. At runtime it either fails to start with `exec format error` or starts under emulation and **every feature is abnormally slow**. It especially happens when the dev machine (arm64) and the deployment target (x64) differ. **The fourth place is the easiest to miss**: CDK's `ContainerImage.FromAsset` holds the build target architecture separately in `AssetImageProps.Platform` (`Amazon.CDK.AWS.Ecr.Assets.Platform_.LINUX_AMD64`) and defaults to the build host if unspecified. The task definition can still declare `X86_64`, so **a grep for `cpuArchitecture` hits and looks "consistent"**. | ② | **Cross-check all four.** `grep -rn 'RuntimeIdentifier\|PlatformTarget' --include='*.csproj' $MODERNIZED` / `grep -rniE 'FROM \|--platform' $MODERNIZED` (Dockerfile) / `grep -rn 'FromAsset\|AssetImageProps\|Platform_' $MODERNIZED` (the image build setting) / the IaC CPU setting `grep -rniE 'cpuArchitecture\|architecture' $MODERNIZED`. **Settle it on the synthesized output**: `cdk synth && grep -o '"platform":[^,]*' cdk.out/*.assets.json` must return `"linux/amd64"`. **The scan target is the modernized tree** (the source has no such configuration, so 0 hits is correct). <br>⚠️ **Under QEMU user-mode emulation `dotnet publish` dies with SIGSEGV (exit 139)** (a known interaction with the .NET SDK JIT). A real cross-architecture build cannot be verified locally, so confirm through the declarations and the synthesized output. | MP-15 (the RID for native dependencies), MP-11 |
| MP-24 | **After the migration there is no route that applies the schema and seeds the data in a production-equivalent environment.** The old framework created them implicitly through EF6 initializers or `App_Start`, so **unless the target writes the application explicitly, the route itself disappears**. The application starts normally and returns HTTP 200 while **every screen is empty**. Local runs work off development-time initialization or test data, so **it only surfaces on the deployment target**. | ② | **Look for the route. The existence of migration definitions is not evidence of a route.** If `grep -rn 'Migrate()\|MigrateAsync\|EnsureCreated()' --include='*.cs' $MODERNIZED` returns 0 hits, there is no application route. **Even on a hit, judge one by one whether the surrounding `if` condition is true under the production configuration** (measured: it only ran inside a verification-only environment-variable branch). Also enumerate the IaC-side means of loading data (Custom Resource / RunTask / initContainer). **Reproduce it by starting up with every table dropped** (startup and the health check succeed; only DB-backed screens return 500). <br>⚠️ **If you fall back to applying it manually and the DB sits in a private subnet, the means of connecting (bastion / SSM port forwarding) is often absent from the IaC.** | MP-18 (initializers have no equivalent), HOLD-2-equivalent |
| MP-25 | **The configuration keys the IaC injects and the keys the application reads are written separately, so they diverge silently.** The .NET environment-variable configuration provider requires **`__` (double underscore)** as the hierarchy separator (`Services__Database` → `Services:Database`). Writing `Services/Database` or `Services:Database` on the IaC side **still deploys successfully; the application cannot find the value and falls back silently to defaults or local mode** (no exception, startup succeeds). Measured when deploying the public sample to ECS: no AWS service (S3 / Rekognition / RDS / CloudWatch) was ever enabled — it ran in local mode permanently. | ② | **Cross-check against the synthesized output as the basis** (reading only the IaC source misses the generated keys). Enumerate every key in the environment-variable block of the `cdk synth` template (or `terraform plan`), apply `__`→`:`, then cross-check against the application's read keys: `grep -rnE 'Configuration\[\|GetSection\(' --include='*.cs' $MODERNIZED` | MP-11 |

**The 'observation that lets you call it correct' (CP-4) and the 'negative test' (CP-13) are held in [verify-snippets.md](verify-snippets.md).** Perspectives whose detection means becomes a test: see [baseline-themes.md](baseline-themes.md).

### How the Perspectives Converge (measured)

On the public sample (AWS's Bob's Used Bookstore; ASP.NET MVC 5 + EF6 + OWIN / .NET Framework 4.8 → .NET 10 on Linux, ~8,400 lines):

- About **24 of the 41 ledger rows were ①** (the build enumerates the same list in seconds)
- **Switching the TFM and making the build green dropped unaddressed rows from 41 → 9**
- **All 9 remaining rows were ②③** (perspectives the build stays silent about or where it misleads)

**Converging to around 10 ②③ rows is the expected range.** If you have several dozen, suspect ① rows have been included. Conversely, if only a few appear, use a negative test to confirm the detector is actually working (CP-13).

### Positive Test Results for Detection Commands (measured 2026-09-13)

All commands were run against the migration source of the same public sample. **This must always be done to eliminate detection commands that were written but do not work** (see `verify-snippets.md` for negative-test procedures).

| ID | Result | Matches the independent ledger record |
|----|--------|---------------------------------------|
| MP-1 | 4 registration lines / `[AllowAnonymous]` in 5 files | ✅ match (5 exception classes) |
| MP-2 | `is HttpPostedFileBase` 2 hits / `ValidationAttribute` subclasses 2 | ✅ match |
| MP-3 | **46 tokens** (`asp-for` 22 / `asp-validation-summary` 5 / `asp-action` 5 / `asp-validation-for` 4 / `asp-items` 4 / `asp-controller` 4 / `asp-route-id` 1 / `asp-route-returnUrl` 1) / `_ViewImports.cshtml` 1 file (**absent from Area subdirectory**) | ✅ match (46) |
| MP-4 | `return View();` 5 hits | — |
| MP-5 | `<form>` with no `action`: 10 / hidden inputs with no `name`: 2 | — |
| MP-6 | 4 URLs / 24 `*Async` actions | ✅ match (4 URLs) |
| MP-7 | `wwwroot` not present | ✅ |
| MP-9 | `/Content/Images/` and `/Content/images/` **coexist in the same source** | ✅ match (case mismatch found) |
| MP-12 | `ToString("C"/...)` 14 hits / `<globalization>` **0 hits** | ✅ |
| MP-16 | Nested `Include` **8 hits** | ✅ match (8) |
| MP-18 | Initializers 2 hits | ✅ |
| MP-20 | `InstancePerRequest` / `Autofac.Integration.*` 3 hits | ✅ |
| MP-22 | Declarations 3 / **render calls 0 → dead code** | ✅ match (dead code verdict) |

**This positive-test pass found 2 bugs in detection commands** (fixed before the table above was finalized):

1. **MP-3**: `asp-[a-z-]*=` missed `asp-route-returnUrl` and returned **45** (correct: 46). camelCase route parameters had not been considered.
2. **MP-6**: `="[^"]*Async` returned **0**. URLs appear inside Razor interpolation that contains a `"`, so the character class stopped at the opening quote of the interpolation. **Reading 0 as "not applicable" would have dropped the entire perspective.**

**A ② perspective may return 0 when run against the migration source** (like MP-8, which only appears in the modernized tree's structure).
**When you see 0, suspect the scan target is wrong before concluding "not applicable".**

---

## Analysis Inputs (not drawn into the coverage baseline)

Perspectives that build / analyzer tooling enumerates (①), and inputs for deciding the migration target. **Do not open ledger rows for these.**
Count them only when a rough scope estimate is needed (the build produces the precise list).

| Perspective | Kind | Contents | How to verify |
|-------------|------|----------|---------------|
| Modern .NET version and EOL | Decision input | **Support stage and end date** of the target TFM. Do not rely on the "LTS" label alone (measured case: the version recommended by automated analysis had reached EOL a few months later). | Microsoft .NET support policy (primary source). CP-10 |
| Project file format | ① | legacy csproj → SDK format. `packages.config` → `PackageReference`. `HintPath` direct references, duplicate `AssemblyInfo.cs` definitions. | The build after conversion produces the precise list. Rough estimate: `grep -rl 'packages.config\|HintPath' --include='*.csproj' $SRC \| wc -l` |
| `System.Web` namespace removal | ① | `System.Web` / `System.Web.Mvc` / `Microsoft.Owin` / `ConfigurationManager` / `HttpContext.Current` / `Global.asax` / `System.Drawing` (GDI+) | **Compile errors enumerate every site. Do not count in advance.** |
| EF6 namespace and Fluent API renames | ① | `System.Data.Entity` → `Microsoft.EntityFrameworkCore`, `DbModelBuilder` → `ModelBuilder` | Same as above |
| Razor legacy helper replacement | ① | `@Html.Partial` → `PartialAsync`, `@Html.BeginForm` → `<form asp-action>` | Analyzer warnings and the build surface these. **Note: `asp-*` inertness is not ① but MP-3 (③).** |
| Configuration file migration | ① | `Web.config` / `App.config` → `appsettings.json` + `IConfiguration` (+ secret store) | A missing configuration key **causes startup failure** — it does not go silent. However, the **injection route** is covered by MP-11 (paths) and MP-25 (key spelling). |
| Container / IaC assumptions | ① | Windows container → Linux container, base image, `OperatingSystemFamily`, IaC project TFM | The IaC build / `synth` surfaces these. Note: **path separators → MP-11**, and **architecture agreement, configuration injection, and the schema-application route → section F** (the RID for native dependencies is MP-15) |
| Migration-source toolchain warnings | Decision input | ⚠️ **When the work host is macOS / Linux, the .NET Framework-targeting Upgrade Assistant / API Portability Analyzer cannot run.** One of the four ledger supply sources is **unavailable from the start** — plan accordingly (compensate with structural analysis + changelog review + code-driven scanning). | Test whether the tools run on the work host at the start. If not possible, document the compensating measures in the work-plan. |
| Existing test assets | Decision input | Whether test projects exist and can be run (determines the baseline mode). | `find $SRC -name '*.csproj' \| xargs grep -l 'Microsoft.NET.Test.Sdk\|xunit\|NUnit\|MSTest'` |

---

## Items to Include in the Environment Diff Table (0b-1)

From the perspective table and analysis inputs above, expand the ones **with concrete values for both migration source and target** into the "Domain-specific diff perspectives" section of `01-plan/environment-diff-table.md`.

| Diff perspective | Source value | Target value | ⚠️ Is the detection tool itself affected by this same difference? |
|-----------------|--------------|--------------|------------------------------------------------------------------|
| Culture-sensitive comparison implementation | NLS (.NET Framework always uses NLS) | ICU (default) | — |
| Default culture | Windows system locale | **Invariant** (unless explicitly specified) | — |
| Filesystem case sensitivity | Case-insensitive | **Case-sensitive** | ✅ **Yes.** If the work host is macOS, the detector is also case-insensitive, so `test -e` produces false negatives (CP-12). |
| Path separator | `\` | `/` | — |
| Lazy loading | Enabled by default (EF6) | Opt-in (EF Core) | — |
| Timezone ID | Windows format | **Modern .NET resolves both Windows and IANA formats** (on platforms with ICU available). "Linux cannot use Windows IDs" is **an outdated assumption**. | — |
| `decimal` rounding | `MidpointRounding.ToEven` | **Same** (unchanged). The round-trip formatting change applies only to `Double`/`Single`. | — |
| Native-dependency target RID | win-x64 | linux-x64 / linux-arm64 (**bundling varies per package**) | — |

**The rationale and primary-source URLs are in [reference/runtime-generation-differences.md](reference/runtime-generation-differences.md)** (with retrieval dates. §5 covers items where no difference was found).

**Do not fill the table with "there should be a difference."** The last two rows (timezone, `decimal`) are items where **checking the primary source found no difference**. Write "no difference" as an actual value too — otherwise the next project repeats the same investigation.

---

## Priorities for the Changelog Investigation (1-1)

- **Pull the compatibility-switch list first** ([reference/compat-switches.md](reference/compat-switches.md)).
  **The existence of a compatibility switch is evidence that the behavior changed.**
  Looking at "what you can revert" is faster than exhaustively searching for "what changed".
- **Distinguish dependencies that get a version bump from those that are replaced with a different implementation.**
  The latter cannot be tracked through a changelog; rely on the official migration guide (CP-9) and runtime verification (CP-4).
  Categories guaranteed to be "replaced" for .NET Framework → Modern .NET: MVC5 / Razor legacy helpers / EF6 / OWIN auth / DI container framework integration packages / bundling mechanism.
- **.NET Framework polyfill packages are removal candidates** (`System.Memory` / `System.ValueTuple` / `System.Text.Json` / `Microsoft.Bcl.*` / `System.Runtime.CompilerServices.Unsafe` / `Microsoft.Extensions.*.Abstractions` etc.).
  In Modern .NET these are part of the BCL, and **keeping explicit references can cause version conflicts**.
- **Cover the official breaking-change list exhaustively per version boundary** (CP-9). A .NET Framework 4.x → Modern .NET migration is a multi-step jump; read the Globalization / EF Core / ASP.NET Core categories separately.
- **EF Core query translation**: from EF Core 3.0 onward, expressions that cannot be translated **throw a runtime exception instead of falling back to client-side evaluation** (EF6 / EF Core 2.2 and earlier silently evaluated client-side). **Do not get the direction backwards** — it is "a query that worked in EF6 now throws", not "no exception but different result".
- **Globalization**: ICU as the default (from .NET 5) and behavioral drift across later versions. Note that enabling `InvariantGlobalization` makes `Compare` / `IndexOf` **always ordinal regardless of the argument**.
- **ASP.NET Core defaults**: `SuppressAsyncSuffixInActionNames`, static file root, deprecated Cookie / auth properties.
- **Native-dependent packages**: RID bundling status and cross-platform output differences.

---

## Notes for Analysis

- **Automated analysis claims are hypotheses** (CP-3). Re-measure both counts and "required work" against the real code. In particular, **challenge the assumption that something is actually in use** (MP-22).
- **Do not draw ① into the coverage baseline.** Rows with zero matches dilute the ledger and create a false sense of completeness.
- **A perspective with no detection command stays at 0 forever, no matter how much work you do.**
  Every ②③ must have a detection command.
- **Give every detector a negative test** (CP-13). Until you break it and confirm EXIT≠0, its detection ability is unproven.
- **Return any newly encountered perspective to this file** (CP-11). Do not let discoveries end within one project's records.
