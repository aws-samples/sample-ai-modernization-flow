---
name: migration-session
description: Details of session start/end procedures. Restoring state when resuming a session, and committing/pushing/checking consistency across both repositories at session end. Refer to this for handing off work across sessions.
---

# Session Start/End Procedures

## Session Start (Resume) Procedure

1. Read `03-worklog/session-context.md`:
   - Last Checkpoint / Current Status / Next Actions / Blockers
   - **Decision Queue** (if there are pending user decisions, report them first)
   - **Verification Queue** (if there are unverified fixes, start with verification)
   - Repository sync status table (report if there are unpushed changes)
2. Check recent work with `tail -80 03-worklog/worklog.md`
3. Set up the test environment (`02-test/test-procedures.md` "Prerequisites".
   Daemons, environment variables, etc. are volatile, so this is needed every time)
4. Confirm "nothing is broken" with `./verify.sh` before resuming work
5. If there is an interrupted subtask, read that directory's plan.md / investigation.md and continue
6. If the working tree is dirty, classify it before continuing: cross-check the session-context `This turn` declaration and working-tree ledger against
   `git log`, and sort each change into diagnostic (revert) / candidate-fix (treat as unverified and
   re-verify). If there is no record at all, reconstruct intent from the diff and record it before proceeding

## Session End Checklist (Tier 1 · Asynchronous Review Zone — execute without waiting for instructions)

**Under the two-repository operation, a commit/push on only one side is considered incomplete.**

1. Confirm that today's entry exists in `03-worklog/worklog.md` (add one if missing)
2. Update `03-worklog/session-context.md`:
   - Last Checkpoint (date/time, git ref of both repositories, Phase/Step)
   - Current Status / Next Actions / resume procedure
   - Decision Queue / Verification Queue
   - Repository sync status table
3. **migration (recording) repository**: commit until `git status` is clean
4. **modernized tree**: commit verified changes
   (record unverified changes in the Verification Queue and set them aside)
5. **If a remote is configured, push both repositories.**
   If no remote is configured, state this explicitly in session-context.md
6. Finally, display `git log --oneline -1` and `git status --short` for both repositories and report their consistency
   (run `./verify.sh repo-sync` to mechanically confirm both repositories have zero uncommitted changes)
7. If there are unresolved items in the Decision Queue, state them explicitly in the end-of-session report

## Repository Sync Status Table (within session-context.md)

| Repository | Latest Commit | Uncommitted Changes | Remote | Push Status |
|-----------|-------------|--------------|---------|---------|
| migration | <sha> | none/yes(<details>) | <remote or not configured> | ✅ pushed / ⚠️ not pushed |
| modernized tree | <sha> | none/yes(<details>) | <remote or not configured> | ✅ pushed / ⚠️ not pushed |
