# Analysis Perspectives Appendix — Java Modernization

A collection of perspectives specific to this domain, supplementing the Method's common analysis procedure (analysis-procedure.md).

**The "Perspective Table" below is the source of the adaptation ledger's coverage baseline** (CP-11).
Pick the applicable perspectives in Phase 0b, prepare a detection command and a negative test in
Phase 2, and obtain the counts in Phase 3 by running the detectors.
`install.sh` installs this file as `00-analysis/analysis-appendix.md`.
It also serves as the input to Phase 0b's 0b-1 (environment differences table) and Phase 1's
1-1 (changelog investigation).

For how to write it see [docs/authoring-playbook.md](../../docs/authoring-playbook.md),
"How to write the perspective table".

## Perspective Table (the source of the coverage baseline)

**Kind**: ② the build succeeds and it breaks only at run time or in production / ③ the build fails but
the straightforward fix breaks something else. ① (the build enumerates the places to fix) is not selected
for the coverage baseline — those live under "Analysis Inputs" below.

| ID | Perspective | Kind | Detection command | Reference |
|----|-------------|------|-------------------|-----------|
| MP-1 | **`javax.*` references in configuration and templates** are never flagged by the compiler during a namespace migration (references in Java code are ①, but strings in XML/JSP/TLD/properties are never flagged, stay behind and fail to resolve at run time) | ② | `grep -rEl 'javax\.(servlet\|persistence\|validation\|mail\|annotation)' --include='*.xml' --include='*.jsp' --include='*.tld' --include='*.properties' .` | — |
| MP-2 | **A change in security defaults makes a page symptomlessly empty** (an OGNL allowlist, parameter binding or CSRF returns empty rather than raising) | ② | `./verify.sh integration` (non-empty assertions; the test patterns are in baseline-themes.md) | DP-2, DP-3 |
| MP-3 | **Server-side formatting and case conversion resolve against the JVM default locale** (formatting or comparison without a `Locale` changes result by environment) | ② | `grep -rnE '(String\.format\|toLowerCase\(\)\|toUpperCase\(\)\|new SimpleDateFormat\(\|new DecimalFormat\()' --include='*.java' src/ \| grep -v Locale` | DP-4 |
| MP-4 | **A mismatch between the servlet container's EE level and the artifacts** (e.g. Jetty 12 separates artifacts across EE8/9/10; picking the wrong one fails at startup or on the first request) | ② | Reconcile `mvn -q dependency:tree \| grep -E 'jakarta\.\|javax\.'` with the container's EE level | — |
| MP-5 | **Classes removed by a CSS framework's major version become inert as a silent failure** (the layout breaks while HTTP 200 is returned) | ② | `grep -rnE 'class="[^"]*\b(btn-default\|pull-left\|pull-right\|hidden)\b' --include='*.jsp' --include='*.html' .` | DP-4 |
| MP-6 | **The test execution locale is not pinned**, so whether tests pass becomes machine-dependent | ② | `grep -nE 'user\.language\|user\.country' pom.xml .mvn/jvm.config 2>/dev/null` (empty means unpinned) | DP-4 |
| MP-7 | **A change in the element IDs a framework tag generates** detaches the E2E selectors as a silent failure (some implementations simply go green when the element is not found) | ② | Reconcile `grep -rnE 'By\.id\(\|#[a-zA-Z0-9_]+' --include='*.java' src/test/` with the generated HTML before and after | DP-4 |

**"The observation that lets you call it correct" (CP-4) and "the negative test" (CP-13) live in
[verify-snippets.md](verify-snippets.md).** For perspectives whose detection method is a test, see
[baseline-themes.md](baseline-themes.md).

## Analysis Inputs (not selected for the coverage baseline)

Perspectives the build enumerates (①), plus material for deciding the target. Do not open ledger rows for these.

| Perspective | Kind | Content | How to verify |
|-------------|------|---------|---------------|
| JDK version and EOL | Decision material | Current/target LTS status (e.g., Oracle Java 21 Premier Support runs until September 2028) | Each vendor's support roadmap |
| Framework compatibility chain | Decision material | Whether chains such as "Struts 7.x requires Jakarta EE 10" or "Spring Security 6.x requires Spring 6.x" are consistent (CP-10) | Requirements in each official document |
| `javax` → `jakarta` (Java code) | ① | Impact of migrating to Jakarta EE 9+. **The compiler enumerates every site** | Do not count in advance. If you need a sense of scale: `grep -rl "javax.servlet" src/main/ \| wc -l` |
| Renames of framework-specific APIs | ① | Dependencies on internal packages (e.g., `com.opensymphony.xwork2` → `org.apache.struts2`) | Same. Compile errors produce the accurate list |
| Build / test environment | Decision material | JAVA_HOME, the Maven path | Verify on the real machine (state it in test-procedures.md) |

## Items to Include in the Environment Differences Table (0b-1)

From the perspective table and the analysis inputs above, expand **those that carry concrete source and
target values** into the "Domain-specific difference perspectives" section of
`01-plan/environment-diff-table.md` (JDK API incompatibilities, GC/JVM option differences, the
container's EE level, the CSS framework version).

## Priorities for Changelog Investigation (1-1)

- **Cover the official migration guides first (CP-9).** A multi-step major-version jump has multiple
  guides, one per version boundary (e.g., Struts 2.5→6.0 and 6.x→7.x)
- Spring Framework / Spring Security (major versions change XML configuration, APIs and defaults substantially)
- The logging facade (SLF4J 1.x→2.x changes the binding mechanism)
- Duplicate or inconsistent dependencies (a mismatch between the parent POM's version property and an individual override)

## Notes on Analysis

- **Estimate the migration cost as the total number of breaking changes × the number of affected files**
  (CP-10). Use it as the material for deciding between a staged rollout (one version at a time) and a
  single-shot one
- For candidate removals of legacy protocols (XML-RPC, OAuth 1.0, etc.), check actual usage and the
  alternatives, then ask for a user decision through HOLD-1 (the feature exclusion flow)
- Check at this stage whether existing test assets (unit / E2E) exist and can be run (the baseline Mode C (reuse the existing tests)
  decision). If E2E exists, count migrating the test infrastructure (container plugins, WebDriver,
  headless setup) as a Step in the work-plan
- **Return newly encountered perspectives to the perspective table** (CP-11). Do not let them end with the project
