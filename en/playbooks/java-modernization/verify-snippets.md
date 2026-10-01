# verify Snippets — Java Modernization

A collection of snippets for implementing each gate of verify.sh in this domain.
(For the skeleton and usage of verify.sh, see the harness's verify.sh.template)

## Common Configuration

```bash
# Pin the JDK and locale (prevents execution under the system default JDK or a Japanese locale)
export JAVA_HOME="${JAVA_HOME:-/Library/Java/JavaVirtualMachines/amazon-corretto-21.jdk/Contents/Home}"
export MAVEN_OPTS="-Duser.language=en -Duser.country=US"
MVN="${MVN:-mvn}"
```

## build Gate

```bash
# ★ Be sure to include test-compile (DP-1). compile alone cannot detect leftover test code
BUILD_CMD="$MVN clean install -DskipTests"

# Example expected artifacts (war/jar)
EXPECTED_ARTIFACTS=(
  "$MODERNIZED/app/target/myapp.war"
  "$MODERNIZED/db-utils/target/db-utils.jar"
)
```

## smoke Gate

```bash
# --- App startup + HTTP response (example using a container plugin) ---
smoke_startup() {
  ( cd "$MODERNIZED" && $MVN jetty:run -pl app ) &   # or deploy the war to a container
  local pid=$!
  for i in $(seq 1 60); do
    code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/<context>/ || true)
    if [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ]; then
      pass "startup: HTTP $code"; kill $pid; return 0
    fi
    sleep 2
  done
  fail "startup: no HTTP response"; kill $pid 2>/dev/null
}

# --- Unit tests (if existing test assets exist, run every time as the smoke equivalent) ---
smoke_unittest() {
  ( cd "$MODERNIZED" && $MVN test -pl <module> ) && pass "unit tests" || fail "unit tests"
}
```

## integration Gate (E2E: Selenium + headless Chrome)

```bash
# Example: running the existing E2E module (build → E2E)
# Self-contained as 02-test/integration/e2e-selenium.sh
( cd "$MODERNIZED" && $MVN clean install -DskipTests -pl db-utils,app && $MVN verify -pl it-selenium )
```

Typical changes needed when modernizing the E2E foundation (counted as work-plan Steps):
- Container plugin: `jetty-maven-plugin` → `jetty-ee10-maven-plugin`,
  goal `start` → `start-war` (with a WAR overlay, `start` does not include the overlay contents)
- JNDI: defined in `WEB-INF/jetty-env.xml` (some contexts ignore `jettyXmls`)
- WebDriver: Firefox → headless Chrome. Selenium 4's Duration API
- Chrome options:
  ```java
  options.addArguments("--headless=new", "--no-sandbox", "--disable-dev-shm-usage",
                       "--disable-gpu", "--window-size=1920,1080", "--lang=en-US");
  ```
- Enable property resource filtering (resolving `${project.basedir}`)

## Multi-repository setups and diagnostic-marker scanning

```bash
# If one system consists of multiple repositories (e.g. the API and the SPA live in
# separate repositories), list them all. Keep them aligned with the repo-ids in
# repository-inventory.md.
MODERNIZED_TREES=(
  "../api-modernized"
  "../web-modernized"
)

# Paths to scan for diagnostic-code markers (DIAG-). For Java, narrowing to the
# implementation sources is faster
DIAG_SCAN_PATHS=(
  "app/src"
  "db-utils/src"
)
```

Keep the expected artifacts and integration tests as a single cross-repository list
(the gates ask "does it work as a system," so do not split them per repository).

## Mechanical detection of lost functionality

```bash
# An E2E test that drives the real user path in a browser. Mandatory for UI-rendering apps (DP-5)
REQUIRE_GOLDEN_PATH=1
GOLDEN_PATH_TESTS=(
  "02-test/integration/e2e-golden-path.sh"   # register -> log in -> main CRUD -> render
)

# Patterns that must not appear in committed code (a second net for unintended stubbing).
# Tag temporary ones with `// STUB-<id>:` (detected by the repo-sync gate)
FORBIDDEN_PATTERNS=(
  "not implemented"
  "TODO: *implement"
  "return null; *// *(temporary|stub|mock)"
)
# Exclude test code (mocks in tests are legitimate)
FORBIDDEN_SCAN_PATHS=(
  "app/src/main"
)
```

**Patterns that are prone to false positives:**

| Pattern | Caution |
|---------|---------|
| `UnsupportedOperationException` | Legitimately used for immutable collections etc. Narrow the scanned paths if you use it |
| `mock` | Legitimate in test code. Restrict `FORBIDDEN_SCAN_PATHS` to `src/main` |
| `@Disabled` / `@Ignore` | Useful for spotting disabled tests, but handle permanent skips under a separate rule requiring a reason comment |

Minimal golden-path E2E (`02-test/integration/e2e-golden-path.sh`):

```bash
#!/bin/bash
# Drive the real user path in a real browser. This is the first-class verification for
# "no exception, HTTP 200, blank screen", which build/unit/smoke cannot catch.
set -e
cd "${MODERNIZED:-../<PRODUCT>-modernized}"
JAVA_HOME="${JAVA_HOME:?}" mvn -q clean install -DskipTests -pl db-utils,app
JAVA_HOME="${JAVA_HOME:?}" mvn -q verify -pl it-selenium
```

The E2E MUST include **non-empty assertions** (confirm that something was actually rendered).
"HTTP 200 was returned" is not evidence of rendering.

## nonfunc Gate (opt-in)

```bash
# --- Memory/GC observation (long-running — the AI can handle this via background execution + log monitoring) ---
# Example: apply load after startup, record GC stats/heap trends with jstat, and compare against baseline
nonfunc_gc() {
  jstat -gcutil <pid> 10000 60 > /tmp/gc-current.txt
  # Compare against 02-test/test-results/baseline/
}
```
