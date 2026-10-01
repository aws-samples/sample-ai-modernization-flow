---
name: migration-subtask
description: Procedure for carrying out subtasks in a migration project. Used to spin off additional work outside the work-plan or complex troubleshooting into an independent plan with its own records. Reference this on a "Start subtask:" instruction, or on a HOLD-4/HOLD-5 trigger.
---

# Subtask Procedure

## Two tiers (lightweight = declaration + worklog / heavy = subtask)

- **Lightweight investigation (default)**: record the start with a `This turn` declaration in session-context and write the hypothesis log and conclusions into the worklog (no intermediate file; skills/migration-troubleshooting).
- **Heavy investigation (this procedure)**: promote when it grows to HOLD-4/HOLD-5, spans Steps, or needs
  external tooling. Create `03-worklog/YYYYMMDDHHmm-<taskname>/`, move the hypothesis log written in the worklog to `investigation.md`, and add `plan.md` (committed, retained).

## Triggers

- The user instructs "Start subtask: \<taskname\>" or "Start investigation: \<taskname\>"
- Proposed via HOLD-4 (3 hypothesis-log lines / spanning 2 sessions) or HOLD-5 (work outside the plan), and approved

## Procedure

### 1. Create a working directory

```
03-worklog/YYYYMMDDHHmm-<taskname>/
```

- The timestamp is the moment work begins (`date '+%Y%m%d%H%M'`)
- taskname is a name specified by the user (alphanumeric + hyphen)

### 2. Create a plan

Copy `03-worklog/templates/subtask-plan.md.template` to `plan.md` and fill in the following:
- Purpose (why this work is necessary)
- Scope (which files/features are involved)
- Steps (concrete work steps)
- Success criteria (what must be confirmed to consider it complete)

### 3. Carry out the work

- Follow the normal Tier gates and work quality rules (core discipline)
- **Place all deliverables, intermediate files, logs, and external tools (git clone, etc.) inside the subtask directory.**
  Do not pollute the original source or the root of the working directory
- For troubleshooting-type work, create `investigation.md` (including the hypothesis log) and `results.md`
- **Always test with a single item before dispatching a batch to sub-agents.** The tools they are given
  **change with the role you specify**; choose a role without file I/O and every item comes back
  unusable (measured: a batch of six failed completely, then changing the role and testing one item
  first resolved it). The test only needs to confirm that one target file could be read and written
- **Always include "no fabrication — report `FAILED: <reason>` if you cannot proceed" in the sub-agent
  prompt.** If it can fill unread input with guesses, the deliverable becomes "apparently done but false"
- **Being a delegate is not a license to drop the model.** Work that contains judgment (independent
  verification, ADR decisions) keeps the stronger model. Only volume-dominated work (translation,
  transcription) may drop (core discipline, "Model Assignment")

### 4. Record completion

- Append a summary to `03-worklog/worklog.md` (timestamp + task name + result)
- Update `03-worklog/session-context.md`
- **LL/DP inventory check**: at the same time as creating `results.md`, check whether the lessons learned from
  this subtask should be reflected in `lessons-learned.md` / `practices.md` (explicitly determine even if none apply)
- Git commit (Tier 1, asynchronous review zone: carry out without waiting for instructions)

## When to make something a subtask

- Additional work not included in a Step of work-plan.md
- Troubleshooting that spans multiple steps
- Verification work that involves introducing and running external tools
- Work of a scale that should have a work plan defined in advance before starting

## The value of a subtask (why spin it off)

- Prevents the main work context from being polluted by trial-and-error noise
- The plan.md / investigation.md / results.md structure preserves trial and error in a re-verifiable form
- Makes interruption and resumption easier (session-context can simply note "continuing in existing subtask")
