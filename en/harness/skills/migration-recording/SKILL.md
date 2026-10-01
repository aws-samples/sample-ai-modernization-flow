---
name: migration-recording
description: Details of the recording format for migration projects. Covers worklog entries, git commit messages, and rules for appending knowledge (PB/LL/ADR). Reference this when recording work, committing, or appending knowledge.
---

# Recording Format Details

## Git commit messages

```
[Step X] X-N: <summary>

Reason: <why this fix is needed>
Verification: <what was observed>
Ref: work-plan.md §Step X, DP-<N>
```

- Commit code in the modernized tree and records in the migration repository (2-repository operation)
- For subtasks, use the `[subtask/<taskname>]` prefix

## Appending to the worklog (03-worklog/worklog.md)

- Each entry: date/time (YYYY-MM-DD HH:MM), Phase/Step, work performed, result (success/failure + observed facts), commit hash
- **Order: oldest entries first, append new entries at the end (chronological order)**
- When troubleshooting is involved, include the hypothesis log table (skills/migration-troubleshooting)

### Turn timestamp transcription (only when `--turn-log` is enabled)

**Trigger: every time a worklog entry is written**, run `./03-worklog/turn-report.sh --worklog` and paste
the output into that entry (the range is determined mechanically; you do not need to remember it).
**The raw log is git-ignored; the pasted table is the only permanent record.**

## Accumulating knowledge (4 files)

| File | Format | Content |
|---------|------|------|
| `docs/knowledge/practices-common.md` | `CP-<project>-N` | Common knowledge (usable regardless of domain or language) |
| `docs/knowledge/practices.md` | `DP-<project>-N` | Domain knowledge (usable by other projects in the same domain) |
| `docs/knowledge/lessons-learned.md` | LL-N | Project-specific technical lessons |
| `docs/decisions/decisions.md` | ADR-N | Design decisions (decision date, phase, background, options, decision, rationale, impact) |

- Upon project completion, additions to practices-common / practices are fed back into the flow's
  repository (method/practices-common.md / playbooks/<domain>/practices.md)
- **A project must never assign an unprefixed `CP-N` / `DP-N`.** Additions made in a project use the
  `CP-<project>-N` / `DP-<project>-N` namespace, and the framework assigns the unprefixed number when
  the knowledge is fed back on completion (there was a real incident where a project assigned an
  unprefixed `DP-5` that collided with the framework's. See "Numbering Authority" in practices-common.md)

- **Record not only the knowledge that was adopted, but also the options that were tried and rejected, along with the reasons** (to prevent re-running the same failed path)
- lessons-learned should retain only references to ADRs (the body text lives in decisions.md)
- Do not modify past ADRs (append-only). To overturn one, reference it from a new ADR using `Supersedes: ADR-N`

### Timing of the review (converting to LL/DP)

Detailed recording in the worklog alone does not produce abstraction of knowledge. At the following
points, you MUST always check whether the lessons learned from this segment of work should be
reflected in lessons-learned.md / practices.md (performing the review itself is Tier 1, no instruction required):
- On Phase/Step completion (before moving on to the next work)
- On subtask completion (at the same time as creating results.md)
- On completion of a Tier 2 (HOLD) trigger response (immediately after an ADR is finalized, an exclusion decision is made, etc.)

Treat "not applicable" as an explicit determination as well (do not skip it implicitly). Include one line
in the completion report: "LL/DP review: N entries added / not applicable".

### Consolidation and deletion are enforced mechanically

**The review above only ever produces additions.** In practice there is a case where a review was
proposed at every phase gate yet consolidation or deletion was never carried out once (one
migration). So the reduction side is triggered mechanically by `./verify.sh knowledge`:

- If the entry count in one file exceeds the limit (default 15), the gate **FAILs**
- If you decide not to consolidate, recording the reason at the top of that file lets it pass:
  `<!-- KNOWLEDGE-REVIEWED: YYYY-MM-DD (N entries, consolidation deferred: <reason>) -->`
- If one entry's body exceeds the limit (default 80 lines), split the detail into `docs/reference/`

The design **rejects only an unrecorded excess**; the judgment itself stays with the human.

### How to append (common to all 3 files)

- All of these are "entry-appending" files. Each file's opening "About this document" section contains the numbering and section-structure rules
- Insert new entries **immediately before** the `ENTRIES END` marker (a single HTML comment line at the end of the body); never move it
  (use `grep -n '^<!-- ENTRIES END -->$'` to find the exact line — do not append to the end of the file)
  (do not append to the end of the file)
- For files with a summary table (practices.md), also add a row to the table

## Exceptions where recording is not required

- Answering a simple question (not involving code changes or test execution)
- When the user has explicitly stated "no recording needed"
