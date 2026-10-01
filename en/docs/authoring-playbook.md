# Applying It to a New Migration Domain (creating a Playbook)

When supporting a new migration domain, adding one Playbook is enough.
The Method layer (`method/`) and the Harness layer (`harness/`) are not changed.

---

## What the Playbook layer is (read before creating one)

A Playbook is where knowledge that only holds in that domain lives.
If you write a domain-specific marker into the generic side (Method / Harness), the procedure stops
working on targets that do not use that marker.

Judge whether something goes in the Playbook or in Method / Harness by the following table.

| This goes in the Playbook | This goes in Method / Harness |
|-------------------|-------------------------|
| A concrete build command such as `mvn clean install -DskipTests` | The principle "the verification command includes compiling the test code" |
| A configuration key such as `struts.allowlist.packageNames` | The principle "a change in a security default produces a silent failure" |
| Forbidden patterns such as `#if 0` / `UnsupportedOperationException` | The mechanism "detect unintended stubbing mechanically" |
| A table of API differences between Solaris and Linux | The procedure "produce an environment diff table" |
| A route-specific trap such as "switching to this type makes the validation attribute lapse as a silent failure" | The principle "hold the perspectives the build stays silent about or misleads you on" (CP-11) |

Do not write a concrete name into the generic side. In another framework there was a real case of
writing a specific annotation name into a generic procedure document.
As a result, on targets that did not use that annotation the coverage denominator became zero, and the
reconciliation could not be computed.

## Procedure

### 1. Create the directory

Create the Playbook's directory with the same structure as an existing Playbook.
The location is arbitrary and can be specified with `install.sh --playbook <path>`. To take it into
the framework itself, place it at `ja/playbooks/<new-domain>/`.
Name the domain so that the migration source and migration target are visible (e.g.
`clang-solarisx86-to-amznlinux`, `java-modernization`).

| File | Content | Required |
|---------|------|------|
| `README.md` | Domain overview and structure | Required |
| `practices.md` | Knowledge collection (`DP-N`; an empty summary table is fine) | Required |
| `analysis-appendix.md` | The perspective table (the source of the adaptation ledger's coverage baseline; see "How to write the perspective table" below) + where changelog investigation pays off | Required |
| `baseline-themes.md` | Test patterns for behaviour that tends to break in this domain | Required |
| `verify-snippets.md` | Per-gate implementation examples by language, forbidden-pattern definitions, golden-path E2E examples | Required |
| `modernized-gitignore.template` | Ignore patterns for build output (e.g. for Java, `target/`, `*.class`) | Required |
| `transform-config-cca-template.yaml` | Config for the structural analysis (`AWS/comprehensive-codebase-analysis`) | Required |
| `reference/` | Domain knowledge (difference lists, considerations) | Optional |

### 2. Write the transform-config

Keep `additionalPlanContext` within ATX's limit of 4096 bytes. Exceeding the limit makes the analysis
impossible to run. After writing it, always check the byte count with the following command.

```bash
python3 -c "
import yaml
c = yaml.safe_load(open('<playbook-dir>/transform-config-cca-template.yaml'))['additionalPlanContext']
print(len(c.encode()), 'bytes')"
```

Make the config something that can be analysed even when the target is undecided. When the goal column
is empty, do not make ATX assume a goal.
Instead, include viewpoints that additionally report an inventory of the current stack and an
enumeration of viable migration targets (LTS, scale of breaking changes, compatibility chain).
The migration policy is decided by the user as an ADR in Phase 0b.

If the Japanese version does not fit in 4096 bytes, shorten the wording. The existing clang Playbook
fits in 3990 bytes using an abbreviated style.

### 3. Write verify-snippets

In `verify-snippets.md`, place snippets for implementing each `verify.sh` gate in this domain. At
minimum, provide the following snippets.

- Example expected artifacts for the build gate (executable / `.so` / `.jar` / `.war` etc.)
- Smoke gate implementation examples (for a CLI, `--help` with rc=0; for a daemon, staying alive a few seconds; for a server, responding on its port)
- Integration gate implementation examples
- Forbidden-pattern definitions (`FORBIDDEN_PATTERNS` and `FORBIDDEN_SCAN_PATHS`)
- Golden-path E2E (for UI-rendering apps, `REQUIRE_GOLDEN_PATH=1` is recommended)
- Examples of `MODERNIZED_TREES` and `DIAG_SCAN_PATHS` for a multi-repository setup

For the forbidden patterns, also write a caution about false positives. For example `mock` is a
legitimate expression in test code, so the scan subject must be limited to implementation sources.

### 4. Numbering in practices.md

An unprefixed `DP-N` is assigned by the Playbook's author. A project uses `DP-<project>-N`.
A new Playbook starts at `DP-1`. Since only one Playbook enters a single project, `DP-N` numbers may
overlap with other Playbooks.

The summary table may start empty and be appended to as you work.
The volume limits (300 bytes per summary row / 80 body lines / 15 entries) are checked by
`./verify.sh knowledge`.

### 5. To take it into the framework itself: register it for i18n and create the English version

In a Playbook for your own use, this step is unnecessary. Do it only when taking it into the framework
itself.
Translation is the maintainers' responsibility (see [CONTRIBUTING.md](../../CONTRIBUTING.md)).

The source of truth for translation is `ja/`, and `en/` is generated from `ja/`. Always register new
files in the manifest.

```bash
# Add one line per file to tools/i18n-manifest.tsv
# Format: <path relative to ja/> <TAB> <target relative to repo root> <TAB> class <TAB> flags
#   class: translate (whole file) / translate-comments (comments only) / copy (verbatim)
```

Once registered, run the following commands.

```bash
./tools/check-i18n.sh          # shows what is out of sync
./tools/build-en.sh            # lists the files to translate plus the glossary
# → create the en/ side (an AI agent may do this)
./tools/build-en.sh --stamp playbooks/<new-domain>/practices.md
./tools/check-i18n.sh          # confirm PASS
```

Edit `ja/` and `en/` together. Updating only `ja/` makes the content installed by
`install.sh --lang en` disagree with its procedure documents.
Also, the check of whether the shared anchors (`CP-N` / `DP-N` / `HOLD-N`) correspond 1:1 between
Japanese and English FAILs.

Keep terminology consistent via `tools/glossary.tsv`. When you introduce a new term, add it to this
file.

### 6. Use it

```bash
./sample-ai-modernization-flow/install.sh --project myapp --playbook <new-domain>      # when it is in the framework's playbooks/
./sample-ai-modernization-flow/install.sh --project myapp --playbook /path/to/playbook  # when placed in an arbitrary location
```

## How to write the perspective table (`analysis-appendix.md`)

The perspective table is the highest-value deliverable in a Playbook. The adaptation ledger's coverage
baseline is selected from the perspective table (CP-11).
`install.sh` installs the perspective table into the project as `00-analysis/analysis-appendix.md`.

### The two kinds of perspective to put in the perspective table

| Kind | How the toolchain reacts | In the table? |
|------|-------------------|-----------------|
| ① It enforces | The build fails and enumerates the places to fix | Not included (not selected for the coverage baseline; the build produces the same list in seconds) |
| ② It stays silent | The build succeeds; it breaks only at run time or in production | Included |
| ③ It misleads | The build fails, but a straightforward fix causes a defect elsewhere | Included first |

Selecting ① for the coverage baseline increases only the ledger's row count with rows that match
nothing, and makes it easy to mistake it for having achieved coverage.
Namespace replacement, project file format changes and API renames are ①.
You may keep ① rows for reference during analysis, but in that case write ① in the `Kind` column and
exclude them from the coverage baseline.

③ has the highest value. Whoever fixed it judges completion on the grounds of a successful build, so
if it is not written in the perspective table nobody notices the problem.
The typical shapes of ③ are the following three.

- Swapping a type makes an `is`/`instanceof`-equivalent pattern stop matching, so execution falls into the branch that returns the default
- A registration routine that uses an old-framework-only type compiles once you delete the whole file. But the deletion also loses cross-cutting concerns such as authorization, auditing and transaction boundaries
- An old API has no equivalent substitute, and the straightforward substitute is destructive (it deletes data, recreates the schema, etc.)

### The table format (the detection command is mandatory)

```markdown
| ID | Perspective | Kind | Detection command | Reference |
|----|------|------|------------|------|
| MP-1 | <state it in one line> | ③ | `<one re-runnable command>` | DP-3, reference/xxx.md §2 |
```

In the `ID` column, write `MP-N` (Migration Perspective). Adaptation-ledger rows reference this ID, so
the numbers are not reassigned.
In the `Kind` column, write ① / ② / ③. What is selected for the coverage baseline is ② and ③.
In the `Reference` column, write the section of `reference/` that is the grounds, and the `DP-N` in
`practices.md` that writes the remedy. Do not duplicate the body.

The `Detection command` column is mandatory for ② and ③. That is because explanatory text alone cannot
surface the full set of applicable sites.
For example, even if you know "the migration target is case-sensitive", without a detector the
reference-path mismatches are always reported as zero.
In that state, the mismatches are not found even as the work proceeds.

"The observation that lets you call it correct" (CP-4) and the negative test (CP-13) contain code, so
they do not go in the table but in `verify-snippets.md`.
Provide, per perspective, one gate implementation example and one negative-test procedure.
Perspectives where a defect occurs only at run time and is detected by a test go in
`baseline-themes.md`.

### Grow the perspective table across projects

A perspective newly found during a project must not end with that project's records alone; always
return it to the perspective table.
Perspectives are an asset fixed per migration route, so they accumulate the more projects you do.
A method that makes a scan hit count the coverage baseline cannot accumulate in this way (CP-11, "Why
a scan hit count is not made the coverage baseline").

## Updating an existing Playbook

A Playbook is something you grow while doing project after project.
There are two triggers for an update. One is when returning a perspective or knowledge newly found on
a project. The other is when revising the Playbook itself, such as supporting a new version of the
migration target.

### What to add and where to add it

| What you gained | Where to add it |
|---------|-------|
| A newly found perspective (a site where the build stays silent or misleads you) | Add `MP-N` to the perspective table in `analysis-appendix.md` |
| A standard pattern for a remedy | Add `DP-N` to `practices.md` |
| A perspective's detector and negative test | `verify-snippets.md` |
| Test patterns for behaviour where a defect occurs only at run time | `baseline-themes.md` |
| Grounds such as a difference list | `reference/` |

`MP-N` and `DP-N` are not reassigned. Because they are referenced from the ledger and ADRs, a number
that is no longer needed is left as a gap.
If a tool improvement turns a perspective into ①, do not delete the row; change the `Kind` to ①.
When taking in a project's `DP-<project>-N`, assign a new unprefixed number and write the origin in
the body.
If entries exceed the limit of 15, consider consolidating. If you change the transform-config,
re-confirm that it fits within 4096 bytes.

### Reflecting it into a running project

```bash
./sample-ai-modernization-flow/install.sh --update-project <records repository> --playbook <name|path>
```

`practices.md`, `analysis-appendix.md`, `baseline-themes.md` and `verify-snippets.md` are also
appended to on the project side, so they are not overwritten.
Their new versions are placed in `.flow-update-<version>/`, so merge them by hand and then delete
`.flow-update-<version>/`.
`reference/`, the transform-config and the gitignore template are overwritten.
If `--playbook` is omitted, the Playbook's files are not updated.

## Deciding not to create a Playbook (important)

If an existing Playbook suffices, do not create a new Playbook. The rule of thumb for the judgment is
the following table.

| Situation | Decision |
|------|------|
| A different product on the same language and same framework generation | Use the existing Playbook. Append what you learn to the existing `practices.md` |
| Same language but a different kind of migration (e.g. a version bump vs. replacement with a different FW) | Add `DP-N` to the existing Playbook and see. Split once the knowledge clearly diverges |
| A different language or execution platform | Create a new one |

The framework works even without specifying a Playbook. If `--playbook` is omitted and there is
exactly one Playbook in `playbooks/`, it is selected automatically.
There are currently multiple Playbooks, so to use one, specify it with `--playbook`.
A migration can proceed with Method and Harness alone even without domain knowledge.
However, the analysis viewpoints and the verification implementation examples will be fewer, so keep
adding what you learn to `practices.md` each time.

## References

- The three layers and reuse boundaries: [for-engineers.md](for-engineers.md)
- Existing Playbooks: `../playbooks/clang-solarisx86-to-amznlinux/`, `../playbooks/java-modernization/`, `../playbooks/dotnetfw-to-modern-dotnet/`
