# AI Modernization Flow

**Version 0.11.0** ([CHANGELOG](CHANGELOG.md))

> 日本語版（原本）: **[ja/README.md](ja/README.md)**

AI Modernization Flow is a workflow for migrating and modernizing legacy systems while holding AI
agents to a disciplined process. It takes a migration methodology (Method) and makes it executable by
combining it with domain knowledge (Playbook) and AI execution discipline (Harness).

In this repository, the Japanese version is the source of truth. The English version (`en/` and the
root `README.md`) is generated from the Japanese version.

---

## Documentation

| What you want to read | Document |
|-----------------------|----------|
| What it can do first (for IT departments and non-engineers) | [en/docs/overview-for-business.md](en/docs/overview-for-business.md) |
| Why it is shaped this way (thinking and design philosophy) | [en/docs/concepts.md](en/docs/concepts.md) |
| How to use it (what actually happens, a troubleshooting lookup) | [en/docs/how-to-use.md](en/docs/how-to-use.md) |
| Internal design (three layers, knowledge system, gate implementation) | [en/docs/for-engineers.md](en/docs/for-engineers.md) |
| I want to add a new migration domain | [en/docs/authoring-playbook.md](en/docs/authoring-playbook.md) |
| The formal definition of the flow (Phase 0-4, three exit points, the items the user decides) | [en/method/flow.md](en/method/flow.md) |
| Harness structure, what gets installed, tool support | [en/harness/README.md](en/harness/README.md) |
| Domain-specific knowledge and viewpoints | `en/playbooks/<domain>/README.md` |

## Quick Start

At the workspace root (the parent directory where you place the source tree), run the following
command:

```bash
cd /path/to/workspace
git clone https://github.com/aws-samples/sample-ai-modernization-flow.git
./sample-ai-modernization-flow/install.sh --project myapp-1.0 \
    --playbook java-modernization --lang en
```

| Option | Meaning |
|--------|---------|
| `--project <name>` | Scaffolds `<name>-migration-<YYYYMMDD>/` and runs git init |
| `--lang ja\|en` | Language of the installed rules and scaffolding (default `ja`) |
| `--tool kiro\|claude-code\|both` | Where the rules are installed (default both) |
| `--playbook <name\|path>` | Copies the Playbook layer (a name under `playbooks/` or a path; may be omitted if there is exactly one) |
| `--skip-project` | Reinstall/update the rules only, without creating a records repository (when updating the harness) |
| `--update-project <dir>` | Reflect the new version of the scaffolding and Playbook into a live records repository |
| `--no-turn-log` / `--no-work-guard` | Disable turn-time recording and the at-start declaration enforcement (both enabled by default) |

After installing, start the AI agent at the workspace root, give it the path to your source tree and
instruct it to "start the assessment from Phase 0a."

Launch Kiro with the following command. Without `--agent migration`, turn timestamps are not recorded.

```bash
cd /path/to/workspace && kiro-cli chat --agent migration
```

**You do not have to fill in the `<PLACEHOLDER>` values by hand.** The agent runs a startup interview,
scans the source tree to fill in what it can, and asks once for the rest. **The target stack may stay
undecided** (it is decided in Phase 0b after seeing the analysis). See
[en/harness/README.md](en/harness/README.md) for the full set of instruction patterns.

**Assessment-only use is supported.** You can stop at the end of Phase 0a (the analysis results
themselves) or at the end of Phase 0b (material for the go/no-go decision). See
[en/docs/how-to-use.md](en/docs/how-to-use.md) for detail.

## Structure (3 layers)

| Layer | Name | Location | Reuse scope |
|-------|------|----------|-------------|
| Upper (generic) | Method (migration methodology) | `method/` | The methodology itself. Domain- and tool-independent |
| Middle (practical) | Playbook | `playbooks/<domain>/` | Specific to the migration domain |
| Lower (AI discipline) | Harness | `harness/` | **Common to all domains** |

To apply this to a new migration domain, **use Method and Harness as-is and add only a Playbook**
([en/docs/authoring-playbook.md](en/docs/authoring-playbook.md)).

```
sample-ai-modernization-flow/
├── README.md       # English (generated from ja/README.md; the GitHub entry point)
├── VERSION         # The source of truth for the version
├── CHANGELOG.md
├── install.sh      # Setup script for a workspace
├── ja/             # ★ Japanese (source of truth; edit only here)
│   ├── docs/       #   user-facing explanations
│   ├── method/     #   Method (flow, analysis procedure, common practices CP-N)
│   ├── harness/    #   Harness (core discipline, skills, scaffolding, verification gate scaffold)
│   └── playbooks/  #   Playbook (domain-specific; practices.md uses DP-N)
├── en/             # English (generated; do not edit. Same structure as ja/)
└── tools/          # Translation synchronization tooling (i18n-manifest.tsv / glossary.tsv / i18n.lock / build-en.sh / check-i18n.sh)
```

## Design Principles

1. **A ladder of execution discipline**: keep what is always loaded to a minimum. Push details into
   skills (on-demand), and push anything that must be enforced down into verify.sh / git
   (tool-independent mechanisms)
2. **Constraints > Prompts**: a prose rule slips through on self-report. Whatever must be enforced
   becomes an executable script
3. **Completion criteria are evidence**: judged by an accumulation of test and observation results,
   not by document approval
4. **Copy-based distribution**: the agent starts at the workspace root; rules are copied into `.kiro/` etc.
5. **No duplication**: tool-specific files (e.g. CLAUDE.md) and the English tree are generated from source

For the background and rationale see [en/docs/concepts.md](en/docs/concepts.md).

## Language Layout

| Tree | Role | Editing |
|------|------|---------|
| `ja/` | **Source of truth** | Edit only here |
| `en/` and root `README.md` | Generated artifacts | Do not edit directly (`tools/check-i18n.sh` detects it) |
| `install.sh` | A single language-independent file | The source (comments, code) and progress output are English. **The closing guidance (next steps) follows `--lang`** (two errors that ask the user to change an action are also localised) |
| `VERSION`, `CHANGELOG.md`, `LICENSE`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` | Language-independent | Kept in English |

`CP-N` / `DP-N` / `HOLD-N` / `Tier` / `Phase` / `Mode A-C` are left untranslated and maintained as
anchors shared by both languages. Terminology is fixed via `tools/glossary.tsv`.

```bash
# 1. Edit the Japanese source of truth and the English tree together
vi ja/method/flow.md en/method/flow.md
# 2. Record the sync state and verify
./tools/build-en.sh --stamp method/flow.md
./tools/check-i18n.sh          # → PASS
```

**Never update `ja/` alone.** `tools/i18n.lock` records the hashes of `ja/` and `en/` at generation
time. If you change only one side, `check-i18n.sh` returns FAIL on the hash mismatch.

`en/` is committed (treated like a lockfile). Even though it is generated, it is kept in the repository
so that external users can run `install.sh --lang en` immediately after cloning.

### External Contributions

Because `en/` is generated, changes to `en/` cannot be merged as-is. Submit proposals as an Issue, or as
a PR against `en/`. A PR is treated as a content proposal; a maintainer reflects it into `ja/` and then
regenerates `en/`. Keeping the translation in sync is the maintainers' responsibility, so PRs are not
expected to update the translation. See `CONTRIBUTING.md` for details.

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.
