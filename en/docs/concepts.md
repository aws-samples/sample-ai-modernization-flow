# Core Concepts (why it is shaped this way)

This document explains the basic thinking behind AI Modernization Flow.
For how to use it see [how-to-use.md](how-to-use.md); for implementation detail see
[for-engineers.md](for-engineers.md).

---

## Elevator pitch

AIMF (AI Modernization Flow) is a procedure guide for AI and a verification mechanism that lets a
developer who wants to update the technology stack of a legacy system carry out disciplined work by
making use of AI.

People who hold both the knowledge of migration work in modernization and the knowledge of making
good use of AI agents are still not very many.

With AIMF, the AI agent follows the way a migration project proceeds and guides the user through every
stage from analysis to verification. It also records the work and more, following the discipline. The
domain knowledge gained in the actual conversion work is accumulated and is usable in subsequent work
as well.

With an AI agent alone or a single-purpose migration tool, a human must assemble the way the migration
proceeds. AIMF differs from that: it entrusts the migration work to the AI agent, so a human can
concentrate on judging the migration policy and the architecture design policy.


## 1. The modernization that AI Modernization Flow targets

There are broadly two ways to modernize a legacy system.
AI Modernization Flow is a flow for achieving Refactor.

- Refactor: update the technology stack while keeping the existing business logic and code
- Reimagine: generate a code-independent specification from the existing code, and re-implement from that specification

### Migrations it suits and migrations it does not

AIMF suits migrations that update an outdated technology stack to a new one without changing the
business logic of the existing application.
In a Refactor-type migration, the behaviour of the pre-migration system is recorded as the correct
answer, and whether the post-migration system behaves the same way is checked (section 6).

AIMF does not suit migrations that re-build into a new language or architecture without using the
existing code.
In that case Reimagine — writing a specification from the existing code and redeveloping from it — is
appropriate.
For the redevelopment after producing a specification, we recommend a development method centred on
making use of AI, such as AI-DLC.

## 2. The basic way modernization proceeds

By "the basic way it proceeds" in this section, we mean a way that does not decide the target before
the analysis, proceeds in stages, and can also make the decision to stop partway.
In AIMF, the AI guides a human along this way, the human decides, and the AI does the work and
verification.

Modernization proceeds in the following order.

1. Analyse the target code to grasp the as-is
2. Study and decide the to-be architecture. Deciding the target before seeing the analysis gets the premises wrong, so the target is decided on the basis of the analysis results
3. Grasp the technical detail for heading towards the to-be architecture. Pin down, before starting the conversion, the changes in the behaviour of dependent libraries, a record of the pre-migration behaviour, the range of non-functional requirements, and so on
4. Make an overall migration plan. Start from the minimal configuration and add features in stages
5. Carry out the migration (conversion) work according to the plan

In the conversion work, progress is grasped at a deterministic gate (test) per step, and the work
proceeds while correcting the plan as needed.
Events that occur during the work are handled as follows. Whether to stop is not left to the AI's
judgment but decided by conditions fixed in advance.

- A technical problem: investigate while recording the hypotheses tried and their results. If it is not resolved after a fixed number of attempts, or the work drags on, stop and carve it out as separate work to investigate deeply
- Substantial work not in the plan: stop and propose carving it out as separate work; once a human approves, add it to the plan and handle it
- A matter to be deferred: record it as a carry-over, with the reason, so it is not lost sight of later. Anything that loses a feature is decided by a human

Finally, an agent with isolated context verifies the migration-completion declaration exactly once.
The findings are closed one at a time in the same record as the carry-overs, and after a fix are
re-confirmed by an automated test. For a finding that is not fixed, the reason is left, and anything
that loses a feature is decided by a human.

## 3. Asking a human to make the decision is a design for handing down domain knowledge

It is sometimes expected that, by making use of AI, migration work can be carried out with no human
involvement.
But if the migration work is fully automated, the handing down of knowledge to future maintainers —
something that could originally have happened in the course of the migration — becomes impossible too.

That AIMF asks a human to make decisions throughout, and records the result of each judgment, is an
intended design.
For example, when an existing staff member rich in domain knowledge and an engineer well versed in the
modern technology stack work and judge together, the domain knowledge is recorded and handed down.
A Phase gate is a procedure of approval and at the same time a place for a human to deepen their
understanding of the migration target.

The reasons for decisions are recorded in ADRs; knowledge gained during the work is recorded in
Lessons Learned and Practices.
These are handed on to the next lap or to post-migration modifications (section 7).

## 4. The thinking behind achieving it

With the spread of coding agents, the time implementation takes has been greatly shortened.
Previously, because the lead time of implementation was long, requirements definition was forced to
"get it right in one shot" to avoid rework.
But as a result of coding agents removing the bottleneck of implementation, the centre of trial and
error has moved from "producing documents" to "verifying with running code".

Before the cloud appeared, infrastructure building proceeded in the order basic design → parameter
sheet → build procedure → configuring the real machine.
After the cloud appeared, a way emerged of building in the real environment from a rough architecture
specification, pinning down the detailed parameters, and codifying as IaC once it settled.
In application development, the same change is happening.

With application modifications that accompany a migration too, it is hard to predict the impact fully
in advance. Solutions are sought exploratorily while implementing.
However, what became cheap to iterate on is only what has effectively zero cost of change (the
implementation details inside a unit).
What has a high back-out cost has not changed.

- Interfaces between units
- Data schemas and persisted formats
- Non-functional baselines
- Organizational agreement and compliance judgments

So rather than a human reviewing every decision uniformly, decisions are split into three stages by
back-out cost.

| Tier | Scope | Operation |
|------|------|------|
| Tier 0 (fully autonomous) | Implementation details inside a unit, internal refactoring, logic fixes | Proceeds without human involvement as long as the verification gates are all-PASS |
| Tier 1 (asynchronous review) | Records, knowledge notes, commits, transitions between Steps | Never blocks; a human batch-reviews the logs afterwards |
| Tier 2 (synchronous gate = HOLD) | Interface changes, data-format changes, design decisions that impose a lasting constraint from then on, feature exclusion, Phase boundaries, etc. | The AI stops and asks for a human decision with an ADR draft attached |

Escalation conditions are decided by mechanical criteria, never left to the AI's own judgment.


## 5. Completion of work is judged by evidence; discipline is enforced mechanically

The completion criterion of each stage is not "approval of a document" but "an accumulation of
evidence — test and observation results".
Concretely, judgments like the following are made.

- Build success is not completion. It is not declared done until observed by a runtime test
- The AI's analysis result is a hypothesis. Always corroborate against the real code before putting it in a plan
- A root cause is confirmed by demonstration. Until the symptom reproduces and disappears with the cause on and off, it is explicitly marked "hypothesis"

This policy follows the repeated observation, in real operation, that "a rule written in prose slips
through on self-report".

For that reason, the discipline we want the AI to keep is pushed, as far as possible, into the
verification script.
Rather than "writing the discipline for the AI", we take the approach of "the code detects the
deviation from discipline" (Constraints > Prompts).

## 6. The thinking about tests

Unlike greenfield development, in the modernization of a legacy system the specification already
exists as the behaviour of the current code.
Therefore the "understanding the current code" stage is not the task of writing up a specification in
natural language.
It is the task of recording the current behaviour as a Characterization Test (a test that pins the
current input/output).
This test becomes the baseline for the post-migration regression tests.

There are three ways to record the current behaviour, chosen to suit the situation.
Mode A (measure on the old environment) by observing the actual input/output on the old environment;
Mode B (define by reading the code) by reading the code to define the expected behaviour; and Mode C
(reuse the existing tests) by reusing the existing automated tests.
The mechanism for checking whether the post-migration behaviour matches the current one is provided by
the flow, and the tests are made into a form that can be run repeatedly, automatically. What counts as
having migrated correctly — that is, the viewpoint of the tests — is decided by a human.
As a way to help make the viewpoint concrete, there is also a method where, on the basis of the
existing system's specification or real environment, the AI creates E2E tests with Playwright.

In Refactor-type modernization, the centre of gravity is equivalence verification — whether the
conversion was done without changing the current behaviour. For that reason there is no stage of
natural-language requirements definition or of writing a specification from the code. Even when the
expected behaviour is defined by reading the code, it is recorded not as a specification but as a
test's expected value, with grounds and a confidence level attached.

### Silent failure (a feature is lost with neither exception nor error)

The hardest defect to find in a migration is a feature being lost with neither an exception nor an
error log.
This flow calls that a "silent failure".

As a real example, there was a case caused by a security default that became enabled through a
framework's major version upgrade.
The build succeeded and the unit tests all passed. An access test returned HTTP 200 and no exception
appeared. Yet the screen was blank.

For this reason the flow casts two verifications.

1. Covering the sites that must be touched: for each applicable perspective, enumerate the sites and handle them, and make driving the count that remains unexplained to zero a completion condition
2. Confirming the real usage path: build, unit test and startup check only confirm that it starts without an exception. So for an app with a UI, a test that drives the user's operations through a browser is included in the verification

Also, at the planning stage of the migration work, the number of sites to verify is not counted in
detail in advance.
For example, API discrepancies when a framework is changed are faster and more reliable to surface
with the compiler than to investigate in advance.

Instead, the perspectives of "what should be looked at in advance" are covered. The targets are sites
the compiler cannot find, and sites that produce a compile error but where a fix that merely clears
the error causes a defect in another feature.
This perspective can be made once per migration route (migration source → migration target) and
reused, accumulating the more projects you do (Playbook).

## 7. How to use the flow

The flow guides the generally necessary way to proceed with modernization. The flow does not
automatically produce the optimal modernization.

Neither the flow itself nor the plan the flow makes is necessarily correct. The premise is to correct
it during the work.

Modernization need not be finished in one go. It often produces a better result to first run a short
first lap to accumulate knowledge, then enter the second and later laps.

## 8. The three-layer document system used in AI-driven modernization

| Layer | Name | Content | Reuse scope |
|------|------|------|-----------|
| Upper (generic) | Method (the methodology of modernization) | The pattern itself: "assessment → plan → execute" | Domain- and tool-independent |
| Middle (practical) | Playbook | Procedures and judgment criteria for concrete migration work such as runtime and library updates | Specific to the migration domain |
| Lower (AI execution discipline) | Harness (the agent harness) | The execution discipline for how to make the AI work: planning, logs, knowledge, ADRs, Tier gates, etc. | Common to all domains |

To apply this to a new migration domain, use Method and Harness as-is and add only a Playbook.

## 9. What this flow does not do

| Not done | Why |
|------------|------|
| Require platform infrastructure (graph DB, vector DB) | It goes against the tool-independent policy. Code exploration is delegated to the host AI tool |
| Provide controls for cloud operations | This flow assumes work within a single host. IAM boundaries and Policy as Code must be set up separately |
| Put performance, leaks, fault tolerance and security in scope by default | They can be separated from the migration itself, so Phase 1 decides them explicitly as an ADR |
| Design and build the deployment environment | It always arises in a real modernization, but it is a follow-on task after Phase 4 and out of scope for this flow |

## References

- How to use it and what actually happens: [how-to-use.md](how-to-use.md)
- The three layers, knowledge system and gates in detail: [for-engineers.md](for-engineers.md)
- Overview for non-engineers: [overview-for-business.md](overview-for-business.md)
- The formal definition of the flow: [../method/flow.md](../method/flow.md)
