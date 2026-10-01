# Playbook: Java Modernization

A **Playbook (mid-tier, practical-document layer)** for migrating legacy Java applications
(Java 8/11, the javax namespace, older-generation frameworks) to a modern stack
(Java 21 LTS, Jakarta EE, current frameworks).

> For the flow (Phase 0-4), the three exit points and the decisions the user must make, see
> `../../method/flow.md`. For AI execution discipline, see `../../harness/`. Setup is done via
> `install.sh` at the repository root.

## Characteristics of this domain (differences from the clang-solarisx86-to-amznlinux Playbook)

- **Silent failure is the primary failure mode**: due to frameworks' hardened security defaults,
  failures that "go empty / fail to fire" without raising an exception are common
  (undetectable by compilation or unit tests — E2E tests are essential)
- **Existing test assets often already exist**: for the baseline, Mode C (reuse the existing tests;
  modernizing existing unit/E2E tests) is the first candidate. Budget the migration of the test
  infrastructure itself into the work-plan

## Structure

| File | Content | Copy destination in the project |
|---------|------|------------------------|
| `practices.md` | Collection of practices for the Java domain (DP-1 onward) | `docs/knowledge/practices.md` |
| `analysis-appendix.md` | Domain-specific analysis viewpoints (EOL/compatibility matrix, namespace impact count) | `00-analysis/analysis-appendix.md` |
| `baseline-themes.md` | Test patterns for behaviors that tend to break in this domain (silent failures, CSRF, etc.) | `02-test/baseline-themes.md` |
| `verify-snippets.md` | Java/Maven implementation examples for each verify.sh gate | `02-test/verify-snippets.md` |
| `modernized-gitignore.template` | Ignore patterns for build artifacts (target/, *.class, etc.) | Records repository root |
| `transform-config-cca-template.yaml` | AWS Transform custom (ATX) structural analysis (CCA) configuration | `00-analysis/transform-config-cca-template.yaml` (in 0a-4, use it as the basis to create `00-analysis/<repo-id>/transform-config-cca.yaml`) |
| `reference/java-modernization-considerations.md` | Collection of considerations for framework migration | `docs/reference/` |

## Quick Start

```bash
cd /path/to/workspace
/path/to/sample-ai-modernization-flow/install.sh --project <product-version> \
    --playbook java-modernization
```

## Distinctive discussion points in this domain

- **Multi-stage major jumps**: for migrations like Struts 2.5→7.1, multiple official guides exist,
  one per version boundary (CP-9). Extracting breaking changes up front is the highest priority
- **javax → jakarta namespace migration**: quantify the number of affected files up front
  (see analysis-appendix)
- **Silent failures from security default changes**: OGNL allowlists, mandatory
  parameter-binding annotations, CSRF, etc. (see DP-2, baseline-themes)
- **Verification commands must include test-compile**: `mvn clean install -DskipTests` (DP-1)
- **UI framework migration** (when accompanied by major updates such as Bootstrap): changes to
  modals, layout, and generated element IDs can only be detected via E2E

## Information to include in instructions

| Item | Example |
|------|---|
| Source code path | `/path/to/<product>/` |
| Current stack (example) | Java 8/11, Struts 2.x, Spring Framework 5.x, javax namespace, Bootstrap 3/4 |
| Target stack (example) | Java 17/21 LTS, Struts 6.x/7.x, Spring Framework 6.x, Jakarta EE 10, Bootstrap 5 |
| Build command | `mvn clean install -DskipTests` (including the JAVA_HOME setting) |
| How to run tests | `mvn test` / whether an E2E module exists (e.g., `mvn verify -pl it-selenium`) |
| Constraints (if any) | Legacy features that may be removed (e.g., XML-RPC), protocols that must be preserved |

## Real-world Example (measured on a public sample)

- Measured on a public sample (the OSS Apache Roller blog server) (Java 11→21, Struts 2.x→7.x,
  Bootstrap 3→5, introduction of Spring Security CSRF): carried out before the flow was applied.
  The practices and theme collection in this Playbook were extracted from the lessons-learned of
  this measurement
