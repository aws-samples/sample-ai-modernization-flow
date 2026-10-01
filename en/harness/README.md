# Harness (Agent Harness)

The Harness is the mechanism for making AI agents work with discipline in migration/modernization
projects. It does not depend on any specific domain or tool, and it provides execution discipline such
as Tier gates, hypothesis logs, ADRs, verification gates, and session management.

In the body, `CP-N` and `DP-N` are knowledge IDs, and Tier and `HOLD-N` are triggers to stop and defer
to the user's judgment.
For details, see Section 4 (where records and knowledge live), Section 7 (Tier and HOLD), and
Section 11 (terminology) of [How to Use](../docs/how-to-use.md).

## Position in the Document System (3 Layers)

| Layer | Name | Substance |
|------|------|------|
| Upper (generic) | Method (migration methodology) | `../method/` (flow.md = Phase 0-4 + three exit points + items the user decides, common analysis procedure) |
| Middle (practical document) | Playbook | `../playbooks/<domain>/` (e.g., clang-solarisx86-to-amznlinux). practices.md (DP-N), the analysis-viewpoint appendix, verify-snippets, reference |
| Lower (AI execution discipline) | Harness = this directory | Core behavioral discipline, skills, templates, verification gate scaffolding |

When applying this to a new migration domain such as Java, use this directory as-is without changing it.
The only thing you create new is the Playbook under `../playbooks/`.

## Structure

```
harness/
├── core/
│   └── migration-core.md        # The thin core discipline that is always loaded (Tier gates, quality rules)
├── skills/                      # Detailed procedures loaded on demand (SKILL.md format)
│   ├── migration-recording/     #   Recording format (worklog, commits, appending knowledge)
│   ├── migration-subtask/       #   Subtask procedure
│   ├── migration-troubleshooting/ # Hypothesis log and root cause determination (CP-8)
│   ├── migration-adr/           #   ADR drafting, exclusion flow, standard Phase-gate confirmation
│   ├── migration-adversarial-review/ # Independent verification (context isolation; limited to the completion declaration and the HOLD-1 feature exclusion)
│   ├── migration-verification/  #   Verification gate operation, test recording
│   ├── migration-session/       #   Session start/end procedure
│   └── migration-tree-setup/    #   modernized tree creation, two-repository operation
├── templates/                   # Project scaffolding (copied by install.sh)
│   ├── migration-project.md.template  # Project-specific information (for steering/CLAUDE.md)
│   ├── session-context.md.template
│   ├── baseline-behavior.md.template  # Guide for the two Characterization Test modes
│   ├── subtask-plan.md.template
│   ├── lessons-learned.md.template
│   ├── decisions.md.template
│   └── project-seed/            # Initial files: inventory, run ledger, adaptation ledger, worklog, work-plan, etc.
├── tools/                       # Hook-driven tools (see "Turn Timestamps and Declaration at Start of Work" below)
├── verify.sh.template           # Verification gate scaffolding (all 8 gates. 4 whose application switches on work-plan confirmation + 4 always applied)
└── setup-modernized.sh              # modernized tree creation (clone+branch / copy+init)
```

The installation script `install.sh` is at the repository root.

## Design Principles

1. **Minimize context load (a ladder of execution discipline)**: Only the thin core in `core/` is always
   loaded. Detailed procedures go into skills loaded on demand. Discipline that must be enforced is
   checked with tool-independent mechanisms such as verify.sh and git. Do not assume a constraint written
   only in the prompt will be followed
2. **Copy-based distribution**: The agent is launched at the workspace root. Rules are copied into
   `.kiro/steering/` and the like, so the user does not need to launch from a subfolder
3. **Tool-independent**: The frontmatter of a skill's SKILL.md works with Kiro and Claude Code. Other
   tools can still reference it as a plain Markdown document
4. **No duplication**: Tool-specific files such as CLAUDE.md are generated from the source (core/templates)
5. **A feature that needs user action is distributed together with that action and a way to confirm it**:
   a feature that uses hooks may not work depending on how the agent is launched. So install.sh prints the
   required action in its output and ships a way to confirm the feature is working. In Kiro you must launch
   with `--agent migration`

## Usage

### Installation

At the parent directory where the source tree, the modernized tree, and the records repository line up
(the workspace root), run the following command.

```bash
cd /path/to/workspace
git clone https://github.com/aws-samples/sample-ai-modernization-flow.git   # or use a path already fetched into any location
./sample-ai-modernization-flow/install.sh --project myapp-1.0 \
    --playbook java-modernization
```

| Option | Description |
|-----------|------|
| `--project <name>` | Generates `<name>-migration-<YYYYMMDD>/` from the scaffolding and runs git init |
| `--lang ja\|en` | Language of the installed rules and scaffolding (default is ja). `ja/` is the source of truth, `en/` is generated |
| `--tool kiro\|claude-code\|both` | Where to install the rules (default is both) |
| `--playbook <name\|path>` | Copies the Playbook layer into the project. Specify a name under `playbooks/` or a path. May be omitted if there is only one Playbook |
| `--skip-project` | Only reinstalls/updates the rules (core and skills). It changes nothing inside the records repository |
| `--update-project [<dir>]` | Updates an existing records repository to this version (see "Updating the Harness" below) |
| `--no-turn-log` / `--no-work-guard` | Disables turn-timestamp recording and the at-start declaration. Both are on by default. See the sections below |

### Running on Windows

Run `install.sh` from Git Bash (MSYS2 or Cygwin). It cannot be run from cmd.exe or PowerShell.
`install.sh` detects Windows automatically, handles the differences in the table below, and prints at
install time the handling this host needs. Everything printed is a warning; the install itself completes.

Each phenomenon in the table below fails without emitting an error, so know them in advance.

| Phenomenon | Description |
|------|------|
| The hook `command` | The tool's hook runner launches commands with the native Windows process API, so a shebang is not interpreted. A hook pointing directly at a `.sh` file is not launched and fails silently every turn. So on Windows `install.sh` writes the command in the form `bash "<path>"`. This form assumes `bash` is visible on the native PATH. `install.sh` checks with `where bash` and warns if it is not found |
| `python3` is found but cannot be executed | On Windows `python3` is usually the WindowsApps App Execution Alias stub. `command -v` finds it, but running it prints a redirect to the Microsoft Store and exits. The real interpreter is usually installed under the name `python`. `install.sh` verifies candidates by actually running them and writes the one that ran into the installed scripts |
| `$HOME` and `%USERPROFILE%` do not match | Git Bash's `$HOME` can be on a different drive from the Windows user profile (measured: `/h/` vs `D:\Users\<user>`). Tools that run as native processes (external agents, etc.) cannot reference files under `~/`. Place toolchains such as the JDK and Maven under `%USERPROFILE%`. On one project a JDK placed in `~/tools/` could not be found, and 30 agents' worth of billing was spent entirely on searching |

### Workspace After Installation

```
<workspace>/                      ← Launch the AI agent here
├── .kiro/
│   ├── steering/
│   │   ├── migration-core.md     ← Core discipline (overwritten on harness update)
│   │   └── migration-project.md  ← Project-specific (edit the PLACEHOLDER)
│   └── skills/migration-*/       ← Detailed procedures (loaded on demand)
├── CLAUDE.md                     ← For Claude Code (project-specific + core discipline)
├── .claude/skills/migration-*/
├── <product>/                    ← Source tree (Off-limits. Its content is not changed)
├── <product>-modernized/         ← modernized tree (created in Phase 3 Step 1)
└── <project>-migration-<date>/   ← Records repository (records, plans, verification. A git repository)
```

When one system consists of multiple repositories, line up the source tree and the modernized tree per repository.

```
├── api/            ├── api-modernized/
├── web/            ├── web-modernized/
└── <project>-migration-<date>/   ← a single records repository
```

The inventory of target repositories is recorded in `00-analysis/repository-inventory.md`.
The list of modernized trees is managed in `MODERNIZED_TREES` of `verify.sh`.

### The First Instruction to the Agent

The user does not need to fill in `<PLACEHOLDER>` by hand. The agent fills them in during the startup
interview and asks, in one batch, only for the items it could not fill in. The information required to
start is only the source tree path and the off-limits range.
The target stack may stay undecided; it is decided in Phase 0b after seeing the analysis results.

Depending on your purpose, give one of the following four patterns of instruction.

**A. Start from the assessment (run the AWS Transform (ATX) analysis)**

```
Starting the assessment of <source tree path>.
Follow Phase 0a of 00-analysis/analysis-procedure.md, beginning with the repository inventory.
The target stack is undecided. We will decide it after seeing the analysis results.
```

**B. Use existing ATX analysis results (skip execution)**

```
Starting the assessment of <source tree path>.
ATX analysis results already exist at <results folder path>.
Proceed with Phase 0a as an ingest, not as a run.
Still do the repository inventory, and confirm the mapping of the results to each repository and the
drift since the analysis (the gap between the analyzed SHA and the current HEAD).
If any repository or analysis kind is missing, run only those.
```

**C. Proceed to the migration after the assessment**

```
Based on the assessment results, proceed with the migration. Continue from Phase 0b.
```

**D. Resume across sessions**

```
Resuming work. Read 03-worklog/session-context.md to confirm the state from last time and continue.
```

If you finish with the assessment only, you can stop at the end of Phase 0a (the analysis results
themselves) or at the end of Phase 0b (the material for the go/no-go decision).
Even then, what `install.sh` does is the same as when going all the way to the migration.
While the work-plan is unconfirmed, verify.sh's build / smoke / integration gates are treated as "not applicable".

### Updating the Harness

Updating the Harness is split into two stages. `--skip-project` updates only the rules.

```bash
cd /path/to/workspace
./sample-ai-modernization-flow/install.sh --skip-project        # core and skills only
./sample-ai-modernization-flow/install.sh --update-project --playbook <name>   # the contents of the records repository
# the --update-project directory may be omitted if there is exactly one <name>-migration-<date>/
# with several, specify it with --update-project <dir> or --project <name>
```

`--skip-project` preserves `migration-project.md` and `CLAUDE.md`. Updates to the core discipline inside
CLAUDE.md are merged by the user manually.
The contents of the records repository, including `verify.sh`, are not updated by `--skip-project`.
On one project, people believed they had updated with `--skip-project`, but `verify.sh` stayed on the old
version. As a result the change that was the main purpose of the release was not reflected, and 7 files
had to be hand-synced before it finally worked as expected.

#### Files That Are Overwritten and Files That Are Preserved

Whether a file is overwritten is decided solely by whether the user writes into it.

| Treatment | Target |
|------|------|
| Regenerated (overwritten) | `00-analysis/analysis-procedure.md`, `00-analysis/*.sh` (the Method tools), `setup-modernized.sh`, `03-worklog/templates/subtask-plan.md.template`, `docs/reference/` / `00-analysis/transform-config-cca-template.yaml` / `modernized-gitignore.template` (Playbook) |
| Preserved (not changed) | `verify.sh`, `docs/decisions/decisions.md`, `docs/knowledge/*.md`, `01-plan/*.md`, `00-analysis/repository-inventory.md`, `analysis-runs.md`, `analysis-appendix.md`, `02-test/*.md`, `03-worklog/session-context.md`, `worklog.md`, `.gitignore` |

Among the preserved files, those that differ from the current template get the new template placed at the
same relative path under `.flow-update-<version>/`.
If there is no difference, nothing is placed and only that file's stamp is updated to the current version.
After finishing the merge, delete the whole `.flow-update-<version>/` directory.

This list is defined in exactly one place, `PROJECT_FILE_MAP` in `install.sh`. Install and update read
the same table, so there is no accident of only one side being updated when a template is added. Previously
the list was split into two implementations, and on the day it was written two Playbook files were missed
from the update targets. Updating without `--playbook` leaves the Playbook-side files out of the update
targets, so install.sh prints that fact as a warning.

`verify.sh` is always preserved. The expected list, `BUILD_CMD`, and the smoke/integration implementations
exist only in the project-side copy. So the merge moves these from the project side to
`.flow-update-<version>/verify.sh`. Merging in the reverse direction means the same work is needed at the
next update too.
install.sh never deletes files. A file that disappeared from the framework is only reported and left in the project.

#### Checking a Project's Gate Version

Line 2 of `verify.sh` stamps the version it was generated from. This line is the only means of checking the version.

```bash
grep '^# ai-modernization-flow ' <records>/verify.sh   # → # ai-modernization-flow 0.11.0
```

`--update-project` reads this line and shows the version it is updating from. If there is no stamp (for example,
the line was deleted), it is shown as `unstamped`.
The stamp of a preserved file is not updated. That is because, until the merge is done, that gate's content really is still the old version.

## Turn Timestamps and Declaration at Start of Work (on by default; disabled with `--no-turn-log` / `--no-work-guard`)

A record that relies on the agent's self-report cannot be detected when it is forgotten. So information
that a hook can collect is collected by a hook.
This mechanism is installed by default. To disable it, add `--no-work-guard` (do not require a declaration)
or `--no-turn-log` (do not even record) to `install.sh`.

| What is installed | Role |
|--------------|------|
| `03-worklog/turn-log.sh` | Called from the hook every turn; appends time, event, and session_id to `turn-log.tsv` in the same directory. The prompt body is not saved |
| `03-worklog/turn-report.sh` | Outputs the table to paste into the worklog with `--worklog`, the list of records with `--list`, and the declaration line with `--declare` |
| `03-worklog/work-declaration-guard.sh` | Not installed when `--no-work-guard` is specified. If there is no declaration, it stops the execution of change-type tools (`Bash` is out of scope) |

The python path is resolved at install time and written directly into the three scripts. The hooks run
every turn, so they do not search for python at runtime.
Replacing, deleting, or moving python invalidates the written path, and recording stops without emitting
an error. The hooks operate fail-open and do not stop tool operation even if recording fails. This
phenomenon happens on any OS.
Run `turn-report.sh --list`, and if the records are not increasing, re-write the path with `install.sh --update-project`.

In Kiro you must specify the agent explicitly at startup. Without it, nothing is recorded even if the
configuration is placed.
That is because the default launch method uses the built-in agent, and hooks cannot be configured for the
built-in agent.
Also, if you launch from somewhere other than the workspace root, Kiro silently uses a global config of the same name.

```bash
cd <workspace root> && kiro-cli chat --agent migration
./<project>-migration-<date>/03-worklog/turn-report.sh --list   # confirm it is being recorded
```

The only records that remain permanently are the table pasted into the worklog and the declaration. The
raw log is excluded from git management.
The table columns are Prompt (received), Reply (returned), Duration (AI), Wait (human) and Notes. After the table come the count, median, minimum, maximum and total for both the duration and the wait.
A wait longer than one hour (`TURN_LOG_IDLE_LIMIT`) is treated as time away and excluded from the wait statistics.
The timing for transcribing into the worklog is in skills/migration-recording, and how the declaration is
operated is in skills/migration-troubleshooting.
The details of the mechanism, caveats, and the security policy are in the header comments of each script.

## Tool Support Status

| Tool | Core discipline | skills | Status |
|--------|---------|--------|------|
| Kiro (CLI/IDE) | `.kiro/steering/` | `.kiro/skills/` (auto-recognized via skill://) | Supported |
| Claude Code | `CLAUDE.md` | `.claude/skills/` (Agent Skills) | Supported |
| Others (Cursor, etc.) | Copy core into each tool's rule file | Instruct to treat skills/ as a reference document | Manual install |

## Items the User Must Explicitly Decide

The Harness does not decide the following items automatically. At the start of a project, the user checks
the "Items the User Must Explicitly Decide" in the Playbook layer's README and decides each item rather
than leaving it implicit.

- baseline mode selection (measure, read the code, reuse existing tests)
- Non-functional scope (ADR mandatory)
- Plan for running long-duration tests
- Adjustment of Tier 2 (HOLD, stop-and-confirm zone) triggers
- Knowledge inventory
- Cloud operation guardrails (not provided by this Harness)
- Whether production-equivalent data may be used
