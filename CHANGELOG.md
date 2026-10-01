# Changelog

All notable changes to this framework are recorded here.

Versioning: while on `0.x`, breaking changes also bump MINOR (MAJOR stays until 1.0.0).
MINOR = a change to the flow, gates or terminology that requires work on existing projects.
PATCH = documentation, wording or error fixes only.

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
