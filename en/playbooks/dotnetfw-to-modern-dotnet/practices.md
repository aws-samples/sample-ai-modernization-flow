# Migration Practices — dotnetfw-to-modern-dotnet

<!-- ⚠️ Draft before upstreaming (2026-09-13). Not yet reflected upstream.
     Source: DP-bookstore-1 through DP-8 from the project's docs/knowledge/practices.md, renumbered and generalized. -->

<!-- KNOWLEDGE-REVIEWED: 2026-09-13 (9 entries, playbook newly created) -->

Knowledge specific to projects that **migrate applications running on .NET Framework (4.x)
to modern .NET (.NET independent of .NET Framework)** is accumulated here in `DP-N` format.
For domain- and language-agnostic knowledge, see `CP-N` in `method/practices-common.md`.

Scope examples: ASP.NET MVC 5 (OWIN self-host / IIS) → ASP.NET Core / resolving `packages.config`
and `PackageReference` coexistence / replacing Windows-specific APIs (`System.Web`, IIS integration,
registry, `Web.config` transforms) / porting to a Linux target / containerization.

**The agent reads only the Summary table by default.** Open the body only when the relevant topic is encountered.

A primary-source-backed differences catalog is in [reference/runtime-generation-differences.md](reference/runtime-generation-differences.md);
verification implementation examples and negative tests are in [verify-snippets.md](verify-snippets.md). **Do not duplicate the body here.**

---

## Summary

| ID | Key point | When it applies | One-line reason |
|----|-----------|----------------|-----------------|
| DP-1 | Validate the target .NET version against primary sources for **support phase and end-of-life date** | 0b (target selection) | .NET ships a new version every November; the tool recommendation and the current optimum are easily 1–2 generations apart. "LTS" says nothing about time left |
| DP-2 | Long-running analysis jobs (ATX) are committed Step-by-step and can be resumed by conversation ID | 0a (run the analysis) | Interruption ≠ start over. Check the staging-branch commit status first. Verify completeness of artifacts yourself |
| DP-3 | MVC5 `asp-*` attributes are inert. Evaluate **per site and per Area** on the assumption they become active | 1-2 / 3 (views) | `_ViewImports.cshtml` is Core-only and covers its own folder and subfolders (Areas need their own). "Same as current behavior" cannot be the success criterion |
| DP-4 | **Remeasure** the counts and "required work" from automated analysis. **Declaration is not evidence of use** | 2 (planning) | In practice 6 of 30 items were wrong. Reading dead code as "needs replacement" adds unnecessary dependencies to scope |
| DP-5 | Nested `Include` from EF6 **does not cause a compile error in EF Core — it throws at runtime** | 3 (Data layer) | `.Include(x => x.Nav.Select(...))` requires `ThenInclude`. Type is unchanged, so static analysis misses it |
| DP-6 | Validation attributes that assume `HttpPostedFileBase` **become a silent failure when changed to `IFormFile`** | 3 (Web layer / security) | `base.IsValid(object)` returns `true` by default. Size limit and extension allowlist both disappear at once |
| DP-7 | `IMiddleware` implementations **require DI registration**. Some Cookie auth properties are deprecated | 3 (Web layer) | A missing registration throws on the first request. Setting a deprecated property throws **at startup** |
| DP-8 | Without `wwwroot`, provide a `FileProvider` explicitly to `UseStaticFiles` | 3 (Web layer) | The default looks for `wwwroot/`. On legacy layouts **all static files return 404** (build and startup still succeed) |
| DP-9 | OWIN Active mode **redirects implicitly as a side effect of authorization**. In Core, call `Challenge()` explicitly | 3 (Web layer / auth) | The login route existed with no code behind it. Adding `[AllowAnonymous]` kills login in production |

---

## DP-1: Select the target .NET version by support phase and end-of-life date, not just "Is it LTS?"

- **When it applies**: When deciding the target TFM in Phase 0b. When using recommendations from automated analysis (ATX/CCA etc.) or an LLM as input.
- **The failure shape**: The version an automated analysis recommends is **older than the current date**. In a measured case, CCA recommended `net8.0` (LTS) throughout its output and described a newer LTS as "upcoming (to be released)" — but that version was already GA. Checking the primary source revealed the **recommended version had an EOL about two months away** and had already entered the Maintenance phase (security fixes only).
  **Following the recommendation would have produced a migration whose target was already EOL at completion.**
- **Three points for the decision** ("Is it LTS?" alone is insufficient):
  1. **Support phase** — Maintenance means security fixes only. **Never choose it as the target for a new migration**
  2. **Gap between end-of-life date and expected completion** — does it cover the migration period plus subsequent operation?
  3. **Release cadence** — .NET releases a new version every November. Even = LTS (3 years) / Odd = STS (2 years)
- **Procedure**: Fetch the official support-policy table **fresh each time** and copy the "support phase" and "end-of-life date" into the ADR (with the retrieval date). **Recording only a version name leaves the next reader unable to assess remaining support time.**
- **Why it is domain-specific**: .NET has a **high-frequency release cycle** where even LTS expires in three years. This means "the latest LTS in the training data" and "the LTS to choose at work time" are easily 1–2 generations apart — faster version staleness than languages with longer LTS lifetimes.
- **Anti-patterns**:
  - Taking the recommended TFM from automated analysis straight into the work-plan → the migration target may be EOL at completion
  - **Deciding on "it's LTS, so it's safe"** → LTS/STS indicates only **the length of support**, not the **remaining time**
- **Related**: CP-3 / CP-10 / DP-4 (a different manifestation of the same "copy automated analysis" failure)

## DP-2: Long-running analysis jobs are committed Step-by-step and can be resumed by conversation ID

- **When it applies**: When running a long-running analysis job (ATX CCA etc.) in Phase 0a. When an interruption occurs.
- **Two points confirmed by measurement**:
  1. **Git commits are written Step-by-step during execution.** In a measured forced-stop case, **4 commits and 104 files** were already committed on the staging branch at the point of interruption. The working tree was clean with no git lock remnants, and **no artifacts were lost**
  2. **The log tail shows a resume command.** The conversation ID matches the suffix of the staging branch name, and logs and artifacts remain locally
- **Procedure**:
  1. **When an interruption occurs, first check the staging-branch commit status**
     (`git log --oneline main..HEAD` / `git diff --name-only main..HEAD | wc -l`)
  2. **Save the artifacts first, then restore the branch.** Artifacts are committed to the staging branch, so `git checkout main` first would remove them from the working tree
  3. Use the resume command shown at the log tail as-is
  4. **Regardless of whether the resume succeeded, verify artifact completeness mechanically yourself.**
     Count "domain count × required files". **The tool's "completed" report or immediate termination of the resume session is not proof that artifacts are complete**
- **Why it is domain-specific**: Strictly speaking this is a property of analysis tools in general. It is placed here because it is knowledge obtained from measurements in this domain.
- **Anti-patterns**:
  - Treating interruption as "start over" and re-running from the beginning → wastes hundreds of agent-minutes
  - Deleting the staging branch to clean up → **off-limits violation**. Destroys artifacts and commit history. Only `git checkout main` is needed to restore
- **Related**: HOLD-6 (stopping a long-running in-flight job) / CP-4

## DP-3: `asp-*` attributes remaining in MVC5 are inert. Evaluate per-site and per-Area assuming they will become active

- **When it applies**: ASP.NET MVC 5 → ASP.NET Core migration. Especially when the target is a **backport** from a Core version, or when there are traces of a prior Core attempt.
- **Facts (verified against primary sources)**:
  - `_ViewImports.cshtml` and `@addTagHelper` are **ASP.NET Core-only mechanisms**; the MVC5 Razor engine does not read them. Common view usings in MVC5 are provided via **`Views/Web.config`**
  - A `<Content Include>` in `.csproj` is not a compilation target, so **the file existing and the build succeeding is not evidence that it is in effect**
  - Therefore in MVC5, `asp-for` / `asp-items` / `asp-action` / `asp-validation-summary` are **output as bare HTML attributes and have no effect**
- **Procedure**:
  1. `grep -rho 'asp-[a-zA-Z-]*=' --include='*.cshtml' $SRC | sort | uniq -c` to enumerate all occurrences by token.
     ⚠️ **Narrowing the character class to `[a-z-]` cuts off camelCase attribute names like `asp-route-returnUrl`**
  2. Open `Views/Web.config` and confirm the Tag Helper mechanism is **not active**
     (do not judge by the presence of `_ViewImports.cshtml` alone)
  3. **Count `_ViewImports.cshtml` files per folder and confirm whether each Area has one.**
     `_ViewImports.cshtml` **applies only to its own folder and its subfolders;
     `Areas/<Area>/Views/` is not a subfolder of `Views/`**
     → Assuming "activating once recovers all views" will **misclassify Area views into the recovery group**
  4. **Classify each occurrence by "would activating it change behavior?"** Sites that recover will
     **behave differently from current behavior** after migration, so the success criterion cannot be "equivalent to current" → **Write an ADR and fix the classification rules first**
  5. **Look for paths that only become reachable once the attribute is active.** Since an inert attribute is never evaluated, things like re-rendering with a null model are not exposed in the current environment
- **Pitfall**: A `<form>` without an `action` that also has no `name` on hidden fields may currently be
  **working because the route values in the current URL rescue it**. When `asp-action` is explicitly added during migration to "clean it up," the binding disappears and it breaks. **Classify such sites as "keep as-is" and make that a documented prohibition.**
- **Post-migration note**: After migration, `asp-*` becomes **valid markup**, so the hit count cannot be used to judge for migration gaps. Use "Is the Tag Helper mechanism active?" as the criterion.
- **Related**: MP-3 / MP-4 / MP-5 / DP-6 (same category of "type or mechanism change becomes a silent failure")

## DP-4: Remeasure counts and "required work" from automated analysis. Especially suspect the "assumed to be in use" premise

- **When it applies**: When using the technical-debt / remediation-plan from automated analysis (ATX/CCA etc.) as input for the work-plan or adaptation ledger. **This is a different failure mode from DP-1 (version staleness).**
- **Observed error rate**: In **6 of 30 items** cross-referenced, the description and measured values diverged. Two types:
  1. **Count divergence** (4 items): all were **under-counted**; directly reflecting them in effort estimates would leave the work under-resourced.
     View-count divergence was also partly a **definitional difference** of whether to count partial views and layouts
     → **Any count that lacks a definition must be recounted after deciding the definition yourself**
  2. **"Required work" errors** (2 items — more dangerous):
     - A bundling mechanism was described as **"needs replacement with a bundler tool"** but the render call count was **0** — it was **registered but never rendered, dead code**. Copying it would have **added an unnecessary dependency to scope**
     - Nested `Include` was shown with **one example** but the actual count was **8 sites**. Reading the example as a count produces an 8x underestimate of effort
- **Why this happens**: **Automated analysis sees "is the dependency declared?" and infers "it is in use."**
  Declaration and use are separate facts; the former does not determine the latter. Also, files
  not reachable from build roots (`.csproj` / `.sln`) — deploy scripts, SQL, static assets — **systematically fall outside the analysis scope**.
- **Procedure**:
  1. **Do not copy figures from the analysis into documents.** Write a remeasurement script and use its output as the authoritative source
  2. The script checks "does it match the measured values recorded in the comparison table?" not "does it match the analysis?". An item where the analysis is wrong **should stay wrong in the authoritative table**
  3. Accept a "needs replacement" claim only **after counting the usage sites of the replacement target**.
     0 sites means the work is "remove it" — no alternative selection needed (no loss of functionality either)
  4. **Record analysis errors in a separate section of the comparison table.** Mixing them in the same table leaves subsequent readers unable to tell which to use
- **Side effect**: The same process also surfaces **errors in the justification text of your own ledger** (entries where the conclusion is correct but the evidence is wrong).
- **Related**: CP-3 / MP-22 / DP-1

## DP-5: Nested `Include` from EF6 does not cause a compile error in EF Core — it throws at runtime

- **When it applies**: EF6 → EF Core migration (Data layer).
- **Problem**: EF6 allows the nested syntax `Include(x => x.Orders.Select(o => o.Items))`.
  EF Core **does not flag this at compile time; it throws `InvalidOperationException` at runtime**.
- **Fix**:
  ```csharp
  // EF6
  .Include(x => x.OrderItems.Select(i => i.Book))
  // EF Core
  .Include(x => x.OrderItems).ThenInclude(i => i.Book)
  ```
  Sweep for all occurrences during migration with `grep -rnE 'Include\([a-z]+ *=> *[a-z]+\.[A-Za-z]+\.Select\('`.
- **Also see**: Because lazy loading is off by default in EF Core, **missing `Include` calls become a silent failure as `null` / empty collections rather than exceptions**. In E2E tests, **assert at the value level that related data actually appears on screen** (HTTP 200 and page rendering will pass regardless).
- **Why it is domain-specific**: Projects following the EF6 → EF Core path encounter this without exception.
  **Because the API changes rather than the type system, static analysis misses it.**
- **Related**: MP-16 / MP-17 / reference §4-1, §4-2

## DP-6: Custom validation attributes that assume `HttpPostedFileBase` become a silent failure when changed to `IFormFile`

- **When it applies**: File upload handling during ASP.NET MVC 5 → ASP.NET Core migration. **Has security impact.**
- **Problem**: An attribute that inherits `ValidationAttribute` and casts to `HttpPostedFileBase` for its check will, after changing to `IFormFile`, **call `base.IsValid(value)` whose default implementation returns `true`, causing validation to always pass**. No build error or runtime exception occurs.
  As a result **both the size limit and the extension allowlist disappear at once**.
- **Fix**:
  ```csharp
  // Before (always returns true after IFormFile change)
  public override bool IsValid(object? value) {
      if (!(value is HttpPostedFileBase file)) return base.IsValid(value); // ← returns true here
      return file.ContentLength <= maxFileSize;
  }
  // After
  public override bool IsValid(object? value) {
      if (value == null) return true;
      if (value is IFormFile file) return file.Length <= maxFileSize;
      return true;   // ← if the type is unexpected and the design is to pass, leave a comment stating the intent
  }
  ```
- **Verification**: After migration, confirm with a **runtime negative test** (that an over-limit file and a disallowed extension are actually rejected on POST).
  **A successful normal-case upload alone cannot distinguish whether the guard is present or absent.**
  ⚠️ **Do not settle for static checks alone (whether the attribute is present / whether it references `IFormFile`).**
  Static checks can only say "the attribute is present," not "the file is actually rejected"
  (this was missed in practice → see the corresponding section of `verify-snippets.md`)
- **Why it is domain-specific**: `HttpPostedFileBase` → `IFormFile` is a **standard step** in .NET Framework → ASP.NET Core migration. Because it is standard, it is done mechanically, leaving the cast in the attribute behind.
- **Related**: MP-2 (canonical ③ example) / `verify-snippets.md` §negative-test

## DP-7: `IMiddleware` implementations require DI registration. Deprecated Cookie auth properties throw at startup

- **When it applies**: Writing custom middleware or Cookie authentication during migration to ASP.NET Core.
- **Problem**:
  - When registering an `IMiddleware` implementation (`InvokeAsync(HttpContext, RequestDelegate)`) with `UseMiddleware<T>()`, **`T` must be registered in the DI container**. Without registration, the first request causes a resolution-failure exception. (Convention-based plain classes do not require registration, so **the requirement varies by how the class is written** — this is the trap)
  - Some `CookieAuthenticationOptions` properties are deprecated; setting them throws an options-validation exception **at startup** (`Cookie.Expiration` → `ExpireTimeSpan`)
- **Fix**:
  ```csharp
  builder.Services.AddTransient<LocalAuthenticationMiddleware>();   // required for IMiddleware implementations
  options.ExpireTimeSpan = TimeSpan.FromDays(1);                    // Cookie.Expiration is deprecated
  ```
- **Side benefit**: A local-development authentication middleware (auto-sign-in by Cookie presence) **can be reproduced in the test host of integration tests**. An implementation that checks for the Cookie key (`context.Request.Cookies.ContainsKey(name)`) passes authentication regardless of value decryption, making it easy to drive auth through E2E. **Never mix it into the production configuration** (branch by environment).
- **Related**: MP-8 / `verify-snippets.md` §integration (authentication in the test host)

## DP-8: Without `wwwroot`, explicitly provide a `FileProvider` to `UseStaticFiles`

- **When it applies**: Moving an MVC5 legacy layout (`Content/` and `Scripts/` at the project root) to ASP.NET Core.
- **Problem**: In MVC5, IIS served static files directly from the project root.
  ASP.NET Core's `UseStaticFiles()` **looks for `wwwroot/` by default**, so on a layout without `wwwroot/`
  **no static files are served at all (404)**. **The build and startup both succeed.**
- **Fix** (option that avoids physically moving files):
  ```csharp
  using Microsoft.Extensions.FileProviders;

  app.UseStaticFiles(new StaticFileOptions
  {
      FileProvider = new PhysicalFileProvider(app.Environment.ContentRootPath),
      RequestPath = ""
  });
  ```
  This makes `/Content/Images/` serve from `{ContentRoot}/Content/Images/`.
  **Align the write side too**: reference `env.ContentRootPath` rather than `env.WebRootPath` (which defaults to `ContentRoot/wwwroot`). **Fixing only one side produces "save succeeds, display is 404"** (→ MP-10).
- **Comparing the options**: Physically moving files to `wwwroot/` is more aligned with the framework convention, but
  **requires a bulk rewrite of reference paths**, and debugging alongside case-sensitivity mismatches (MP-9) at the same time is hard to isolate.
  In the first migration pass, serve via an explicit `FileProvider` and **align with the convention in a separate Step**.
- **Related**: MP-7 / MP-9 / MP-10

## DP-9: OWIN Active-mode authentication redirects implicitly. In Core, call `Challenge()` explicitly

- **When it applies**: Migrating OWIN external authentication (OIDC / Cognito / Azure AD etc.) to ASP.NET Core.
- **Problem**: OWIN authentication middleware defaults to **Active mode** and automatically redirects unauthenticated
  requests to the authentication provider. **The global authorization filter emits a 401 and the middleware picks it up
  and redirects**, so **there may be no code at all that implements the login route.**
  ASP.NET Core defaults to the Passive equivalent: **no redirect happens unless `Challenge()` is called explicitly.**
- **Worst form**: The migrator thinks "the login page should be visible while unauthenticated" and adds `[AllowAnonymous]`
  to the login controller. **It looks correct, the build passes, and the local simple-auth mode works.**
  But in production mode the 401 no longer happens, making **login fundamentally impossible** (measured: we hit this).
- **Fix**:
  ```csharp
  // Login action in production (external IdP) mode
  return Challenge(
      new AuthenticationProperties { RedirectUri = returnUrl ?? "/" },
      OpenIdConnectDefaults.AuthenticationScheme);
  ```
- **Missed for the same reason**: `SignOutAsync()` against a handler that does not implement
  `IAuthenticationSignOutHandler` throws **`InvalidOperationException`**. OWIN's
  `AuthenticationManager.SignOut()` has no corresponding constraint, so a straightforward port hits it.
  For each call in `grep -rn 'SignOutAsync(' --include='*.cs' $MODERNIZED`, cross-check that the handler for
  the scheme implements that interface.
- **Verification**: **Assert the raw status code and the `Location` header** (does it point at the IdP discovery URL?).
  If redirects are followed automatically, an intended 302 and a 302 from a silent failure are indistinguishable.
- **Why domain-specific**: This is a **difference in default mode** specific to OWIN → ASP.NET Core. Types and method
  names are replaced so the build passes; what disappears is only the behavior "an implicit redirect".
- **Related**: MP-1 (the `AllowAnonymous` file-set diff) / MP-25 (the same screen breaks for a different reason when
  production configuration is not injected)

<!-- ENTRIES END -->
