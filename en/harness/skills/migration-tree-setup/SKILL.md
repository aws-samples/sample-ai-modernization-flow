---
name: migration-tree-setup
description: Procedure for creating the modernized tree (the modernized tree) and recording its starting-point information. Reference this when running setup-modernized.sh in Phase 3 Step 1, or when checking the configuration of the two-repository operation.
---

# Setting Up the modernized tree (Phase 3 Step 1)

## Configuration of the Two-Repository Operation

| Repository | Contents | Commit targets |
|-----------|------|-------------|
| `<project>-migration-<date>/` | Records, plans, verification (worklog, plan, test, docs) | Records, knowledge, verification scripts |
| `<product>-modernized/` | Modernized tree source + build system | Code changes (artifacts are .gitignored) |

- The two MUST be placed **side by side** (as sibling directories). verify.sh references the modernized tree via `MODERNIZED=../<product>-modernized`
- The migration source (the original) MUST NOT be modified directly (Off-limits)

## Running setup-modernized.sh

From directly under the migration project:

```bash
./setup-modernized.sh <source-path> <target-os>-<arch> [base-ref]
# Example: ./setup-modernized.sh /path/to/myapp amzn2023-x86_64-lp64
```

- If the migration source is under git management: clone it to carry over history, cut the branch `modernize/<target-os>-<arch>`,
  and tag the starting point with `modernize-base`
- If the migration source is not under git: copy it, run `git init`, make an initial commit, and tag it `modernize-base`
- Build artifacts (generated output depending on the language; use the Playbook's modernized-gitignore.template) MUST be excluded via the modernized tree's .gitignore (they are regenerable)

## Recording Starting-Point Information (required for reproducibility)

After execution, record the following in both `03-worklog/session-context.md` and `01-plan/work-plan.md`:

- The migration source's source path (and whether it is git-managed or not)
- The starting base-ref (tag or SHA) and the SHA of the `modernize-base` tag
- The modernize branch name (`modernize/<target-os>-<arch>`)
- The command for checking the change diff: `(cd ../<product>-modernized && git diff modernize-base..HEAD)`

## Notes When the Migration Source Is Under Git

- MUST NOT push or commit to the protected branches of the clone source (upstream)
- Work MUST be done only on the `modernize/<target>` branch

## Conditions for Completing Step 1

- The modernized tree has been created and the starting-point information has been recorded
- **The verify.sh smoke gate MUST be implemented** (proceeding to Step 2 or beyond while it remains unimplemented is prohibited — see Core Discipline Tier 1 / Asynchronous Review Zone)
