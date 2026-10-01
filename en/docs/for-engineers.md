# For Engineers

For the thinking see [concepts.md](concepts.md); for how to use it see [how-to-use.md](how-to-use.md).
This document explains the internal design: the boundaries of the three layers, the knowledge system,
and how the gates are implemented.

---

## 1. Three-line summary

- A three-layer framework for having AI agents execute legacy migrations. It consists of a methodology (Method), domain knowledge (Playbook) and AI execution discipline (Harness)
- It does not depend on a particular tool. It does not have platform infrastructure such as a graph DB or vector DB, and does not require one of the user
- The rules we want the agent to keep are checked mechanically by `verify.sh` (an executable script) and git

## 2. The three layers and their reuse boundaries

| Layer | Directory | What lives there | On a new domain |
|------|------------|-----------|----------------|
| Method | `method/` | The Phase 0-4 flow, the common analysis procedure, common practices `CP-N` | Used as-is |
| Playbook | `playbooks/<domain>/` | Domain knowledge `DP-N`, analysis viewpoints, verify examples, reference, transform-config | Created new |
| Harness | `harness/` | Core discipline, skills, templates, the verify.sh scaffold | Used as-is |

What enters a single project is only the common part plus one Playbook.
That is why `DP-N` numbers may repeat across Playbooks. For example clang's DP-3 and java's DP-3 are
unrelated.

### Inside the Harness (the ladder of execution discipline)

```
harness/
├── core/migration-core.md     ← always loaded. Keep it thin (only the skeleton of judgment)
├── skills/migration-*/        ← loaded on demand (SKILL.md format)
│   ├── migration-recording          recording formats
│   ├── migration-troubleshooting    hypothesis log and confirming root cause
│   ├── migration-adr                ADR drafts, exclusion flow, Phase gates
│   ├── migration-adversarial-review independent verification (completion declaration / HOLD-1 only)
│   ├── migration-verification       operating the verification gates
│   ├── migration-session            session start/end
│   ├── migration-subtask            subtask procedure
│   └── migration-tree-setup         creating the modernized tree, two-repository operation
├── templates/                 ← project scaffolding
├── tools/                     ← recording tools and the declaration guard called from hooks (enabled by default)
├── setup-modernized.sh        ← creating the modernized tree
└── verify.sh.template         ← the substance of mechanical enforcement
```

From the top of the tree down, the layers run from always loaded, through on demand, to mechanically
enforced.
The more a rule must be enforced, the lower the layer it is placed in. A constraint merely written in
a prompt is not assumed to be kept.

## 3. The knowledge system (CP / DP / LL / ADR)

The meaning of each ID and its location in the workspace is explained in section 4 of
[how-to-use.md](how-to-use.md).
On the framework side, the source of truth is `method/practices-common.md` for `CP-N` and
`playbooks/<domain>/practices.md` for `DP-N`.

### Separation of numbering authority

Only the framework itself may assign an unprefixed `CP-N` or `DP-N`. In a Playbook you create
yourself, that Playbook's author assigns them.
A project appends in the `CP-<project>-N` / `DP-<project>-N` namespace and feeds it back to the
framework on completion.
Feedback into the framework itself is proposed as an issue or a PR ([CONTRIBUTING.md](../../CONTRIBUTING.md)). Gaps are preserved and never reused.

This rule is a countermeasure against a real incident. A running project assigned its own `DP-5`,
which collided with a differently-contented `DP-5` in the Playbook itself.

### Three-stage promotion

```
LL-N (project-specific)
  → judged usable on other projects in the same domain → DP-<project>-N
    → fed back on completion → DP-N (unprefixed, assigned by the Playbook's author)
```

If you hit the same lesson on another project too, that lesson is no longer treated as
project-specific.

### Reading granularity

By default an agent reads only the Summary table of each knowledge file. The body is opened when the
work on the relevant theme begins.
The body is the layer humans read to understand, so it may be written in detail, including examples
and anti-patterns.

Likewise, an agent does not read `worklog.md` through chronologically. That is because the worklog is
append-only and keeps growing.
The previous state is grasped from `session-context.md`.

### Quantitative discipline

A rule written in prose relies on the agent's self-report, so it slips through unkept.
For that reason the volume of knowledge is capped by numbers and checked with
`./verify.sh knowledge`.

| Target | Default | When exceeded |
|------|------|-------|
| One summary row | 300 bytes | If it does not fit in one line, move it to the body |
| One entry's body | 80 lines | Split the detail into `reference/`, leaving the essentials and a pointer in the body |
| Entries per file | 15 | Consider consolidating. If you do not, recording the reason as `KNOWLEDGE-REVIEWED` lets it pass |

## 4. How quality is assured

This framework does not assume that what the AI produced is correct.
The three layers in 4.1 to 4.3 make the produced output verifiable, and 4.4 decides the assignment of
the models that carry out that verification.

### 4.1 Formal soundness (verify.sh)

`verify.sh` consists of eight gates. Each gate can be run individually as `./verify.sh <name>`.

| # | Gate | What it checks | When it applies |
|---|--------|---------|---------|
| 1 | build | Do the artifacts in the expected list exist (CP-7) | After the work-plan is confirmed |
| 2 | smoke | Startup and basic operation | Same |
| 3 | integration | Integration / E2E. With `REQUIRE_GOLDEN_PATH=1`, a golden-path E2E is mandatory | Same |
| 4 | nonfunc | Non-functional (opt-in) | Same, and when `RUN_NONFUNC=1` |
| 5 | repo-sync | Uncommitted sync across both repos / unrecorded dirty / leftover `DIAG-`, `STUB-` / commit-time divergence | Always |
| 6 | knowledge | Volume of the knowledge files | Always |
| 7 | adaptation | Adaptation ledger (coverage baseline definition, presence of evidence, exclusion reasons, unaddressed count, negative-test records) | Always |
| 8 | project | Provenance of project information. Whether any `⟨inferred⟩` (an AI-inferred value) survives after the work-plan is confirmed | Always |

Gate applicability is switched by a machine-readable marker written in `work-plan.md`.

```
<!-- WORK-PLAN-STATUS: DRAFT     -->  → gates 1-4 are "not applicable" and exit 0
<!-- WORK-PLAN-STATUS: CONFIRMED -->  → they apply for real; an empty expected list FAILs build
```

With this, the gates 1-4 do not FAIL when you finish with the assessment alone.
After the work-plan is confirmed, the build gate detects an artifact that was forgotten in the
expected list.

### 4.2 The coverage baseline (expected list and adaptation ledger)

Whether something was covered is judged by a baseline that can be counted before the work, and judged
by that baseline.
The qualitative judgment "we looked at the main parts" is not used.

| Target | Coverage baseline | Substance |
|------|-----------|------|
| Artifacts | Expected list | `EXPECTED_ARTIFACTS` in `verify.sh`. All of them registered when the work-plan is confirmed (CP-7) |
| Behaviour | Adaptation ledger | `01-plan/adaptation-ledger.md`, with dispositions |

The adaptation ledger's dispositions are the four kinds `addressed` / `replaced` / `not_required`
(reason required) / `unaddressed`.
Driving the `unaddressed` count to zero becomes a Phase 4 completion condition.

The adaptation ledger's coverage baseline uses, from the Playbook's perspective table
(`analysis-appendix.md`), the perspectives that apply to the target system.
One ledger row corresponds to one perspective. The number of hits from scanning the code is not made
the coverage baseline.
The count for each perspective is obtained during the migration work by running each perspective's
detector. The reason is written in CP-11 of `practices-common.md`.

The expected list counts whether the artifacts that should exist are all present. However, it cannot
detect a site inside an existing artifact that was forgotten.
The adaptation ledger makes up for that detection gap.

### 4.3 Content accuracy (detector negative tests, and a narrowly scoped independent verification)

What `verify.sh` assures is the form. Whether a test can really discriminate the truth of a claim is
assured by a different mechanism.
The default means is a mechanical check.

| Target | Treatment | Pass condition |
|------|------|---------|
| Every perspective's detector | Negative test (CP-13) | Break the detector, confirm EXIT != 0, and record it. Re-runnable |
| Completion declaration / HOLD-1 feature exclusion (irreversible) | Independent verification (an AI with separate context) | It runs once. The findings are opened in the ledger and closed with a disposition. Re-verification is done with verify.sh and the negative tests. A feature exclusion is verified lightly, one item at a time |
| Confirming the work-plan (Phase 2→3) | Does not apply | Work-plan rows can be changed in Phase 3. A planning error is detectable by the build and the golden-path E2E |

A negative test measures the detection power of a detector. Deliberately create the state that should
be detected, and confirm the detector returns EXIT != 0.
The checklist for which perspective to doubt is in CP-13.

The most important thing in an independent verification is isolating the verifying AI's context from
the producing side. Separating role names alone is not enough.
The AI attempting the refutation is given only the declaration under test and the location of the
primary sources, not the producing side's reasoning or worklog.
There are two lenses to the verification. One is lost functionality: independently search for stubs
and disabling, and take the difference set between the ledger and the implementation.
The other is scope: confirm that items that disappeared from the success criteria are approved.

Independent verification runs exactly once. The subject of the verification is limited to the
modernized tree and its runtime behaviour.
The format of the ledger, the placement of ADRs, and defects in `verify.sh` itself are not made
findings.
That is because a metric where findings grow the more the records grow cannot be used for a
completion judgment.
The operational detail is in `skills/migration-adversarial-review`.

### 4.4 Model assignment (split by judgment vs. volume)

Model assignment is decided by whether the dominant property of the work is judgment or volume.
The distinction of sub-agent vs. main agent is not the basis for assignment.

| Target | Dominant property | Assignment |
|------|------------|---------|
| Tier 0 (implementation, builds, tests, investigation inside the work-plan) | Volume | A faster model is fine |
| Tier 1 (worklog, records, commits, translation, transcribing ledger rows) | Volume | A faster model is recommended |
| Tier 2 (HOLD), ADR decisions, HOLD-1 exclusions, confirming the work-plan, independent verification, designing negative tests | Judgment | Keep the stronger model |

A sub-agent doing an independent verification is exercising judgment. Even when it is a delegate
sub-agent, it must not be switched to a lighter model.

## 5. Mechanical detection of unintended loss of functionality

The hardest thing to find in a migration is a symptomless defect where no exception appears, HTTP 200
is returned, and the screen is blank.
The build, unit and smoke tests only confirm that it starts without an exception, so they cannot
detect this defect.

This framework detects this defect by four mechanisms.

1. Making the `// STUB-<id>:` marker mandatory: attach this marker to a temporary stub, mock or disabling.
   If a marker survives into committed code, `repo-sync` returns FAIL (the same mechanism as `// DIAG-<id>:`)
2. A forbidden-pattern gate: it detects patterns such as `not implemented`. The pattern definitions differ by language and framework, so they are placed in the Playbook layer.
   The scan subject is limited to implementation sources so that mocks for tests are not false positives
3. Making the golden-path E2E mandatory: when `REQUIRE_GOLDEN_PATH=1`, if the golden-path E2E is unregistered, the integration gate returns FAIL
4. Reconciliation with the adaptation ledger: if a feature is gone, its corresponding row does not become `addressed`, so it appears as an unaddressed count

## 6. Interruption resilience

In a long migration, session breaks inevitably occur. In a design that imposes the recording
obligation at work completion, the content of an investigation interrupted partway is lost.

For that reason, before making the first change, the AI writes a one-line declaration into
`session-context.md` in the form `- **This turn (<time>):** …`.
This at-start declaration is enforced by the `preToolUse` hook. This enforcement is enabled by default
(for detail see [../harness/README.md](../harness/README.md)).

Also, state is never left only in the uncommitted working tree. With small `[wip]` or `[diag]`
commits, the `// DIAG-<id>:` marker, and the working-tree ledger in `session-context.md`, the state is
left on the git side too.
If there is an unrecorded uncommitted change, `repo-sync` returns FAIL, so it does not depend on
whether a human notices.

## 7. Multiple repositories

This framework also supports the case where one system consists of multiple repositories.

Phase 0a starts from a repository inventory. The inventory does not rely on the presence of `.git`
alone but also detects build roots.
Analysis runs once per repository (CCA = ATX's `AWS/comprehensive-codebase-analysis`), in parallel
across repositories.
The unit of parallelism is the git work tree. ATX runs `git checkout -b` in the target repository, so
it cannot run in parallel within the same work tree.
To split one repository and analyse in parallel, prepare a separate work tree with `git worktree` or a
clone.

The progress state of the analysis is recorded only in the run ledger `analysis-runs.md`.
One modernized tree is also created per repository, and all of them are listed in `MODERNIZED_TREES`
in `verify.sh`.
A single-repository configuration is handled by the same procedure, as the case where the number of
repositories is one, with no dedicated branching.

## 8. Tool support

| Tool | Core discipline | skills |
|--------|---------|--------|
| Kiro (CLI/IDE) | `.kiro/steering/` | `.kiro/skills/` (auto-recognized) |
| Claude Code | `CLAUDE.md` | `.claude/skills/` (Agent Skills) |
| Others | Copy the core into each tool's rule file | Point at skills as reference documents |

This framework works completely even in an environment with just a single agent working sequentially.
Parallel execution and independent verification are options for raising efficiency or the strength of
verification.
In an environment where these cannot be used, it degrades gradually to verification in a separate
session, and then to a human sign-off.

## 9. What this framework does not take on

| Area | Why |
|------|------|
| Designing and building the deployment environment | Treated as a follow-on task after Phase 4. It always arises in a real migration, though, and target-environment constraints can require application changes |
| Guardrails for cloud operations | Work within a single host is assumed. IAM boundaries and Policy as Code are set up separately |
| Performance, leaks, fault tolerance, security | Out of scope by default. Phase 1 decides them explicitly as an ADR |
| Whether production-like data may be used | Always left to human judgment (Tier 2) |

## 10. Terminology

The list of terms is in section 11 of [how-to-use.md](how-to-use.md).

## References

- The thinking behind it: [concepts.md](concepts.md)
- How to use it: [how-to-use.md](how-to-use.md)
- Adding a new domain: [authoring-playbook.md](authoring-playbook.md)
- The formal definition of the flow: [../method/flow.md](../method/flow.md)
