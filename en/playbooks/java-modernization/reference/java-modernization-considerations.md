# Java Modernization Considerations

A domain knowledge collection for Java modernization involving major framework and runtime
upgrades. Distilled from real-world experience migrating legacy Java applications
(Java 11→21, Struts 2.x→7.x, Spring 5→6, Jakarta EE 10, Bootstrap 3→5).

## 1. Selecting the Target Stack (Phase 1 — CP-10)

- **EOL/LTS check**: Tabulate Java LTS versions (17/21/25...) and framework support end dates
- **Compatibility matrix**: Enumerate chains such as "Struts 7.x → requires Jakarta EE 10",
  "Spring Security 6.x → requires Spring 6.x", "Spring 6.x → requires Jakarta EE 9+", and
  confirm there are no contradictions
- **Handling multi-step jumps**: Jumping two or more major versions accumulates breaking
  changes. Count the breaking changes from the official guides (multiple exist per
  boundary — CP-9), multiply by the number of affected files to estimate cost, and
  decide whether to proceed in stages or all at once

## 2. Common Namespace/API Migration Patterns

| Item | Description |
|------|------|
| javax → jakarta | Jakarta EE 9 changed the namespace entirely. This ripples through imports, web.xml, TLDs, and configuration files |
| Servlet container | Jetty 12 has separate artifacts per EE8/9/10 (`org.eclipse.jetty.ee10.*`). Tomcat 10.1+ = EE10 |
| Mail | `javax.mail` → `jakarta.mail-api` + implementation (angus-mail) |
| Connection pool | commons-dbcp → commons-dbcp2 |
| SLF4J 1.x → 2.x | The binding mechanism changed (ServiceLoader-based) |

## 3. Security-Hardening Defaults and Silent Failures (DP-2)

Modern frameworks are evolving toward enabling security restrictions by default, and
**legacy code invariably stops working as a silent failure, without exception**. Known patterns:

| Symptom | Example cause | Detection method |
|------|---------|---------|
| Dynamic content renders as an empty string | Expression language allowlist (Struts OGNL) | E2E non-empty assertions + diagnostic logging |
| Form values not populated / NPE | Parameter binding now requires annotations | E2E round-trip of forms |
| Silent upload failure | Generational change in the file upload API (old setter no longer called) | Verify the result exists |
| 403 Access Denied | CSRF enabled without corresponding form support | E2E across all POST paths (DP-3) |

## 4. Spring Security CSRF Pitfalls (DP-3)

- Login forms often live in a separate JSP and are easy to miss
- POSTs from anonymous users (e.g., comments) cannot carry a token → path exclusions are needed
- `security="none"` strips away credentials entirely and cannot be trusted with FORWARD dispatch
- `<csrf request-matcher-ref>` **completely overrides** the default method filter
  → Use `AndRequestMatcher` to compose "NOT(GET|HEAD|TRACE|OPTIONS) AND NOT(excluded paths)"
- For multipart/form-data, the filter cannot read a hidden-field token
  → Use the query-parameter approach on the action URL (a single shared-header JS snippet can cover all forms)

## 5. Migrating the E2E Test Infrastructure (Baseline Mode C = reuse the existing tests)

If an existing Selenium E2E suite exists, getting it running on the modern stack is itself
part of the migration work:

- Update the container plugin to an EE-compatible version; for WAR overlays, use the `start-war` goal
- JNDI resources go in `WEB-INF/jetty-env.xml` (`jettyXmls` is ignored depending on the context)
- WebDriver: headless Chrome (`--headless=new --no-sandbox --window-size=1920,1080 --lang=en-US`)
- **Locale**: Server-side i18n is resolved using the JVM's default locale.
  Pin it with `MAVEN_OPTS="-Duser.language=en -Duser.country=US"`
- Don't make selectors depend on framework-generated IDs (DP-4)

## 6. Testability (When Writing New Code During Conversion)

- Design interface boundaries for external SDK integrations up front (don't let the SDK's final types leak outside the boundary)
- Isolate dependencies on static methods and global state so they can be substituted during tests
- Verify the test execution environment (JAVA_HOME, Maven path) before coding
- Alternate between writing production code and test code (retrofitting testability later is double the work)

## 7. Interaction with the Deployment Environment (Reference)

Constraints of the target environment can sometimes flow back into application changes.
Real example: a local file-based search engine (Lucene + file locking) posed an index
corruption risk under a multi-instance configuration (multiple ECS tasks + shared storage),
which required an application change — migrating to a managed search service (OpenSearch).
Deployment design is out of scope for this flow, but it's worth understanding during the
analysis phase **whether multi-instance operation is feasible** (i.e., whether local state,
file locking, or in-memory caching are present).
