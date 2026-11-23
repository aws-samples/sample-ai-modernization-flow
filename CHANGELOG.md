# Changelog

All notable changes to this framework are recorded here.

Versioning: while on `0.x`, breaking changes also bump MINOR (MAJOR stays until 1.0.0).
MINOR = a change to the flow, gates or terminology that requires work on existing projects.
PATCH = documentation, wording or error fixes only.

---

## Unreleased

_No changes yet._

## 0.12.0 — 2026-11-23

MINOR: the recording rules change; see "Migrating an existing project" below.

- **Turn time recording** (#6): no time table in the worklog; `turn-report.sh --by-entry` summarizes
  time per entry into `time-summary.md` at session start and end. `turn-log.tsv` gains a kind column
  (`human` / `notify`) and is now tracked. `--worklog` is removed.
- **Declaration guard** (#6): Kiro hooks use `"matcher": "fs_write"` (no longer started on every
  tool call), and Kiro v3's `str_replace` is now covered.
- **Agent-direct analysis** (#12): when ATX cannot run, or when the user asks for it, the agent runs
  the public CCA definition itself (0a-4b, 0a-5b). New `fetch-cca-definition.sh` and
  `check-mermaid.sh` (renders the HTML and counts mermaid errors, 0a-6).
- **Knowledge gate** (#11): the 15-entry limit counts only the entries a project added.
- **Fixes**: `generate-html.sh` runs on Windows and with newer pandoc (#10); `install.sh
  --update-project` no longer stops when a `*-migration-*` file (e.g. a `.tgz`) is present (#8).
- **Repository**: `AGENTS.md` / `CLAUDE.md` for developing this repository (#5), CI on pull
  requests (#1), scratch files under `.work/` (#7).

### Migrating an existing project (`install.sh --update-project <dir>`)

1. Merge `.flow-update-<version>/.gitignore` (remove the `03-worklog/turn-log.tsv` line) and
   `.flow-update-<version>/verify.sh` (repo-sync and knowledge gate changes).
2. Run `git add 03-worklog/turn-log.tsv` once, and commit.
3. Claude Code: in the workspace `CLAUDE.md`, replace "Recording Obligations" item 1 and the
   "Session-End Checklist" with the text from `harness/core/migration-core.md` (Kiro's steering is
   overwritten automatically).
4. To use agent-direct analysis, add its Off-limits exception to `migration-project.md` (Claude
   Code: the top of `CLAUDE.md`).

---

## 0.11.0 — 2026-10-02

Initial public release.

- **Method**: the migration flow (Phase 0-4, three exit points, the items the user decides),
  the analysis procedure and the common practices (`CP-N`).
- **Harness**: the core discipline, skills, project scaffolding, the `verify.sh` gate,
  turn-time recording and the at-start declaration guard, for Kiro and Claude Code.
- **Playbooks**: `clang-solarisx86-to-amznlinux`, `dotnetfw-to-modern-dotnet`,
  `java-modernization`.
- `install.sh` with `--lang ja|en`, `--tool`, `--playbook`, `--skip-project` and
  `--update-project`.
- Japanese source of truth (`ja/`) with a generated English tree (`en/`) and the sync tooling
  under `tools/`.
