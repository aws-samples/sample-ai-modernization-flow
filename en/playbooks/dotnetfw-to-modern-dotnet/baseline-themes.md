# Migration Theme Test Patterns — .NET Framework → Modern .NET

baseline (Characterization Tests) and test patterns to **systematically** incorporate into the
verify integration gate for behaviors that tend to break in this domain.
(For the common framework, see the `baseline-behavior.md` template in the harness.)

Implementation examples are in [verify-snippets.md](verify-snippets.md) §4;
primary sources are in [reference/runtime-generation-differences.md](reference/runtime-generation-differences.md).

---

## Test Patterns

| Theme | Test pattern | Reference |
|-------|-------------|-----------|
| **Static asset delivery** | **Assert per URL that images, CSS, and JS actually return 200.** A page rendering with HTTP 200 is not enough — a `<img>` 404 does not appear in the HTML. The `onerror` fallback target can also be a 404, so **the fallback image may not appear either**. | MP-7, MP-9, MP-10, DP-8 |
| **Related-data loading** | **Assert at the value level.** Not "the order detail page returns 200" but "the book title and price strings are present in the body". With lazy loading defaulting to OFF, a missing `Include` produces **no exception — just `null` / empty collections — and only the screen is empty**. | MP-17, DP-5, reference §4-1 |
| **Formatting (currency, numbers, dates)** | **Assert with the symbol included.** Not "an amount is displayed" but "the body contains `$`". The default culture depends on the container environment, so **formatting rules may not change but the display does**. | MP-12, reference §5-2 |
| **String sort order** | **Pin the list sort order.** NLS → ICU changes the handling of non-alphanumeric characters (differences appear with data containing apostrophes, symbols, or ligatures). Check whether the real data contains such records first; if not, **add them to the test data**. | MP-13, MP-14, reference §2-1 |
| **Paging boundaries** | **Assert that page 1 and page 2 do not share the same ID.** Range operations without `OrderBy` have no guaranteed stable order in EF Core. ⚠️ **Non-deterministic — do not rely solely on a runtime test** (combine with a static scan). | MP-14, MP-19 |
| **Authorization defaults** | **Pin both directions.** ① Unauthenticated requests to protected routes are redirected to authentication. ② Pages with anonymous access return 200 anonymously. Omitting ② means missing **over-locking regressions**. | MP-1 |
| **Input validation — rejection side** | **Assert that invalid input is actually rejected.** POSTing an oversized file or a forbidden extension (`.gif` / `.svg` / `.exe`) must be rejected. **A successful upload in the happy path cannot distinguish "guarded" from "unguarded".** Static analysis (checking that the attribute is present) is not a substitute. | MP-2, DP-6, verify-snippets §5 |
| **Re-render on validation failure** | **POST invalid input and assert the response is not 500.** Re-rendering without passing the model produces `NullReferenceException` only after Tag Helpers are activated. **The happy path can never reach this code path in principle.** | MP-4, DP-3 |
| **Update vs. create** | **Assert at the ID level that an existing record is updated and the count does not increase.** A form without an `action` that is saved by the current URL's route values will lose its ID if you "tidy it up", causing a new record to be created instead. | MP-5, DP-3 |
| **Transaction boundary** | **Count all side effects.** Not "an order was created" but "an order was created, inventory decreased, and the cart is empty" — verified in the same commit. An incorrect DI scope causes only the primary entity to be committed. | MP-20 |
| **Overwrite-protection branch** | **Assert at the value level that unmodified attributes are unchanged before and after a save.** "The update succeeded" will pass. When tracked/detached state changes, a "currently inactive branch" starts firing, and **removing either guard becomes a silent failure**. | MP-21 |
| **Button-driven navigation** | **Assert that the state actually changes.** Rendering the list page alone will pass. A routing convention change (`Async` suffix auto-removal) causes **the screen to be fine while only the button returns 404**. | MP-6 |
| **Per-Area view mechanism** | **Assert that validation summaries etc. render even in screens under an Area.** View-wide settings apply only to the current folder and its subfolders; Areas are treated separately. Checking only the root misses unrecovered Areas. | MP-3, DP-3 |
| **Native-dependency output** | **Do not use byte-identical comparison.** Assert on **perceptual or structural properties** such as dimensions, format, channel count, or file size range. No primary source guarantees byte-identical output for the same input, and cross-architecture differences have been reported. | MP-15, reference §6 |
| **Pinning current broken behavior** | **Pin the "currently broken" state as the expected value for feature-exclusion approvals.** Example: assert "updating resets the value to its default". **Always attach the approval ID (ADR) to that row** — without it, the next maintainer treats it as a bug, fixes it, and the test breaks. | DP-3, HOLD-1 |

---

## Choosing a baseline mode (notes for this domain)

| Situation | Mode | Note |
|-----------|------|------|
| Current environment is running and can be observed | A (measure on the old environment) | The strongest option — directly captures before/after diff |
| **No current environment and no test assets** | **B (define by reading the code)** | Most common in this domain. See pitfall below |
| Existing test assets can be reused | C (reuse the existing tests) | First confirm that the .NET Framework tests can be built on Modern .NET |

### Mode B (define by reading the code) pitfall: include Razor views and configuration files in the coverage baseline

Recording a failure measured in practice. **Making `.cs` files the sole coverage baseline for Mode B (define by reading the code) drops the main part of the migration risk.**

On the public sample (AWS's Bob's Used Bookstore), the initial coverage baseline was 129 `.cs` files / 5,722 lines, but **42 Razor view files (2,269 lines) and 7 configuration files (385 lines) were missing**. What was dropped specifically:

- `ToString("C")` usages (currency format) → MP-12
- Static asset path references → MP-9
- Locations of legacy Razor helpers and `asp-*` attributes → MP-3
- The presence or absence of the `<globalization>` setting itself

**The correct coverage baseline is "`.cs` + `.cshtml` + `.config`"** (178 files / 8,376 lines on the public sample). Looking only at `.cs` files leads to the assumption that ".NET Framework coupling lives in the code", **missing the coupling concentrated in views and configuration**.

**Verify coverage rate mechanically.** Take the set difference between the coverage baseline list and the list of files actually read, then **confirm the unread count is zero mechanically**. The typical failure is measuring only precision without measuring recall.

### Reading the web layer first is front-loading, not extra work

Reading the web layer may feel expensive, but **.NET Framework coupling concentrates in the web layer**, so Phase 2 corroboration will require reading that range regardless. **It is front-loading, not an increase in total work.**

---

## Do not use auto-extracted "business rules" as specifications

**For a technology-stack migration, do not use auto-extracted business rules as the baseline source.**

Measured: corroborating 42 items across 4 domains against primary source code found only **23 items (55%) were accurate** — 12 insufficient, 7 wrong. **The bigger problem is not precision but the blind spot in scope** — automatic extraction looks at domain-layer business rules, but **.NET Framework coupling concentrates in the web layer, which it structurally does not examine. It does not cover the places where baseline is most needed.**

**Precision can be rescued by corroboration; recall cannot.** The extraction result may be kept as a reference, but **the source of expected behavior must be the actual code**.
