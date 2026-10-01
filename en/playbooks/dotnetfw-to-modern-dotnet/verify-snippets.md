# verify.sh Implementation Snippets — .NET Framework → Modern .NET

`verify.sh` gate **templates for implementing this domain**. The verification logic
itself follows the framework core; **the project side writes only configuration values
and gate implementations**.
The snippets are extracted from code that actually ran in the migration of the public sample
(AWS's Bob's Used Bookstore).

**The "observation that lets you call it correct" (CP-4) and the "negative test" (CP-13)
for each `MP-N` in the perspective table ([analysis-appendix.md](analysis-appendix.md))
are in §6.**

---

## 1. Configuration values

```bash
# Modernized tree(s) — list all when there are multiple repositories
MODERNIZED_TREES=(
  "../<product>-modernized"
  # "../<component2>-modernized"
)

BUILD_CMD="${BUILD_CMD:-dotnet build <Solution>.sln -c Release}"

# Paths to scan for diagnostic/stub markers (limit to implementation source; exclude test code)
DIAG_SCAN_PATHS=(
  "app"
  "db-scripts"
)

# Non-functional gate is opt-in (set to 1 only when the Phase 1 ADR declares it in scope)
RUN_NONFUNC="${RUN_NONFUNC:-0}"

# Recommended to set to 1 for UI-rendering apps
REQUIRE_GOLDEN_PATH="${REQUIRE_GOLDEN_PATH:-1}"
```

⚠️ **`dotnet` may not be on PATH in some environments.** Add it explicitly at the top of each script:

```bash
export PATH="$HOME/.dotnet:$PATH"
```

## 2. build gate — expected artifacts

**Register all deliverables in scope when the work-plan is confirmed (day one)** (CP-7). Register them even before the build succeeds.

```bash
EXPECTED_ARTIFACTS=(
  # Output assembly per project. The path differs when TFM differs across projects
  "$MODERNIZED/app/<Web>/bin/Release/net10.0/<Web>.dll"
  "$MODERNIZED/app/<Data>/bin/Release/net10.0/<Data>.dll"
  "$MODERNIZED/app/<Domain>/bin/Release/net10.0/<Domain>.dll"
  "$MODERNIZED/app/<Common>/bin/Release/netstandard2.0/<Common>.dll"   # Shared libs may have a different TFM
  "$MODERNIZED/app/<Iac>/bin/Release/net10.0/<Iac>.dll"                # Also register the IaC project

  # Register not just code but also "things that should have been generated"
  "$MODERNIZED/app/<Data>/Migrations"                                  # EF Core Migrations

  # If there are native dependencies, verify that they were copied to the output (→ MP-15)
  # "$MODERNIZED/app/<Web>/bin/Release/net10.0/runtimes/linux-arm64/native"
)

# Exclusions — always state the reason (so future readers don't mistake them for omissions)
# <path> → <reason (ADR-N / AP-N)>
```

**Catching missing native dependency bundles here is effective.** The check is mechanical — "exists" rather than "worked". A missing copy only surfaces at runtime, and only when the code path that uses the feature is actually exercised.

## 3. smoke gate — startup check

**You may implement it in stages, but never leave it at the stub.**

```bash
gate_smoke() {
  echo "=== Gate 2: Smoke Test ==="
  if skip_if_plan_unconfirmed; then return 0; fi

  # --- Production smoke: the app starts and responds over HTTP ---
  local port=5099 pid=0 code=""
  ( cd "$MODERNIZED/app/<Web>" \
      && ASPNETCORE_URLS="http://127.0.0.1:$port" \
         ASPNETCORE_ENVIRONMENT=Development \
         dotnet run --no-build -c Release >/tmp/smoke.log 2>&1 ) &
  pid=$!
  for _ in $(seq 1 30); do
    code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/" 2>/dev/null || true)"
    [ "$code" = "200" ] && break
    sleep 1
  done
  kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true

  if [ "$code" = "200" ]; then
    pass "GET / returns 200"
  else
    fail "Startup check failed (last response code: ${code:-none})"
    tail -20 /tmp/smoke.log
  fi
  gate_result "smoke"
}
```

### ⚠️ Failure measured in practice: the stub smoke was never replaced

At Step 1 the modernized tree could not yet start, so we began with a **stub smoke** (checking the existence of the modernized tree, `.sln`, and a start tag). A comment in the code read "replace with HTTP GET / after Step 5 is complete." **The replacement never happened.** Startup was effectively verified through the integration tests (test host), so all gates kept passing and **the missed replacement was never detected by anyone**.

**Lesson:** if you place a stub smoke, write the replacement deadline as a completion condition of the corresponding work-plan Step. Comments in code are not checked by machines and will be forgotten. "Integration covers it so the smoke can stay a stub" does not hold — **a smoke is valuable precisely because it fails faster than integration**.

## 4. integration gate — running user journeys on a test host

In .NET, **an app test host (`WebApplicationFactory` equivalent) + an in-memory DB** can stand in for full E2E tests. **No Docker, no real DB required** — the same tests run in CI and locally.

```bash
#!/bin/bash
# 02-test/integration/run-integration.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="$HOME/.dotnet:$PATH"

TEST_PROJECT="$SCRIPT_DIR/<Product>.IntegrationTests/<Product>.IntegrationTests.csproj"
[ -f "$TEST_PROJECT" ] || { echo "❌ Test project not found: $TEST_PROJECT"; exit 1; }

dotnet test "$TEST_PROJECT" --configuration Release --logger "console;verbosity=normal" 2>&1
EXIT_CODE=$?
[ $EXIT_CODE -eq 0 ] && echo "✅ All integration tests PASS" || echo "❌ Integration tests failed (exit=$EXIT_CODE)"
exit $EXIT_CODE
```

### Passing authentication on the test host

Exercising protected pages requires authentication. Implementing the development auth middleware so that it checks only for the **presence of a Cookie key** lets tests pass by attaching a single Cookie (→ DP-7). **Guard against contaminating the production configuration by branching on the environment.**

### Registering tests

```bash
GOLDEN_PATH_TESTS=(
  "02-test/integration/run-integration.sh"   # Real user journeys (SC-1 to SC-N)
)
INTEGRATION_TESTS=(
  # Add individual check scripts here if needed
)
```

Setting `REQUIRE_GOLDEN_PATH=1` **makes an unregistered test FAIL**. Make this mandatory for UI-rendering apps. Reason: build and smoke only check "the app starts without an exception", so they **cannot catch the silent failure "no exception, HTTP 200, blank screen"**.

### What to assert (look at values)

**Many perspectives will pass if you only check HTTP 200 and page rendering.** Assertion types that proved effective in practice:

| Type | Example | Perspectives caught |
|------|---------|---------------------|
| Static asset returns 200 | `GET /Content/Images/<file>` returns 200 | MP-7 / MP-9 / MP-10 |
| Value appears in body | Book title and price strings are present | MP-17 (`Include` missing) |
| Format appears in body | Body contains currency symbol `$` | MP-12 |
| **Unauthenticated → 302** | Protected route redirects to authentication | MP-1 |
| **Anonymous → 200** | `[AllowAnonymous]` page opens without auth | MP-1 (**also catches over-locking regressions**) |
| Invalid input → not 500 | Validation failure re-renders the input form with errors | MP-4 |
| **Update does not become create** | Existing record is updated; count does not increase | MP-5 |
| Broken behavior pinned | "Update resets to default" fixed as expected value | Feature-exclusion (HOLD-1) approved sites |
| No duplicates at paging boundary | Page 1 and page 2 do not share the same ID | MP-14 / MP-19 |
| Attribute unchanged before/after | Updating info without changing image → image URL stays the same | MP-21 |

**It is normal to have rows that pin the current broken behavior as the expected value** (→ DP-3). **Always attach the approval ID (ADR) to that row.** Without it, the next maintainer will treat it as a bug and fix it.

## 5. nonfunc gate (opt-in) — security

Set `RUN_NONFUNC=1` only when the Phase 1 ADR declares this in scope. Place one script per perspective under `02-test/nonfunc/sc-n<N>-<name>.sh` and pass `MODERNIZED` as an environment variable.

```bash
gate_nonfunc() {
  echo "=== Gate 4: Non-functional Test ==="
  if skip_if_plan_unconfirmed; then return 0; fi
  local scripts=(
    "02-test/nonfunc/sc-n1-<idp>-wiring.sh"      # Authentication provider wiring
    "02-test/nonfunc/sc-n2-no-secrets.sh"        # No secrets in configuration
    "02-test/nonfunc/sc-n3-secure-headers.sh"    # Security headers
    "02-test/nonfunc/sc-n4-auth-filter.sh"       # Authentication required by default (→ MP-1)
    "02-test/nonfunc/sc-n5-n6-validators.sh"     # Upload validation (→ MP-2)
  )
  for script in "${scripts[@]}"; do
    [ -f "$script" ] || { fail "nonfunc script not found: $script"; continue; }
    if MODERNIZED="$MODERNIZED" bash "$script"; then pass "$(basename "$script" .sh)"
    else fail "$(basename "$script" .sh)"; fi
  done
  gate_result "nonfunc"
}
```

### Vulnerability scanning

```bash
dotnet list package --vulnerable --include-transitive
```

**Without `--include-transitive` this only looks at direct dependencies, producing a false negative.**
In practice, adding it immediately surfaced 1 High finding (a transitive dependency). Fix a transitive
dependency by writing a `PackageReference` directly in the `.csproj` to override the version, and confirm
that **the overridden version is what ships in the publish output**.

### ⚠️ Failure measured in practice: stopped at static analysis

The nonfunc script for upload validation (MP-2 / DP-6) was written as **static analysis of the implementation code**: does the attribute class exist / does it reference `IFormFile` / does the model carry the attribute / does the allowlist contain dangerous extensions. At the end of the script was this note — **"runtime negative test (actual rejection of oversized files and forbidden extensions) to be verified in E2E"**.

**That E2E was never added.** There are 13 integration tests, but **not a single one actually POSTs an oversized file or a `.exe` and checks that it is rejected**. The nonfunc gate kept passing nonetheless.

**MP-2 is "the silent failure where swapping the type makes all validation pass".** What static analysis can say is "the attribute is present" and "the string `IFormFile` exists" — it **cannot say "it is actually rejected"**. This is the state CP-13 describes as "the detector's capability is unproven".

**Lesson: it is fine to use static analysis as the entry point for security perspectives, but "runtime negative test later" means it never gets in.** Add it in the same Step.

## 6. Negative tests (CP-13) — break the detector and confirm EXIT≠0

**"Zero hits" reads as either "it is absent" or "the detector cannot find it".**
For each perspective, **deliberately introduce a violation, confirm the detector fails**, and record the procedure.

### Procedure template

```bash
# 1. Run the detector and record the current state (positive test)
./00-analysis/detection/<scan>.sh > /tmp/before.txt; echo "exit=$?"

# 2. Deliberately introduce a violation (temporary change to the modernized tree — do not commit)
#    Example: MP-9 → change one character in a reference path to the wrong case
#    Example: MP-1 → comment out the global authorization filter registration line
#    Example: MP-2 → revert the type guard in the validation attribute to HttpPostedFileBase

# 3. Confirm the detector fails
./00-analysis/detection/<scan>.sh > /tmp/after.txt; echo "exit=$?"   # ← must be non-zero

# 4. Revert the change and confirm the detector recovers
git -C "$MODERNIZED" checkout -- <file>
```

**Record two things: the "how to break it" and the "exit code observed".** Without the record, the detector's capability remains unproven and the adaptation ledger row cannot be marked "addressed".

### How to break each perspective (easiest first)

| MP | How to break it | Expected observation |
|----|----------------|----------------------|
| MP-1 | Delete the global authorization filter registration line | Unauthenticated request to a protected route returns 200 → integration FAILS |
| MP-2 | Revert the type guard in the validation attribute to the old type | POST of an oversized file is accepted → negative test FAILS |
| MP-3 | Delete the Area's `_ViewImports.cshtml` | Validation summary in the Area does not render → integration FAILS |
| MP-6 | Revert the assumption about `Async` suffix removal (rewrite the URL to `*Async`) | Affected button returns 404 → integration FAILS |
| MP-7 | Remove the `FileProvider` from `UseStaticFiles` | Static assets return 404 → integration FAILS |
| MP-9 | Change one character in a reference path to the wrong case relative to the actual file | Detector reports one mismatch → exit≠0 |
| MP-12 | Remove the request localization configuration | Currency-symbol assertion fails → integration FAILS |
| MP-16 | Revert `ThenInclude` to a nested `Include` | Runtime exception → integration FAILS |
| MP-19 | Remove `OrderBy` from a paging query | Paging boundary duplicate check fails (**may not fail every run** — because of the non-deterministic nature, **supplement with a static scan as the detection means**) |
| MP-21 | Remove one side of the double guard | Image URL disappears on an update that did not change the image → integration FAILS |

⚠️ **For perspectives like MP-19 where "breaking it may not cause a failure", do not rely solely on runtime tests.** Combine with a static scan (check for the presence of `OrderBy`).

## 7. Forbidden patterns (`FORBIDDEN_PATTERNS`)

Mechanically detect strings that must not remain in committed code. **Never run this gate with an empty list.**

```bash
FORBIDDEN_PATTERNS=(
  "NotImplementedException"          # Abandoned placeholder
  "TODO: *migrat"                    # Abandoned migration TODO
  "throw new NotSupportedException"  # Abandoned dead-end path from migration (use STUB- if intentional)
  "AllowAnonymous.*// *(temp|一時)"  # Trace of temporarily removed authorization
  "InvariantGlobalization>true"      # Disabling ICU as a shortcut (→ reference/compat-switches.md)
  "UseRelationalNulls"               # Changing null semantics (do not deviate from the default)
)

# Limit the scan to implementation source (patterns may appear legitimately in test code)
FORBIDDEN_SCAN_PATHS=(
  "app"
)
```

⚠️ **False-positive notes:**
- `NotImplementedException` **legitimately appears in auto-generated code or intentional abstract bases**. Narrow `FORBIDDEN_SCAN_PATHS` or add `// STUB-<id>:` to make the intent explicit.
- If you add `mock` / `fake` / `stub` as patterns, **exclude the test directory**. These are legitimate words in test code.
- **Lesson from practice**: on the public sample (AWS's Bob's Used Bookstore), the migration completed without setting **a single** `FORBIDDEN_PATTERN` (only one commented-out example was present). The gate always passed. **An empty forbidden-pattern list means "no violations" but also "no inspection".**

## 8. Multi-repository configuration

```bash
MODERNIZED_TREES=(
  "../<web>-modernized"
  "../<batch>-modernized"
)
DIAG_SCAN_PATHS=(
  "app"
  "src"
)
```

The `repo-sync` gate **checks all trees**. A state where only one tree has been committed will FAIL. `DIAG_SCAN_PATHS` **applies uniformly across all trees**, so if directory layouts differ between trees, write the union (non-existent paths are silently ignored).
