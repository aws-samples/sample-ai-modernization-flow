# A Plain Explanation (for IT departments and non-engineers)

For technical detail see [for-engineers.md](for-engineers.md); for how to use it see
[how-to-use.md](how-to-use.md).

---

## 1. In one sentence

This flow is a framework for having AI agents carry out the migration of systems built on old
technology, under a fixed procedure.

If you simply leave it all to an AI and say "migrate this", the build can succeed while features have
quietly gone missing. It can also become impossible for anyone to tell, afterwards, why something was
fixed the way it was.
In this flow, the range the AI may advance autonomously and the junctures a human must decide are
separated in advance.
On that basis, the migration proceeds while recording the basis for each decision.

## 2. Problems it addresses

| Problem | How the flow responds |
|-----------|--------------|
| It runs on out-of-support technology and we want to migrate, but cannot size the work | You can stop after the assessment alone (see characteristic 1 in section 3) |
| The design documents are old and we do not know the current specification | The current code's behaviour is recorded as executable tests. These tests pin the current input/output |
| If we leave it to an AI, we worry a feature is missing even though it looks like it works | The places that need work are compiled into a ledger. Driving the count of sites whose handling cannot be explained to zero becomes a completion condition |
| Later, nobody can tell why it was implemented this way | Design decisions are kept as records (ADRs). Human approval is always required at a decision juncture |
| System-specific knowledge discovered during the work is lost inside the dialogue with the AI | Lessons Learned during the work, and Practices for carrying out the migration work better, are recorded as domain knowledge |
| The migration drags on and cannot be handed over when staff change | Work state, decisions and knowledge live in files, so work can be interrupted and resumed |

## 3. Five characteristics

### Characteristic 1: You can do just the assessment

Before committing to a migration, you can carry out only the work of investigating the current state.
There are two points at which the work can be stopped.

| Where you stop | What you receive |
|--------------|---------------------|
| ① Analysis | An inventory of the current configuration per repository, a list of technical debt, and the results of structural analysis (viewable as HTML) |
| ② Decision material | In addition to ①'s deliverables: a system-wide configuration diagram integrating multiple repositories, migration target candidates and a comparison, a rough size estimate, the main risks, and a proposed migration policy |

### Characteristic 2: The target is chosen after seeing the assessment results

The current technology configuration is made clear by the analysis. The target is chosen after seeing
those analysis results.
This ordering avoids the situation of deciding the target first and finding later that it does not
work.
Even during the migration work, if there is a reason such as a dependency, the work plan can be
changed with human approval.

### Characteristic 3: Completion is judged by evidence of working

The completion of each stage is judged by test results and observation results. Approval of a design
document alone does not count as completion.
The point at which the build passes is also still incomplete; completion is the point at which it is
actually run and its behaviour observed.

### Characteristic 4: It always stops where a decision is needed

What the AI must not decide on its own is laid down in advance as rules.
For example, when removing a feature, changing a data format, or changing the scope of work, the AI
always stops.
On that basis it summarises the options and their impact and asks for a human decision.

While waiting for the decision, the AI advances other work unrelated to that decision, reducing the
wait as much as possible.

### Characteristic 5: It detects that a feature has been lost

The hardest thing to find in a migration is a defect where a feature stops working yet no error
appears.
In this flow, the places that need work are compiled into a list (a ledger) and reconciled against
the post-migration implementation.
In addition, a test that automatically reproduces, in a browser, the flow of operations a real user
performs is built in as a mandatory verification item.

## 4. How it proceeds (the broad flow)

```
  ① Analysis        Phase 0a  Analyse the current configuration and technical debt
  ② Decision material  Phase 0b  Summarise target candidates, size and risks
  ③ Preparation     Phase 1   Record current behaviour, decide the verification scope
  ④ Planning        Phase 2   Get the work plan approved
  ⑤ Execution       Phase 3   Migrate in stages, verifying at each stage
  ⑥ Final check     Phase 4   Verify all functionality, then re-check from an outside viewpoint
```

At the end of each stage, the AI confirms with a human whether to proceed to the next stage.

## 5. What it can and cannot do

| | Content |
|---|---|
| Can | For application code: analysis of the current configuration / surfacing of technical debt / comparison of target candidates / staged migration / automation of verification / recording of decisions and knowledge |
| Cannot | Performance and failure testing after the migration (can be added as a follow-on phase) |
| | Designing and building the cloud environment (can be added as a follow-on phase after the migration) |
| | Controls for an AI directly operating cloud resources (this flow assumes work within a single server) |
| | Deciding whether production-like data may be used in tests (always a human decision, because law and contracts are involved) |

## 6. Why you can use it with confidence

- The current source code is not changed. The current code is treated as read-only, and the migrated code is created in a separate location
- A record of decisions remains. "Why this technology was chosen" and "why this feature was removed" can be confirmed later
- It can be continued after an interruption. Work state lives in files, so it handles staff handovers and multi-day work
- Verification is automated. Rather than relying on visual inspection, pass/fail is judged by a mechanical check

## 7. Frequently asked questions

Q. We have not chosen the target technology. Can we still start?
Yes. In fact we recommend choosing the target after seeing the analysis results.
All that is needed to start is two things: where the target source code is, and what must not be
changed.

Q. Our system is split across several repositories.
Multiple repositories are supported. The whole is inventoried first, then the analysis proceeds in
parallel per repository.
Integration points between repositories, such as the exchange between the screens and the business
logic, are hard to change later, so they are surfaced at an early stage.

Q. We have already had an analysis done separately. Will it be redone?
It is not redone; the existing analysis results can be taken in.
However, the current code may have moved on since the analysis, or the analysis may have been
insufficient.
Therefore the AI proceeds by confirming the analysis results against the current code.

Q. How long does it take?
It depends on the size of the target and the content of the migration. For reference, there is a case
where a technology stack was updated on a medium-sized Java web application (150K LOC, about 160
existing tests).
In that case, the analysis finished in a few hours, and completion of the implementation, including
exchanges with people, took a few days.

## More detail

- How to use it and what actually happens: [how-to-use.md](how-to-use.md)
- The thinking behind it: [concepts.md](concepts.md)
- Technical detail: [for-engineers.md](for-engineers.md)
