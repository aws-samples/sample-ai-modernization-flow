---
name: migration-troubleshooting
description: Rules for hypothesis log operation during troubleshooting and confirming root cause (CP-8). Always reference this when investigating or fixing build errors, runtime errors, or behavior that differs from expectations.
---

# Troubleshooting Discipline — Hypothesis Log and Proof of Causation

## Principle (CP-8)

**You may only record that you have "identified the root cause" when causation has been proven.**
That is, only when you have observed that "toggling the cause ON/OFF reproduces/eliminates the symptom."
Until then, it must always be labeled a "hypothesis."

- ❌ Declaring a "root cause" based solely on code structure analysis (no reproduction test)
- ❌ Confirming causation solely because the symptom disappeared after a fix (cannot be distinguished from a change in environmental factors)
- The more plausible an explanation sounds, the more dangerous it is. A misdiagnosis does not manifest as a "failure," so it can only be detected through proof, not by any other means

## Declare Before You Act (interruption-resilient)

The recording obligation fires at completion, so it does not protect an interrupted investigation.
Write a one-line declaration **before the first code-touch** in the
"In-progress Investigation / Working-tree State" section of `03-worklog/session-context.md`:

```
- **This turn (<timestamp>):** <what you are about to do>
```

- `timestamp` = the instruction time of this turn. `./03-worklog/turn-report.sh --declare` generates the line (when `--turn-log` is enabled).
- **`This turn (...)` is a shared anchor that is not translated.** The work-declaration-guard hook checks it literally.
- **Write it even for work-plan items.** The goal is "know what was happening at interruption".
- Deep-dive details (Trigger / Symptom / Correct =) may follow in the same section. **No separate scratchpad file** — the permanent record is the worklog, and adding an intermediate file just adds a transfer step.

**Classify uncommitted changes in the working-tree ledger in the same section:**
| File | diagnostic(revert) / candidate-fix(verify) | note |
|------|--------------------------------------------|------|

**Never let in-progress state live only in the uncommitted working tree**: make frequent
`[wip]`/`[diag]` commits to the modernized tree. Tag temporary diagnostic code with **`// DIAG-<id>:`**
(id matches the ledger) so it is greppable.

**Heavy investigation = subtask**: when it grows to HOLD-4/HOLD-5, spans Steps, or needs external
tooling, create `03-worklog/YYYYMMDDHHmm-<taskname>/`, move the hypothesis log written in the worklog
to `investigation.md`, and add `plan.md` (committed, retained; skills/migration-subtask).

**Close-out (on completion)**:

1. **Copy the declaration line itself into the worklog** (along with the hypothesis log, root cause and verdict). The declaration lives in session-context and will be removed; if not copied, nothing permanent remains. **Enforcement and permanence are separate problems.**
2. Clear the declaration and working-tree ledger in session-context.
3. Confirm `grep -rn "DIAG-"` is 0 and the ledger has no diagnostic left, then commit candidate-fix files (after verification) with a normal message.

## Hypothesis Log

Record one line for each fix attempt. Recording location: worklog.md for small-scale work, investigation.md for subtasks.

| # | Hypothesis | Prediction (what should change with this fix) | Observed Result | Verdict |
|---|------|--------------------------------|---------|------|
| 1 | Shared library not found (C/Unix example) | Path configuration should resolve rc=127 | rc=0 with normal output | Resolved (causation proven) |

- Verdict: one of **Resolved (causation proven) / Hypothesis rejected / Continuing**
- Attempting a fix without recording it is a violation of the recording obligation
- Also retain rejected hypotheses and the reasons for rejection (to prevent re-running the same failure route)

## Escalation (HOLD-4)

Once either of the following is reached, **stop**, report to the user with the full hypothesis log and the possibility of misdiagnosis attached, and propose "Start subtask: \<taskname\>":
- The hypothesis log for the same issue reaches **3 lines** without reaching a "Resolved" verdict
- The same issue has spanned **2 sessions**

Since the number of lines in the hypothesis log is the denominator for the count, you cannot "game the count by splitting attempts into finer increments" (splitting attempts only increases the number of lines).

## Fundamentals of Observation

- **Always scrutinize exit codes** (native execution example): 124=timeout (process may be alive, meaning startup may have succeeded), 139=128+11 (true SIGSEGV), 127=missing command/library, 1=application-level error
- Record crash reports as a set of three: "execution command, environment variables, exit code"
- Distinguish daemon malfunction from a crash (starting up and then going silent ≠ SEGV)
- Do not exclude environmental factors (PATH, LD_LIBRARY_PATH, prerequisite daemons, directory permissions) from the hypothesis list

## Monitoring Long-Running Commands

For long-running commands such as ATX execution or large-scale builds, do not ask the user to run them manually just because of their duration (except when interactive operation is required). Do not rely solely on simple liveness monitoring like `while pgrep ...; do sleep; done` (a process disappearing does not mean "terminated normally" — it also disappears on abnormal termination).

Monitor via an active-check cycle at 1–2 minute intervals, rather than delegating everything to a single command that blocks for a long time at once. In each cycle, check the following:
- The latest few lines of the log (visualizes progress; a substitute for on-screen output during manual execution)
- The log file's last-modified time (stale detection; suspect a stall if there has been no update for a certain period)
- Whether the process is still alive, and if it has disappeared, its exit code
- Error patterns in the log (`error:`, `Error [0-9]`, `undefined reference`, etc.)

Upon confirming an anomaly (stoppage, stall, or detected error pattern), immediately switch to detailed investigation instead of continuing to monitor.

## Case Study (Lesson Learned — C/Unix Migration Example)

A misdiagnosed "SEGFAULT" in a certain daemon process: a plausible-sounding root cause of "collision between ELF copy relocation and C++ static constructors" was recorded as confirmed, but on re-investigation the SEGFAULT itself did not reproduce, and the true causes were (1) the shared library search path not being configured (rc=127) and (2) malfunction due to a prerequisite daemon not having started. Had proof of causation been made a condition for confirmation, this could have been detected on the first pass.
