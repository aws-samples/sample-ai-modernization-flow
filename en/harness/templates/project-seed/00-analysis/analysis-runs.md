# Analysis Run Ledger

<!-- The source of truth for Phase 0a progress. Even if a session is interrupted, work must be
     resumable from this ledger plus the logs.
     Update it on every run (create the row before running, fill in the result afterwards). -->

## Git state (before / after)

<!-- ATX runs `git checkout -b atx-result-staging-<id>` in the target repository, appends to
     .gitignore, and performs `git add .` plus a commit (unavoidable tool behaviour).
     Therefore it is mandatory to **record the branch and HEAD before the run and confirm they
     match afterwards**. In one migration there was a real incident where work continued
     while still on the staging branch.
     The Phase 0a completion condition is "the return has been confirmed for every target repository". -->

| repo-id | Branch before | HEAD before | git init performed | Branch after | HEAD after | Return confirmed |
|---------|---------------|-------------|--------------------|--------------|------------|------------------|
| <repo-id> | <branch> | <sha> | done / not needed (already git-managed) | <branch> | <sha> | ✅ match / ❌ mismatch (needs action) |

## Analysis runs

<!-- source column:
       executed = run by this project
       ingested = an existing analysis result was taken in (Phase 0a-2b)
     Drift since the analysis: for ingested results, the gap between the analysed SHA and the current HEAD.
                If the SHA is unknown, state "unknown" and strengthen the
                corroboration in Phase 2 (CP-3).

     **Completion is not judged by the exit code** (measured; see 0a-5 for detail):
       CCA creates empty scaffolding first and writes the content later, so the exit code can be 0
       even when it was cut short -> judge by the **number of non-empty files** or the terminal artifacts
       A non-zero exit can still indicate completion: --limit reached fires after completion with exit 2
     Record the exit code as input to the decision to resume, but never treat it alone as completion. -->

| repo-id | Analysis kind | source | Start | End | Exit code | Completion | Log | Staging branch | Output | Drift since the analysis |
|---------|---------------|--------|-------|-----|-----------|------------|-----|----------------|--------|-----------|
| <repo-id> | CCA (AWS/comprehensive-codebase-analysis) | executed | | | | ✅ complete (terminal artifacts confirmed) / ❌ incomplete (resume needed) | 00-analysis/\<repo-id\>/cca-run.log | atx-result-staging-\<id\> | 00-analysis/\<repo-id\>/ | — |

### Provenance of ingested results

<!-- An ingested result was not produced here, which makes corroboration most valuable (CP-3).
     In one migration, ATX reported "EclipseLink is javax-generation" and a single grep
     disproved it. -->

| repo-id | Analysis kind | Source path | Analysed on | Analysed SHA | Run by | Current HEAD | Diff size | Re-run decision |
|---------|---------------|-------------|-------------|--------------|--------|--------------|-----------|-----------------|
| | | | | <sha / unknown> | | <sha> | <N commits / unknown> | not needed / needed (reason) |

## Execution policy

- **Across repositories: parallel** (cap on concurrent runs: <N>. **Default 5**; up to about 5 is practical on a many-core machine)
- **One analysis per repository** (CCA). ATX runs `git checkout -b` on the target, so parallel execution inside
  one git work tree is impossible. With a single analysis per repository this is automatically satisfied
- **Isolate failures.** One failure must not stop the others. Re-run only what failed

## Incomplete / needs re-running

| repo-id | Analysis kind | State | Next action |
|---------|---------------|-------|-------------|
| | | not run / failed / interrupted | |
