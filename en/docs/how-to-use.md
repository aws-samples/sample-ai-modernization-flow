# How to Use

This document explains, for users, how to use the framework from setup to migration completion,
together with what actually happens at each stage.
For the thinking see [concepts.md](concepts.md); for the internal design see
[for-engineers.md](for-engineers.md).

---

## 1. The whole picture in 30 seconds

When you say "Starting the assessment of <source path>. Begin from Phase 0a", the AI starts with a
startup interview.
In the startup interview, the AI scans the source to fill in the items it can tell, and asks once, in
one batch, only for the items it is missing. After that it proceeds in the following order.

| Phase | What happens |
|-------|------------|
| 0a | Repository inventory → ATX analysis (structure, technical debt) → HTML output of the results |
| 0b | Cross-repo integration → organizing target candidates → migration policy decided as an ADR |
| 1-2 | Capture the baseline → decide the non-functional scope → confirm the work-plan |
| 3 | Implement per Step → `./verify.sh` all-PASS at each Step → commit |
| 4 | Verify all modules → unaddressed count in the ledger reaches zero → negative tests → independent verification → done |

You can also finish at the point of Phase 0a (the analysis results) or Phase 0b (material for the
go/no-go decision) (section 10).

All you need to start is two things: the path of the target source, and what must not be changed.
The target technology stack may stay undecided; it is decided in Phase 0b after seeing the analysis
results.

## 2. Three trees and one records repository

The following directories line up in the workspace. The AI agent is launched at the workspace root.
For Kiro, launch it with `kiro-cli chat --agent migration` (section 8).

```
<workspace>/                      ← launch the AI agent here
├── .kiro/steering/               ← core discipline + project-specific information
├── CLAUDE.md                     ← for Claude Code (same content)
├── myapp/                        ← source tree (read only; its content is not changed)
├── myapp-modernized/             ← modernized tree (created in Phase 3 Step 1)
└── myapp-migration-20260901/     ← records repository (plans, records, verification)
```

| Tree | Role | Who changes it |
|--------|------|--------------|
| Source tree | The current code. Reference only | Nobody changes the content of the code (only `git init` and the working branch ATX creates are permitted) |
| Modernized tree | The migrated code | The AI writes code here |
| Records repository | Plans, records, verification gates | The AI writes records; you read them here |

The reason code and records are split into separate repositories is to detect mechanically a state
where only one side was committed and the other was left uncommitted.
Detection uses `./verify.sh repo-sync`.

If one system consists of multiple repositories, the source tree and the modernized tree line up per
repository.
The records repository stays a single one.

## 3. The files you touch

Install creates many files, but what you read and write is a very small part.

| File | Your involvement |
|---------|------------|
| `.kiro/steering/migration-project.md` (for Claude Code, `CLAUDE.md`) | The AI fills it in during the startup interview. You only answer the questions |
| `01-plan/work-plan.md` | You approve it in Phase 2 (the AI writes the content) |
| `01-plan/adaptation-ledger.md` | The adaptation ledger. You look at it when judging an exclusion |
| `docs/decisions/decisions.md` | You approve ADRs. "Why it was done" is recorded in this file |
| `03-worklog/session-context.md` | Check the state when interrupting or resuming |
| `verify.sh` | You run it and read the result (the AI implements the content) |
| `03-worklog/worklog.md` | The chronological detail. It is large, so do not read it through — read it only when needed |

You do not have to fill in the `<PLACEHOLDER>` values by hand. The AI asks, in one batch, only for the
items it could not fill in.
Values the AI inferred are marked `⟨inferred⟩`; values you confirmed are marked `⟨confirmed⟩`.
A value still marked `⟨inferred⟩` is treated as a hypothesis and is not used as a premise for an ADR
or plan.

## 4. Where records and knowledge live

Numbers such as `ADR-3` or `LL-2` that appear during the work point to items in the following files.

| ID | What it is | Location in the workspace | Who writes it |
|----|------|----------------------|-----------|
| `ADR-N` | A design decision and its reason | `docs/decisions/decisions.md` | The AI drafts it and you approve it |
| `LL-N` | A lesson specific to this project | `docs/knowledge/lessons-learned.md` | The AI |
| `CP-N` | Domain-independent common knowledge | `docs/knowledge/practices-common.md` | Provided by the framework. The project appends with `CP-<project>-N` |
| `DP-N` | Knowledge per migration route | `docs/knowledge/practices.md` | Provided by the Playbook. The project appends with `DP-<project>-N` |

By default the AI reads only the summary table of each file, and opens the body when the work on the
relevant theme begins.
You too can start by looking at the summary table first.
Knowledge usable on other projects is fed back to the framework when the project completes.
The rules for numbering and feedback are in section 3 of [for-engineers.md](for-engineers.md).

## 5. What actually happens in Phase 0-4

### Phase 0a: Assessment (running the code analysis)

First the AI inventories the repositories and confirms the analysis targets with you (default: all).
Then, per target repository, it runs AWS Transform custom's structural analysis
`AWS/comprehensive-codebase-analysis` (structure, technical debt) once each.

Analysis of multiple repositories runs in parallel and takes tens of minutes per repository.
The AI runs it in the background and monitors the logs, so you just wait.

By the tool's design, ATX writes to the target repository during analysis. Concretely it appends to
`.gitignore`, creates a working branch, and commits.
That is why the procedure includes a step to confirm that the branch and HEAD match before and after
the run.

If analysis results already exist, they are ingested rather than running the analysis.
Even if the code at the time of the analysis cannot be identified, the work does not stop; it is made
up for by confirming the real code in Phase 2.
The analysis is run only for repositories that have no results.

When running the analysis, ATX needs one-time preparation on the first run. ATX is assumed to be used
from the CLI.
Before the run the AI checks the `atx` install status, AWS authentication and region. If anything is
missing it sets it up following the [official documentation](https://docs.aws.amazon.com/transform/latest/userguide/custom-get-started.html).
SSO or temporary IAM role credentials are recommended for authentication.

### Phase 0b: Consolidating the assessment results

The AI integrates the per-repository results into a form readable as the system as a whole.
At this stage the contracts between repositories (APIs, events, shared DBs, shared files) are
inventoried.
The frontend/backend boundary has the highest cost to change later, so it is made visible at this
stage.

On that basis, the target stack is decided as an ADR. It must not be decided before seeing the
analysis results.

### Phase 1: preparation

In Phase 1, the changelogs of dependent libraries are investigated, the baseline (a record of correct
current behaviour) is captured, and the non-functional requirement scope is decided.
Each of performance, leaks, fault tolerance and security is assigned to "in scope" or "out of scope"
and recorded as an ADR.
This assignment requires your approval.

The purpose of the assignment is to decide "out of scope" explicitly. In fact there was a case where
the scope of memory-leak verification was left undecided until late in implementation.

### Phase 2: planning

The AI confirms the ATX findings against the real code and makes the work-plan.
Once you approve, the AI sets the state in `work-plan.md` to `CONFIRMED`.
At that point the treatment of the verification gates switches from "not applicable" to applying for
real.

### Phase 3: implementation

The AI implements per Step, and once `./verify.sh` is all-PASS at each Step it proceeds to the next
Step.
Tier 0 work proceeds without confirmation; when it hits a Tier 2 (HOLD) trigger, the AI stops and asks
you to decide.

### Phase 4: final verification

In Phase 4, all modules are built, all tests are run, and the diff against the baseline is checked.
It is complete once the unaddressed count in the adaptation ledger reaches zero and the
independent-verification record and the negative-test records for all perspectives are in place.

## 6. What is machine-checked at the verification gates

`./verify.sh` consists of eight gates.

| Gate | Content | When it applies |
|--------|------|----------------|
| 1. build | Do the artifacts in the expected list exist | After the work-plan is confirmed |
| 2. smoke | Startup and basic operation | Same (must be implemented when Step 1 completes) |
| 3. integration | Integration / E2E. For an app with a UI, a golden-path E2E can be made mandatory | Same |
| 4. nonfunc | Non-functional (performance, leaks, etc.) | Same, but only if put "in scope" in Phase 1 |
| 5. repo-sync | Sync between the records repository and the modernized tree; leftover diagnostic/stub markers | Always |
| 6. knowledge | Volume of the knowledge files (summary rows, body line count, entry count) | Always |
| 7. adaptation | Adaptation ledger (coverage baseline definition, presence of evidence, exclusion reasons, unaddressed count). When unaddressed is zero, the independent-verification and negative-test records | Always |
| 8. project | Provenance of project information (remaining `⟨inferred⟩`) | Always |

The applicability state of each gate can be checked with `./verify.sh status`.

Separately from the eight gates there is `./verify.sh assessment`.
Once Phase 0a has been started, assessment runs automatically at the end of `all`. "Started" means the
state where `analysis-runs.md` has at least one recorded run.
This conditional run exists to prevent declaring Phase 0a complete without going through the mechanical
check.
assessment confirms the Phase 0a completion conditions mechanically. On an engagement premised on
proceeding to the migration, it replaces the human confirmation at the end of Phase 0a with assessment
and proceeds directly to 0b.
This replacement takes effect when "finish with the assessment only" in `migration-project.md` is
`no`.

While the work-plan is unconfirmed, gates 1-4 are treated as PASS as "not applicable".
With this, the gates do not FAIL when you finish with the assessment alone.
On the other hand, if the work-plan is confirmed but the expected list is empty, the build gate FAILs.
This is so a forgotten artifact registration is not overlooked.

## 7. The situations you decide (Tier and HOLD)

The AI's work is split into three stages by the cost of walking it back later.

- Tier 0 (autonomous execution): implementation, builds and tests inside the work-plan proceed without confirmation as long as `./verify.sh` is all-PASS
- Tier 1 (asynchronous review): records, commits and transitions between Steps are done without stopping the work. You confirm them later in a batch via the worklog or git log
- Tier 2 (HOLD): when it hits one of the following eight triggers, the AI always stops and waits for your decision

| # | Stops when |
|---|-----------|
| HOLD-1 | Excluding, disabling or stubbing a feature (a change that loses functionality) |
| HOLD-2 | A change that touches a wire format, a persisted format, or an externally published interface |
| HOLD-3 | Changing the success criteria (= a scope change) |
| HOLD-4 | Three attempts on the same problem without resolution, or spanning two sessions |
| HOLD-5 | A substantial piece of additional work not in the plan arises |
| HOLD-6 | A destructive operation, a change to a shared environment, or stopping a running analysis or build |
| HOLD-7 | A design decision at the level of an ADR |
| HOLD-8 | Crossing a Phase boundary |

When the AI stops, it attaches the material for the decision, such as an ADR draft. You can approve in
one word.
While waiting for the decision, the AI may proceed with other work not dependent on that decision.
Pending decisions are managed in the Decision Queue.

There are two ways to confirm whether the AI's declaration is correct. One is independent
verification, where an AI with a context separate from the declaring AI tries to refute the
declaration.
The other is a negative test, where a detector is deliberately broken to confirm that it can really
detect the problem.

The situations where independent verification is used are limited. Independent verification is done by
an AI running in a separate context; in an environment where that cannot be used, a human sign-off
substitutes.

| Situation | Treatment | Means of assurance |
|------|------|-----------|
| Completion declaration / feature exclusion (HOLD-1) | Independent verification | It runs once. The findings are opened in the adaptation ledger and closed with a disposition. A feature exclusion is verified lightly, one item at a time |
| Confirming the work-plan (Phase 2→3) | Does not apply | Work-plan rows can be changed in Phase 3, so confirmation is not irreversible. A planning error can be detected with high precision by the build and the golden-path E2E |
| A Phase boundary in the middle of analysis and planning | Detector negative test | Deliberately break each perspective's detector and show mechanically that it can detect (CP-13). Remaining findings are carried into the ledger |

The grounds for this allocation are in 4.3 of [for-engineers.md](for-engineers.md).

## 8. The mechanism that lets you continue even after a session is cut

In long migration work, session breaks, server restarts and multi-day work inevitably occur.

- The only file that holds state is `session-context.md`. On resuming, read this file first
- At start, the AI declares in one line what it will do that turn. Because the work is interrupted partway, the declaration is written at the point of starting
- State is never left only in the uncommitted working tree. With WIP commits, diagnostic commits and markers, it is left on the git side too
- If there is an unrecorded uncommitted change, `verify.sh repo-sync` returns FAIL
- Every turn, the hook records the time the prompt was received and the time the reply was returned in `03-worklog/turn-log.tsv` in the records repository. The prompt text is not saved, and the file is not tracked by git
- The AI pastes a table built from these records into `worklog.md`. Its columns are the prompt and reply times, the duration (AI processing time), the wait (human response time) and notes, followed by statistics for the duration and the wait. This table is the only permanent record
- The wait is the wall-clock time from the previous reply to the next prompt. It does not match the time a person spent thinking
- In Kiro, nothing is recorded unless you launch it with `kiro-cli chat --agent migration`
- Recording the turn time and enforcing the at-start declaration are on by default. To disable them, add `--no-turn-log` or `--no-work-guard` at install time ([../harness/README.md](../harness/README.md))

These are countermeasures following a real incident. On one project the work server was interrupted
and two unrecorded uncommitted files were left behind.
As a result, rework occurred to reconstruct the work by guessing from the diff what was changed and
why.

When resuming, you can instruct as follows.

```
Resuming work. Read 03-worklog/session-context.md to confirm the state from last time and continue from where it left off.
```

## 9. A lookup table for when you are stuck

| Symptom | Where to look |
|------|---------|
| I cannot tell how far things have progressed | Current Status in `03-worklog/session-context.md` |
| I cannot tell why it was implemented this way | `docs/decisions/decisions.md` (ADRs) |
| I cannot tell why this feature is missing | The `not_required` rows of `01-plan/adaptation-ledger.md` and the ADR |
| I cannot tell why a gate FAILs | Run `./verify.sh <gate name>` individually and read the message |
| I cannot tell whether Phase 0a is done | Run `./verify.sh assessment`. The missing records are enumerated |
| A gate shows "not applicable" | The work-plan is unconfirmed. Set `WORK-PLAN-STATUS: CONFIRMED` in Phase 2 |
| The AI stopped and asked for a decision | Look at the HOLD number (the table in section 7). An ADR draft is attached |
| I feel I am repeating the same failure | The summary tables of `docs/knowledge/lessons-learned.md` and `practices*.md` |
| The knowledge files are growing large | `./verify.sh knowledge` reports the over-limit condition. Consolidate the content, or record the reason for exceeding |
| `atx: command not found` / ATX authentication or region errors | Follow the installation procedure in the official documentation and redo the Phase 0a-2c checks |
| I do not want to redo the analysis | Existing results can be ingested (Phase 0a-2b). Just give the path to the results |
| `turn-log.tsv` does not grow in Kiro | Kiro was launched without `--agent migration`. Relaunch it with the command in section 8 |
| `turn-log.tsv` is not created on Windows | The hook is not starting. See "Running on Windows" in [harness/README.md](../harness/README.md) |

## 10. Using it for the assessment only

There are three exit points for the work.

| Exit point | Deliverable | Use |
|--------|--------|------|
| End of Phase 0a | ATX analysis results (as HTML), repository inventory, run ledger | You want the analysis results themselves. Handing over to another team |
| End of Phase 0b | Cross-cutting integration, target candidates, rough size and risks, migration policy ADR draft | You want to decide whether to migrate |
| End of Phase 4 | The migrated modernized tree and the verification records | You want to complete the migration |

What `install.sh` does is the same whichever exit point you choose, and there is no mode designation.
No reinstall is needed if you stop at the assessment and later proceed to the migration.

## 11. Terminology

| Term | Meaning |
|------|------|
| Source tree | The current code. Reference only; its content is not changed |
| Modernized tree | `<product>-modernized`. The independent repository where the migrated code is written |
| Records repository | `<product>-migration-<date>`. Holds the plans, records and verification gates |
| ATX | AWS Transform custom. Used for the Phase 0a code analysis |
| Playbook | Procedures, perspectives and knowledge per migration route (e.g. .NET Framework → .NET) |
| work-plan | The work plan confirmed in Phase 2. Holds the sequence of Steps and the success criteria |
| ADR | A record of a design decision (Architecture Decision Record). Writes the background, options, decision and impact |
| baseline | A record of correct pre-migration behaviour. Becomes the baseline for post-migration comparison |
| Expected list | The list of artifacts that should exist after the migration (`EXPECTED_ARTIFACTS` in `verify.sh`) |
| Perspective / perspective table | The kinds of site easily missed in a migration, and how to detect them. In the Playbook's `analysis-appendix.md` |
| Adaptation ledger | A table that manages the sites to be touched, per perspective (`01-plan/adaptation-ledger.md`) |
| Disposition | The state of each ledger row. `addressed` / `replaced` / `not_required` (reason required) / `unaddressed` |
| Unaddressed count | The number that remained `unaddressed` in the ledger. Zero is a completion condition |
| golden-path E2E | A test that runs the user's representative operations in a browser |
| Negative test | A test that deliberately breaks a detector to confirm it can really detect |
| Independent verification | A verification where an AI with a context separate from the working AI tries to refute a completion declaration and the like |
| findings | The remarks that came out of independent verification. Registered as ledger rows and closed with a disposition |
| Tier 0/1/2 | Autonomous execution / asynchronous review / synchronous gate (HOLD) |
| HOLD-N | A trigger at which the AI always stops the work (section 7) |
| Decision Queue | The list of matters awaiting a decision. In `session-context.md` |
| `⟨inferred⟩` / `⟨confirmed⟩` | A value the AI inferred / a value you confirmed |
| CP / DP / LL | Common knowledge / domain knowledge / a lesson specific to the project (section 4) |

## More detail

- The thinking behind it: [concepts.md](concepts.md)
- Internal design and knowledge system: [for-engineers.md](for-engineers.md)
- The formal definition of the flow: [../method/flow.md](../method/flow.md)
- Harness structure and installation: [../harness/README.md](../harness/README.md)
