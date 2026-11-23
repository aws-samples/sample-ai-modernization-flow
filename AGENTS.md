# Agent Instructions — developing this repository

> **Scope.** These instructions are for developing the AI Modernization Flow framework
> itself. If you are running a migration (you were started at a workspace root and this
> repository is only a cloned copy of the framework), **ignore this file** and follow the
> installed migration rules instead.

Read [CONTRIBUTING.md](CONTRIBUTING.md) ("Repository Layout and Translation Policy") and
[README.md](README.md) ("Language Layout") for the background. The rules below are the
parts an agent must not get wrong.

## Repository layout

- `ja/` — **source of truth** (Japanese): `docs/`, `method/`, `harness/`, `playbooks/`.
- `en/` and the root `README.md` — **generated** English artifacts, committed like a lockfile.
- `install.sh`, `VERSION`, `CHANGELOG.md`, `LICENSE`, `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md`, this file — language-independent, kept in English.
- `tools/` — i18n sync tooling (`i18n-manifest.tsv`, `glossary.tsv`, `i18n.lock`,
  `build-en.sh`, `check-i18n.sh`) and `test-verify-helpers.sh`.

## Editing `ja/` and `en/`

1. Make the change in `ja/`, then make the corresponding change in `en/` **in the same
   change**. Never update only one side.
2. Translate per `tools/glossary.tsv`. The class in `tools/i18n-manifest.tsv` says how:
   - `translate` — translate the whole file.
   - `translate-comments` (shell scripts, templates) — translate comments and
     user-facing strings only; **never change code** while translating.
   - `code-identical` (`harness/verify.sh.template`) — code lines (non-comment,
     non-echo) must be byte-identical between `ja/` and `en/`.
   - `root-readme` — `ja/README.md` generates the root `README.md`; relative links into
     `method/`, `harness/`, `playbooks/`, `docs/` get the `en/` prefix.
3. Record the sync state for each changed entry (path relative to `ja/`):
   `./tools/build-en.sh --stamp <path>`. Run `./tools/build-en.sh` with no arguments to
   list stale entries. Do not use `--bootstrap` unless explicitly asked.
4. Adding or removing a file under `ja/` requires the same change under `en/` and a
   matching line in `tools/i18n-manifest.tsv`.

Do not translate or renumber the shared anchors: `CP-N`, `DP-N`, `HOLD-N`, `LL-N`,
`ADR-N`, `Tier`, `Phase`, `Step`, `Mode A`-`C`. They are referenced from both trees and
from installed user projects. `check-i18n.sh` enforces a 1:1 match of `CP-N` / `DP-N` /
`HOLD-N` between each source and target.

## Code

- `install.sh` is a single English file. Its closing guidance (next steps) follows
  `--lang`, so a change there needs both the `ja` and `en` strings.
- After touching `harness/verify.sh.template` (either tree), run
  `./tools/test-verify-helpers.sh`.
- All shell scripts must pass `bash -n`. `check-i18n.sh` covers the scripts under `ja/`
  and `en/`; check `install.sh` and `tools/*.sh` yourself.

## Versioning

`VERSION` is the single source of truth (`install.sh` stamps it into generated files).
While on `0.x`: MINOR = a change to the flow, gates or terminology that requires work on
existing projects; PATCH = documentation, wording or error fixes only. Record notable
changes in `CHANGELOG.md`. Bump the version only when asked.

## Done means

All of the following pass:

```bash
./tools/check-i18n.sh
./tools/test-verify-helpers.sh
bash -n install.sh tools/*.sh
```
