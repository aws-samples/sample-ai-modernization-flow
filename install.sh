#!/bin/bash
# =============================================================================
# AI Modernization Flow Installer Script
# =============================================================================
#
# Run this from the workspace root (the parent directory where the source tree,
# the modernized tree, and the records repository are laid out side by side).
# The AI agent is started from the workspace root.
#
# Usage:
#   cd /path/to/workspace
#   /path/to/sample-ai-modernization-flow/install.sh --project <name> [options]
#
# Options:
#   --project <name>      Project name (required). Creates <name>-migration-<YYYYMMDD>/
#   --lang <ja|en>        Language of the installed rules and scaffolding, and of the
#                         closing guidance (default: ja). Selects the ja/ or en/ tree
#                         of this repository. ja/ is the source of truth; en/ is
#                         generated. Progress and error output is English
#   --tool <kiro|claude-code|both>
#                         Tool to install rules for (default: both)
#   --playbook <name|path>
#                         Specify the Playbook layer. A name under the selected
#                         language tree's playbooks/ directory (e.g.
#                         clang-solarisx86-to-amznlinux) or a path. If omitted:
#                         auto-selected if playbooks/ contains exactly one entry
#   --skip-project        Skip generating the migration project scaffold
#                         (only reinstall/update the rules -- core and skills).
#                         **It does not touch anything inside the records
#                         repository.** To update those files use
#                         --update-project
#   --update-project [<dir>]
#                         Update an existing records repository to this
#                         framework version, and reinstall the rules.
#                         Files carrying no project data are regenerated;
#                         files carrying project data are never touched --
#                         the new templates are staged under
#                         .flow-update-<version>/ at the same relative paths
#                         so you can merge by hand, then delete the directory.
#                         <dir> may be omitted when exactly one
#                         <name>-migration-<date>/ exists (or pass --project
#                         <name> to disambiguate). The overwrite/preserve
#                         lists are documented in harness/README.md
#   --no-turn-log         Disable turn-timestamp recording (default: on).
#                         Turn recording installs 03-worklog/turn-log.sh +
#                         turn-report.sh and wires the tool hooks. Only the
#                         timestamp, the event name and the session id are
#                         stored -- never the prompt text.
#                         Kiro: generates .kiro/agents/migration.json; start
#                         with `kiro-cli chat --agent migration` (hooks are
#                         only read from the active agent).
#   --no-work-guard       Disable the declaration guard (default: on).
#                         The guard blocks the first edit of a turn until the
#                         session context carries a declaration for that turn.
#                         Enforces the interruption-tolerance rule at the
#                         moment it applies: before the first code contact.
#
# Example:
#   ./sample-ai-modernization-flow/install.sh --project myapp-1.0 \
#       --playbook java-modernization --lang ja
#
# What gets installed:
#   Kiro:        .kiro/steering/migration-core.md (common rules, overwritten on update)
#                .kiro/steering/migration-project.md (project-specific, generated only once)
#                .kiro/skills/migration-*/SKILL.md (detailed procedures, overwritten on update)
#   Claude Code: CLAUDE.md (project-specific + common rules, generated only once)
#                .claude/skills/migration-*/SKILL.md (overwritten on update)
#   Common:      <name>-migration-<YYYYMMDD>/ (worklog/plan/verification scaffold + git init)
#
# On Windows (Git Bash / MSYS2 / Cygwin):
#   The hook `command` is written as `bash "<path>"` instead of a bare .sh path,
#   because the tools' hook runners start the command through the native Windows
#   process API, which does not honour a shebang -- a bare .sh path never starts and
#   the hook fails silently. A preflight prints what this host needs; see
#   harness/README.md, "Running on Windows".
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# Framework version (single source of truth: the VERSION file at the repository root)
HARNESS_VERSION="$(cat "$REPO_DIR/VERSION" 2>/dev/null | head -1 | tr -d '[:space:]')"
[ -n "$HARNESS_VERSION" ] || HARNESS_VERSION="unknown"
WORKSPACE="$(pwd)"
DATE="$(date +%Y%m%d)"

# Windows (Git Bash / MSYS2 / Cygwin) needs the interpreter spelled out in a hook
# `command`: the tools' hook runners start it through the native Windows process API,
# which does not honour a shebang, so a bare `.sh` path never starts and the hook fails
# **silently** on every turn (LL-2 -- measured, cost four sessions to find).
#
# Detected once, here, on the host whose hooks these will be. On POSIX hosts every
# generated file stays byte-identical to before this branch existed. `FLOW_IS_WINDOWS`
# exists to force either side when verifying exactly that.
IS_WINDOWS=0
case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
esac
IS_WINDOWS="${FLOW_IS_WINDOWS:-$IS_WINDOWS}"

PROJECT_NAME=""
TOOL="both"
PLAYBOOK_ARG=""
SKIP_PROJECT=0
LANG_SEL="ja"
TURN_LOG=1
WORK_GUARD=1
DO_UPDATE=0
UPDATE_ARG=""
# Set by section 3b; next_steps() reads it, so give it a value for `set -u`
UP_STAGE_REL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project)  PROJECT_NAME="$2"; shift 2 ;;
    --lang)     LANG_SEL="$2"; shift 2 ;;
    --tool)     TOOL="$2"; shift 2 ;;
    --playbook) PLAYBOOK_ARG="$2"; shift 2 ;;
    --skip-project) SKIP_PROJECT=1; shift ;;
    # The directory is optional: it is resolved the same way --turn-log resolves it when
    # omitted. Updating a project never generates a new scaffold, so it implies --skip-project.
    --update-project)
      DO_UPDATE=1; SKIP_PROJECT=1; shift
      if [ $# -gt 0 ]; then
        case "$1" in --*) ;; *) UPDATE_ARG="$1"; shift ;; esac
      fi
      ;;
    --turn-log) TURN_LOG=1; shift ;;     # kept for backwards compat
    --no-turn-log) TURN_LOG=0; shift ;;
    # The guard reads the turn timestamps, so it cannot work without the collection
    --work-guard) WORK_GUARD=1; TURN_LOG=1; shift ;;  # kept for backwards compat
    --no-work-guard) WORK_GUARD=0; shift ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

case "$LANG_SEL" in
  ja|en) ;;
  *) echo "Error: --lang must be 'ja' or 'en' (got: $LANG_SEL)" >&2; exit 1 ;;
esac

# --- Messages ------------------------------------------------------------------
# The message table is English. Only next_steps() -- the closing guidance the user acts on --
# follows --lang, plus the two errors below that ask the user to *do* something.
msg() {  # $1=key, $2.. = printf arguments
  local k="$1"; shift
  local f=""
  case "$k" in
    title)         f='=== AI Modernization Flow Install ===' ;;
    f_version)     f='  Version:   %s' ;;
    f_workspace)   f='  Workspace: %s' ;;
    f_language)    f='  Language:  %s  (%s)' ;;
    f_tool)        f='  Tool:      %s' ;;
    f_playbook)    f='  Playbook:  %s' ;;
    not_specified) f='(not specified)' ;;
    kiro_gen)      f='  [kiro] Generated .kiro/steering/migration-project.md (the <PLACEHOLDER> entries are filled in by the startup interview)' ;;
    kiro_kept)     f='  [kiro] migration-project.md already exists, keeping it' ;;
    kiro_done)     f='  [kiro] Installed/updated steering(core) + skills' ;;
    cc_gen)        f='  [claude-code] Generated CLAUDE.md (the <PLACEHOLDER> entries are filled in by the startup interview)' ;;
    cc_kept)       f='  [claude-code] CLAUDE.md already exists, keeping it (merge core discipline updates manually)' ;;
    cc_done)       f='  [claude-code] Installed/updated skills' ;;
    pb_copied)     f='  [playbook] Copied knowledge and domain viewpoints from %s' ;;
    pb_none)       f='  [playbook] Not specified. Place docs/knowledge/practices.md, analysis-appendix.md, etc. separately' ;;
    proj_created)  f='  [project] Created %s + git init' ;;
    done)          f='=== Done ===' ;;
    tl_installed)  f='  [turn-log] Installed into %s and wired the hooks (timestamp, event and session id only -- never the prompt text)' ;;
    tl_no_python)  f='  [turn-log] No working python3/python found -- turn-log/work-guard hooks will silently no-op (fail-open) until one is on PATH' ;;
    tl_wired)      f='  [turn-log] Configuration: %s (a copy is kept in 03-worklog/hooks/; the live files sit outside git)' ;;
    tl_cc_manual)  f='  [turn-log] Could not update .claude/settings.json automatically. Merge %s by hand' ;;
    # Windows preflight. Every line is a warning, never a failure: each condition still
    # leaves a usable install, and stopping here would be worse than saying what to expect.
    w_no_atx)      f='  [atx] NOTE: `atx` is not on PATH. It is needed only when Phase 0a runs the analysis, not when importing existing results. On Windows it must be visible from Git Bash' ;;
    w_detected)    f='  [windows] Git Bash/MSYS/Cygwin detected -- hook commands are written as `bash "<path>"` (a bare .sh path does not start on Windows)' ;;
    w_no_bash)     f='  [windows] WARNING: `where bash` finds nothing in the native PATH, so the hook command cannot start. Put the Git Bash bin directory on the Windows PATH, or edit the hook command to an absolute bash path' ;;
    w_home_diff)   f='  [windows] NOTE: $HOME (%s) and %%USERPROFILE%% (%s) differ. Anything you install under ~/ is invisible to native-Windows tools (a portable JDK there cost one project 30 billed agent-minutes). Install toolchains under %%USERPROFILE%%' ;;
    w_python)      f='  [windows] Hint: `python3` on Windows is usually the WindowsApps App Execution Alias stub, which is found but does not run. A real interpreter is normally named `python`' ;;
    wg_installed)  f='  [work-guard] Edits are blocked until a declaration exists (generate the line with turn-report.sh --declare)' ;;
    tl_commit)     f='  [turn-log] The files added above are uncommitted. Commit them in %s (repo-sync treats untracked files as a failure)' ;;
    up_target)     f='  [update] Target: %s' ;;
    up_from_to)    f='  [update] Installed from %s -> updating to %s' ;;
    up_over)       f='      regenerated: %s' ;;
    up_same)       f='      already current: %s' ;;
    up_stage)      f='      needs a merge: %s' ;;
    up_orphan)     f='      no longer part of the framework (left in place): %s' ;;
    up_over_head)  f='  [update] Regenerated -- these carry no project data:' ;;
    up_stage_head) f='  [update] Left untouched -- these carry your project data. The new template is staged under %s (same relative paths). Merge, then delete the directory:' ;;
    up_none_stage) f='  [update] Nothing to merge by hand: every file carrying project data already matches this version' ;;
    up_summary)    f='  [update] %s regenerated, %s staged for a manual merge, %s already current' ;;
    up_stamp)      f='  [update] The gate records the version it came from: grep "ai-modernization-flow" %s/verify.sh' ;;
    up_no_pb)      f='  [update] No --playbook given, so the Playbook-owned files (practices.md, analysis-appendix.md, baseline-themes.md, verify-snippets.md, docs/reference/, the transform-config and gitignore templates) were skipped. Re-run with --playbook <name> to update them' ;;
    up_untracked)  f='  [update] The files written above are uncommitted. Review and commit them in %s (repo-sync treats untracked files as a failure)' ;;
    e_usage)       f='Usage: %s --project <name> [--lang ja|en] [--tool kiro|claude-code|both] [--playbook <name|path>] [--skip-project] [--update-project [<dir>]] [--no-turn-log] [--no-work-guard]' ;;
    e_pb_missing)  f='Error: playbook not found: %s' ;;
    e_pb_avail)    f='  Available: %s' ;;
    e_dir_exists)  f='Error: Directory already exists: %s' ;;
    e_up_nodir)    f='Error: --update-project could not resolve the records repository. Pass the directory, or --project <name>, or run where exactly one <name>-migration-<date>/ exists' ;;
    e_up_notproj)  f='Error: %s does not look like a records repository (no verify.sh). Refusing to touch it' ;;
    # Localised exceptions: these two ask the user to change what they are doing, so they
    # follow --lang. Every other message stays English.
    e_workspace)
      if [ "$LANG_SEL" = "ja" ]; then
        f='エラー: ワークスペースのルートで実行してください（フレームワーク自身のリポジトリ内では実行できません）'
      else
        f='Error: Please run this from the workspace root (not inside the framework'"'"'s own repository)'
      fi
      ;;
    e_tl_records)
      if [ "$LANG_SEL" = "ja" ]; then
        f='エラー: --turn-log には記録リポジトリが必要です。--project を指定するか、<名前>-migration-<日付>/ が1つだけある状態で実行してください'
      else
        f='Error: --turn-log needs the records repository. Pass --project, or run where exactly one <name>-migration-<date>/ exists'
      fi
      ;;
    *)             f="(unknown message key: ${k})" ;;
  esac
  # shellcheck disable=SC2059
  printf "${f}\n" "$@"
}

# The closing guidance is kept as one block per language rather than per line, because it only reads
# naturally as continuous prose. This is the only place with Japanese text, so the bash 3.2 + set -u
# rule applies here: always brace ${VAR}. A full-width character immediately after $VAR is absorbed
# into the variable name, and the script then exits 1 with no visible error.
next_steps() {
  # An update is not a fresh start, so the startup-interview guidance below would be wrong advice.
  # Only one thing cannot be left to the docs: the merge direction for verify.sh.
  if [ "$DO_UPDATE" -eq 1 ]; then
    if [ "$LANG_SEL" = "ja" ]; then
      cat <<EOS

次にやること:
  ${UP_STAGE_REL}/ を自分のコピーへマージし、ディレクトリを削除してください。
  **期待リスト・BUILD_CMD・smoke / integration の実装は自分の verify.sh にしかありません。**
  それらを ${UP_STAGE_REL}/verify.sh へ移す方向でマージします（逆向きは次回も同じ作業になります）。
  上書き/保持の一覧と手順: harness/README.md「ハーネスの更新」
EOS
    else
      cat <<EOS

Next steps:
  Merge ${UP_STAGE_REL}/ into your own copies, then delete the directory.
  **Your expected list, BUILD_CMD and smoke / integration implementations exist only in your
  verify.sh.** Merge by moving those into ${UP_STAGE_REL}/verify.sh, not the other way round
  (the reverse means doing this again next time).
  Overwrite/preserve lists and the procedure: harness/README.md, "Updating the Harness"
EOS
    fi
    return 0
  fi
  if [ "$LANG_SEL" = "ja" ]; then
    cat <<EOS

次にやること:
  <PLACEHOLDER> を手で埋める必要はありません。最初のセッションでエージェントが起動インタビューを
  行い、ソースツリーを走査して埋められるところを埋め、残りを一度だけ質問します。
  開始に必要なのは「対象ソースのルートパス」と「off-limits」だけです。
  移行先スタックは未定でかまいません（Phase 0b で分析結果を見てから決めます）。

  このディレクトリ（ワークスペースのルート）でエージェントを起動し、次のいずれかを指示してください:
    A. アセスメントを新規に開始する:
         <ソースのパス> のアセスメントを開始します。
         00-analysis/analysis-procedure.md の Phase 0a に従い、リポジトリ棚卸しから始めてください。
         移行先スタックは未定です。分析結果を見てから決めます。
    B. 既存の ATX 分析結果を使う（実行はしない）:
         ATX の分析結果が <結果のパス> にすでにあります。
         Phase 0a は実行ではなく取り込み（ingest）として進めてください。
         → git 準備・transform-config 作成・ATX 実行はスキップされます（0a-0）
    C. アセスメントの後に移行へ進む:  Phase 0b から続けてください。
    D. 次のセッションを再開する:  03-worklog/session-context.md を読んで続きから進めてください。

  指示文の全文は ${LANG_SEL}/harness/README.md の「エージェントへの最初の指示」を参照してください。
  アセスメントのみの利用も可能です。Phase 0a の終わり（分析結果そのもの）でも、
  Phase 0b の終わり（移行するかの判断材料）でも終了できます。
EOS
    if [ "$TURN_LOG" -eq 1 ]; then
      echo "  ターン時刻の記録を有効にしました。"
      if [ "$TOOL" = "kiro" ] || [ "$TOOL" = "both" ]; then
        cat <<EOS
  **Kiro では起動時にエージェントを明示してください**
  （既定起動は組み込みエージェントを使い、hook を持てないため何も記録されません）:
    cd $(pwd) && kiro-cli chat --agent migration
EOS
      fi
      echo "    ./${RECORDS_REL:-<project>-migration-<date>}/03-worklog/turn-report.sh --list   # 記録の確認"
    fi
  else
    cat <<EOS

Next steps:
  You do NOT have to fill in the <PLACEHOLDER> entries by hand. On the first session the agent runs a
  startup interview: it scans the source tree, fills in what it can, and asks once for the rest.
  All you need to start is the source root path and the off-limits list.
  The migration target stack can stay undecided (it is decided in Phase 0b).

  Start the AI agent from this directory (the workspace root) and give it one of:
    A. Assessment from scratch:
         Start the assessment of <source path>.
         Follow Phase 0a in 00-analysis/analysis-procedure.md, beginning with the repository inventory.
         The target stack is undecided; we will decide after seeing the analysis.
    B. Reuse existing ATX analysis results (do not run them):
         The ATX analysis results are already at <results path>.
         Take Phase 0a as an ingest rather than a run.
         -> the git preparation, the transform-config and running ATX are all skipped (0a-0)
    C. Proceed to migration after the assessment:  Continue from Phase 0b.
    D. Resume a later session:  Read 03-worklog/session-context.md and continue from there.

  See "Initial Instruction to the Agent" in ${LANG_SEL}/harness/README.md for the full wording.
  Assessment-only use is supported: you can stop at the end of Phase 0a (the analysis results
  themselves) or at the end of Phase 0b (material for the go/no-go decision).
EOS
    if [ "$TURN_LOG" -eq 1 ]; then
      echo "  Turn timestamps are enabled."
      if [ "$TOOL" = "kiro" ] || [ "$TOOL" = "both" ]; then
        cat <<EOS
  **Name the agent when you start Kiro** (the default launch uses the built-in agent, which
  cannot carry hooks, so nothing would be recorded):
    cd $(pwd) && kiro-cli chat --agent migration
EOS
      fi
      echo "    ./${RECORDS_REL:-<project>-migration-<date>}/03-worklog/turn-report.sh --list   # check"
    fi
  fi
}

LANG_DIR="$REPO_DIR/$LANG_SEL"
if [ ! -d "$LANG_DIR" ]; then
  echo "Error: language tree not found: $LANG_DIR" >&2
  echo "  ja/ is the source of truth; en/ is generated by tools/build-en.sh" >&2
  exit 1
fi
HARNESS_DIR="$LANG_DIR/harness"
PLAYBOOKS_DIR="$LANG_DIR/playbooks"
METHOD_DIR="$LANG_DIR/method"
for d in "$HARNESS_DIR" "$METHOD_DIR"; do
  [ -d "$d" ] || { echo "Error: incomplete language tree, missing: $d" >&2; exit 1; }
done

if [ -z "$PROJECT_NAME" ] && [ "$SKIP_PROJECT" -eq 0 ]; then
  msg e_usage "$0" >&2
  exit 1
fi

if [ "$REPO_DIR" = "$WORKSPACE" ]; then
  msg e_workspace >&2
  exit 1
fi

# --- Resolve Playbook: name -> playbooks/<name>, path -> as-is, omitted -> auto-select if only one ---
PLAYBOOK_DIR=""
if [ -n "$PLAYBOOK_ARG" ]; then
  if [ -d "$PLAYBOOKS_DIR/$PLAYBOOK_ARG" ]; then
    PLAYBOOK_DIR="$PLAYBOOKS_DIR/$PLAYBOOK_ARG"
  elif [ -d "$PLAYBOOK_ARG" ]; then
    PLAYBOOK_DIR="$(cd "$PLAYBOOK_ARG" && pwd)"
  else
    msg e_pb_missing "${PLAYBOOK_ARG}" >&2
    msg e_pb_avail "$(ls "${PLAYBOOKS_DIR}" 2>/dev/null | tr '\n' ' ')" >&2
    exit 1
  fi
elif [ -d "$PLAYBOOKS_DIR" ] && [ "$(ls "$PLAYBOOKS_DIR" | wc -l)" -eq 1 ]; then
  PLAYBOOK_DIR="$PLAYBOOKS_DIR/$(ls "$PLAYBOOKS_DIR")"
fi

# Stamp the framework version into a generated file.
# Records which framework version the project was installed from, so that later
# knowledge backports and incident investigations can tell whether a given
# discipline existed in that version.
stamp_version() {  # $1=file
  [ -f "$1" ] || return 0
  perl -pi -e "s/<HARNESS_VERSION>/$HARNESS_VERSION/g" "$1"
}

# Resolve python3 with an absolute path first (a bare command name can be hijacked
# through PATH). Same rule as the harness tools (CP-12).
#
# Every candidate is actually executed before being trusted: on Windows, `python3`
# (and sometimes `python`) on PATH can resolve to the App Execution Alias stub under
# WindowsApps, which is executable (`-x` passes) but only prints "Python was not
# found..." to stderr and exits non-zero. `command -v` can't tell it apart from a
# real interpreter, so we run a no-op program and require a clean exit (LL-1).
_python_works() { "$1" -c '' >/dev/null 2>&1; }

resolve_python() {
  local cand
  for cand in /usr/bin/python3 /usr/local/bin/python3 /opt/homebrew/bin/python3; do
    if [ -x "$cand" ] && _python_works "$cand"; then echo "$cand"; return 0; fi
  done
  for cand in "$(command -v python3 2>/dev/null || true)" "$(command -v python 2>/dev/null || true)"; do
    if [ -n "$cand" ] && _python_works "$cand"; then echo "$cand"; return 0; fi
  done
  return 1
}

# Bake the resolved python path into a copied tool script, replacing the
# `__PYTHON_BIN__` placeholder. Resolution happens once here, at install time --
# the deployed script never re-resolves python at hook-firing time (which is the
# path that hit LL-1: a hook runs on every turn, so a stub misdetection there fails
# silently on every turn instead of once, loudly, during install).
stamp_python_bin() {  # $1=file  $2=resolved python path
  [ -f "$1" ] || return 0
  # Two things this line has to get right:
  #
  # 1. **Only the assignment line.** The next line of each tool script is the guard
  #    `case "$PY" in __PYTHON_BIN__|"") PY="" ;; esac`, whose job is to blank PY when the
  #    script was copied without ever being stamped. A global replace would rewrite that
  #    sentinel too, turning the guard into "if PY is the real python, blank it" -- always
  #    true -- so turn-log, turn-report and the work guard would run with no python at all,
  #    on every platform. Anchoring to `^PY="..."$` leaves the guard's sentinel alone.
  # 2. **The path goes through the environment, never into the perl program.** Interpolating
  #    it inline aborts the installer everywhere: the `/` in any real path
  #    (`/usr/bin/python3`) closes the `s///` delimiter, and `\Q...\E` does not protect a
  #    delimiter -- it applies to patterns, and this is the replacement side. A Windows
  #    path's backslashes are the second reason: a replacement built from `$ENV{}` is not
  #    re-scanned for escapes, so they survive as written.
  PY_BIN="$2" perl -pi -e 's/^PY="__PYTHON_BIN__"$/PY="$ENV{PY_BIN}"/' "$1"
}

# Turn a script path into the body of a hook's JSON `command` string -- the **only**
# place the Windows/POSIX difference is allowed to live, so that "what a hook command
# looks like" stays one decision rather than five copies of it.
#
# POSIX: the path unchanged, started by its shebang.
# Windows: `bash "<path>"`. The quotes are emitted JSON-escaped because every caller
# interpolates the result between the quotes of a JSON string; the path may also contain
# spaces, which the quoting covers as well. `bash` is left bare rather than resolved to
# an absolute path: an absolute path would bake this machine's Git install location into
# the user's settings.json and break when Git moves. The preflight checks that the native
# PATH can find it, which is the condition that makes the bare name safe.
hook_cmd() {  # $1=script path (may contain an un-expanded ${CLAUDE_PROJECT_DIR})
  if [ "$IS_WINDOWS" -eq 1 ]; then
    printf 'bash \\"%s\\"' "$1"
  else
    printf '%s' "$1"
  fi
}

# Report, once, what this Windows host will and will not do. Warnings only -- see w_*.
# Each check reads; none of them change anything.
windows_preflight() {
  [ "$IS_WINDOWS" -eq 1 ] || return 0
  msg w_detected

  # `//c`, not `/c`. MSYS rewrites a lone `/c` argument into a Windows path (`C:/`) before
  # cmd.exe sees it, so `/c` leaves cmd with no switch at all: it starts interactively,
  # prints its banner and exits 0. That makes this check pass unconditionally and puts two
  # banner lines into the captured %USERPROFILE% below -- both measured here. `//c` is the
  # documented escape and MSYS collapses it back to `/c`.
  #
  # The hook runner resolves `bash` from the *native* PATH, not from this shell's PATH,
  # so asking this shell would answer the wrong question.
  if ! cmd.exe //c "where bash" >/dev/null 2>&1; then
    msg w_no_bash
  fi

  # Git Bash's $HOME can sit on a different drive than the Windows profile (measured:
  # /h/ vs D:\Users\<user>). Tools that run as native processes see only the latter.
  local up
  up="$(cmd.exe //c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')" || up=""
  if [ -n "$up" ] && [ -n "${HOME:-}" ]; then
    local up_unix
    up_unix="$(cygpath -u "$up" 2>/dev/null || echo "$up")"
    [ "$up_unix" = "$HOME" ] || msg w_home_diff "$HOME" "$up"
  fi

  resolve_python >/dev/null 2>&1 || msg w_python
}

# Merge a hooks fragment into .claude/settings.json. **Never overwrite the file**: it
# belongs to the user and holds their own settings. The merge is additive and keyed on
# the command string, so re-running the installer is idempotent. Returns non-zero when
# it cannot be done safely (no python3, or a file we cannot parse); the caller then
# asks the user to merge the fragment by hand rather than damaging the file.
merge_claude_hooks() {  # $1=settings.json path, $2=fragment path
  local py
  py="$(resolve_python)"
  [ -n "$py" ] || return 1
  SETTINGS="$1" FRAGMENT="$2" "$py" - <<'PY'
import json, os, sys

settings_path = os.environ["SETTINGS"]
with open(os.environ["FRAGMENT"], encoding="utf-8") as f:
    fragment = json.load(f)

data = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path, encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        sys.exit(1)                       # do not touch a file we cannot parse
    if not isinstance(data, dict):
        sys.exit(1)

hooks = data.setdefault("hooks", {})
if not isinstance(hooks, dict):
    sys.exit(1)

def commands(entries):
    found = set()
    for entry in entries if isinstance(entries, list) else []:
        if not isinstance(entry, dict):
            continue
        for h in entry.get("hooks", []) or []:
            if isinstance(h, dict) and h.get("command"):
                found.add(h["command"])
    return found

for event, entries in fragment.get("hooks", {}).items():
    current = hooks.setdefault(event, [])
    if not isinstance(current, list):
        sys.exit(1)
    wired = commands(current)
    for entry in entries:
        if commands([entry]) & wired:
            continue                      # already wired
        current.append(entry)

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
}

PROJECT_DIR="${WORKSPACE}/${PROJECT_NAME}-migration-${DATE}"

# --- The project file map ------------------------------------------------------
# **One list, read by both the install path (section 3) and the update path (section 3b).**
# Keeping two lists produced two silent omissions on the day it was written (the Playbook's
# transform-config and modernized-gitignore templates were never updated), which is the same
# failure mode --update-project exists to fix. Adding a row here is all a new file needs.
#
#   dst | src | policy | attrs
#
#   policy  managed  the user never writes into it, so --update-project regenerates it
#           staged   the user writes into it (expected list, ADRs, ledger rows,
#                    CP-<project>-N additions). --update-project never touches it and puts
#                    the new template under .flow-update-<version>/ instead
#   attrs   dir      src is a directory; its contents are copied into dst
#           exec     chmod +x after copying (for a dir: the *.sh inside it)
#           stamp    replace <HARNESS_VERSION> with the framework version
#
# core / skills / migration-project.md / CLAUDE.md are not here: they live outside the records
# repository and follow a different rule ("generate once, then keep").
PROJECT_FILE_MAP=(
  "verify.sh|${HARNESS_DIR}/verify.sh.template|staged|exec stamp"
  "setup-modernized.sh|${HARNESS_DIR}/setup-modernized.sh|managed|exec"
  "00-analysis|${METHOD_DIR}/tools|managed|dir exec"
  "00-analysis/analysis-procedure.md|${METHOD_DIR}/analysis-procedure.md.template|managed|"
  "00-analysis/repository-inventory.md|${HARNESS_DIR}/templates/project-seed/00-analysis/repository-inventory.md|staged|"
  "00-analysis/analysis-runs.md|${HARNESS_DIR}/templates/project-seed/00-analysis/analysis-runs.md|staged|"
  "01-plan/work-plan.md|${HARNESS_DIR}/templates/project-seed/01-plan/work-plan.md|staged|"
  "01-plan/adaptation-ledger.md|${HARNESS_DIR}/templates/project-seed/01-plan/adaptation-ledger.md|staged|"
  "01-plan/environment-diff-table.md|${HARNESS_DIR}/templates/project-seed/01-plan/environment-diff-table.md|staged|"
  "02-test/test-procedures.md|${HARNESS_DIR}/templates/project-seed/02-test/test-procedures.md|staged|"
  "02-test/baseline-behavior.md|${HARNESS_DIR}/templates/baseline-behavior.md.template|staged|"
  "03-worklog/session-context.md|${HARNESS_DIR}/templates/session-context.md.template|staged|"
  "03-worklog/worklog.md|${HARNESS_DIR}/templates/project-seed/03-worklog/worklog.md|staged|"
  "03-worklog/templates/subtask-plan.md.template|${HARNESS_DIR}/templates/subtask-plan.md.template|managed|"
  "docs/decisions/decisions.md|${HARNESS_DIR}/templates/decisions.md.template|staged|"
  "docs/knowledge/lessons-learned.md|${HARNESS_DIR}/templates/lessons-learned.md.template|staged|"
  "docs/knowledge/practices-common.md|${METHOD_DIR}/practices-common.md|staged|"
  ".gitignore|${HARNESS_DIR}/templates/project-seed/gitignore.template|staged|"
)
# Playbook rows are appended only when a Playbook was resolved, so an absent Playbook cannot
# produce rows pointing at "/practices.md" and friends.
if [ -n "$PLAYBOOK_DIR" ]; then
  PROJECT_FILE_MAP=("${PROJECT_FILE_MAP[@]}"
    "docs/knowledge/practices.md|${PLAYBOOK_DIR}/practices.md|staged|"
    "docs/reference|${PLAYBOOK_DIR}/reference|managed|dir"
    "00-analysis/analysis-appendix.md|${PLAYBOOK_DIR}/analysis-appendix.md|staged|"
    "00-analysis/transform-config-cca-template.yaml|${PLAYBOOK_DIR}/transform-config-cca-template.yaml|managed|"
    "02-test/baseline-themes.md|${PLAYBOOK_DIR}/baseline-themes.md|staged|"
    "02-test/verify-snippets.md|${PLAYBOOK_DIR}/verify-snippets.md|staged|"
    "modernized-gitignore.template|${PLAYBOOK_DIR}/modernized-gitignore.template|managed|"
  )
fi

# Split one map row into pf_dst / pf_src / pf_pol / pf_att (set as globals; bash 3.2 has no
# associative arrays, so a `dst|src|policy|attrs` string is the portable form).
map_row() {  # $1=row
  local rest
  pf_dst="${1%%|*}"; rest="${1#*|}"
  pf_src="${rest%%|*}"; rest="${rest#*|}"
  pf_pol="${rest%%|*}"; pf_att="${rest#*|}"
}
map_has_attr() {  # $1=attrs, $2=attr
  case " $1 " in *" $2 "*) return 0 ;; esac
  return 1
}
# Copy one row into a destination root, honouring dir / exec / stamp.
map_place() {  # $1=root
  if map_has_attr "$pf_att" dir; then
    mkdir -p "$1/$pf_dst"
    cp -R "$pf_src/." "$1/$pf_dst/"
    if map_has_attr "$pf_att" exec; then chmod +x "$1/$pf_dst/"*.sh 2>/dev/null || true; fi
  else
    mkdir -p "$(dirname "$1/$pf_dst")"
    cp "$pf_src" "$1/$pf_dst"
    if map_has_attr "$pf_att" exec; then chmod +x "$1/$pf_dst"; fi
  fi
  if map_has_attr "$pf_att" stamp; then stamp_version "$1/$pf_dst"; fi
}

# --- Resolve the --update-project target *before* installing anything -----------
# A wrong target must cost nothing. Resolving it here means the rules are not reinstalled and
# no file is touched when the records repository cannot be identified.
UPDATE_DIR=""
if [ "$DO_UPDATE" -eq 1 ]; then
  if [ -n "$UPDATE_ARG" ]; then
    if [ -d "$UPDATE_ARG" ]; then UPDATE_DIR="$(cd "$UPDATE_ARG" && pwd)"; fi
  else
    # Same resolution rule as --turn-log: accept exactly one candidate, never guess between several
    if [ -n "$PROJECT_NAME" ]; then
      set -- "$WORKSPACE/$PROJECT_NAME"-migration-*
    else
      set -- "$WORKSPACE"/*-migration-*
    fi
    if [ "$#" -eq 1 ] && [ -d "$1" ]; then UPDATE_DIR="$1"; fi
  fi
  [ -n "$UPDATE_DIR" ] || { msg e_up_nodir >&2; exit 1; }
  # verify.sh is the one file every records repository has. Without it this is not a project
  # directory, and writing into an arbitrary directory is worse than doing nothing.
  [ -f "$UPDATE_DIR/verify.sh" ] || { msg e_up_notproj "${UPDATE_DIR}" >&2; exit 1; }
fi

PLAYBOOK_SHOWN="${PLAYBOOK_DIR}"
[ -n "${PLAYBOOK_SHOWN}" ] || PLAYBOOK_SHOWN="$(msg not_specified)"
msg title
msg f_version   "${HARNESS_VERSION}"
msg f_workspace "${WORKSPACE}"
msg f_language  "${LANG_SEL}" "${LANG_DIR}"
msg f_tool      "${TOOL}"
msg f_playbook  "${PLAYBOOK_SHOWN}"
windows_preflight
command -v atx >/dev/null 2>&1 || msg w_no_atx

# -----------------------------------------------------------------------------
# 1. Kiro: steering + skills
# -----------------------------------------------------------------------------
if [ "$TOOL" = "kiro" ] || [ "$TOOL" = "both" ]; then
  mkdir -p "$WORKSPACE/.kiro/steering" "$WORKSPACE/.kiro/skills"
  cp "$HARNESS_DIR/core/migration-core.md" "$WORKSPACE/.kiro/steering/migration-core.md"
  cp -R "$HARNESS_DIR/skills/." "$WORKSPACE/.kiro/skills/"
  if [ ! -f "$WORKSPACE/.kiro/steering/migration-project.md" ]; then
    cp "$HARNESS_DIR/templates/migration-project.md.template" \
       "$WORKSPACE/.kiro/steering/migration-project.md"
    stamp_version "$WORKSPACE/.kiro/steering/migration-project.md"
    msg kiro_gen
  else
    msg kiro_kept
  fi
  msg kiro_done
fi

# -----------------------------------------------------------------------------
# 2. Claude Code: CLAUDE.md + skills
# -----------------------------------------------------------------------------
if [ "$TOOL" = "claude-code" ] || [ "$TOOL" = "both" ]; then
  mkdir -p "$WORKSPACE/.claude/skills"
  cp -R "$HARNESS_DIR/skills/." "$WORKSPACE/.claude/skills/"
  if [ ! -f "$WORKSPACE/CLAUDE.md" ]; then
    {
      cat "$HARNESS_DIR/templates/migration-project.md.template"
      echo ""
      echo "---"
      echo ""
      cat "$HARNESS_DIR/core/migration-core.md"
    } > "$WORKSPACE/CLAUDE.md"
    stamp_version "$WORKSPACE/CLAUDE.md"
    msg cc_gen
  else
    msg cc_kept
  fi
  msg cc_done
fi

# -----------------------------------------------------------------------------
# 3. Generate the migration project scaffold
# -----------------------------------------------------------------------------
if [ "$SKIP_PROJECT" -eq 0 ]; then
  if [ -d "$PROJECT_DIR" ]; then
    msg e_dir_exists "${PROJECT_DIR}" >&2
    exit 1
  fi

  mkdir -p "$PROJECT_DIR"/{00-analysis,01-plan,02-test/test-results/baseline,02-test/integration,03-worklog/templates}
  mkdir -p "$PROJECT_DIR"/docs/{reference,knowledge,decisions}

  # Every file inside the records repository comes from PROJECT_FILE_MAP -- the same list the
  # update path reads. A file missing from the selected language tree or Playbook is skipped
  # rather than fatal, because a Playbook is optional and trees evolve.
  for row in "${PROJECT_FILE_MAP[@]}"; do
    map_row "$row"
    [ -e "$pf_src" ] || continue
    map_place "$PROJECT_DIR"
  done

  if [ -n "$PLAYBOOK_DIR" ]; then
    msg pb_copied "${PLAYBOOK_DIR}"
  else
    msg pb_none
  fi
fi

# -----------------------------------------------------------------------------
# 3b. Update an existing records repository (--update-project)
# -----------------------------------------------------------------------------
# `--skip-project` updates only the rules, so without this an existing project keeps its old
# verify.sh while the user believes the update landed (measured: seven files hand-synced).
#
# One criterion splits every file: does the user write into it?
#   regenerated  no -- overwriting loses nothing
#   staged       yes -- merging is a judgment, so the new template goes to
#                .flow-update-<version>/ at the same relative path and the copy is untouched
# Nothing is ever deleted; a file that left the framework is only reported.
# Rationale and the full lists: harness/README.md "Updating the Harness".
if [ "$DO_UPDATE" -eq 1 ]; then
  # The stamp is the only machine-readable record of which version the gates came from.
  # A missing stamp reports "unstamped" rather than a wrong version.
  UP_OLD_VER="$(grep '^# ai-modernization-flow ' "$UPDATE_DIR/verify.sh" 2>/dev/null | head -1 | awk '{print $3}' || true)"
  [ -n "$UP_OLD_VER" ] || UP_OLD_VER="unstamped"

  UP_STAGE_REL=".flow-update-${HARNESS_VERSION}"
  UP_STAGE="$UPDATE_DIR/$UP_STAGE_REL"

  msg up_target  "${UPDATE_DIR}"
  msg up_from_to "${UP_OLD_VER}" "${HARNESS_VERSION}"

  UP_N_OVER=0; UP_N_STAGE=0; UP_N_SAME=0
  UP_OVER_LIST=""; UP_STAGE_LIST=""; UP_SAME_LIST=""; UP_ORPHAN_LIST=""

  # PROJECT_FILE_MAP is the same list the install path uses; only the treatment differs here.
  for row in "${PROJECT_FILE_MAP[@]}"; do
    map_row "$row"
    [ -e "$pf_src" ] || continue
    if map_has_attr "$pf_att" dir; then
      # A directory row is always managed (pure framework or domain reference content).
      # New files are added; nothing is removed -- see the orphan report below.
      [ -d "$UPDATE_DIR/$pf_dst" ] || continue
      map_place "$UPDATE_DIR"
      UP_OVER_LIST="${UP_OVER_LIST}${pf_dst}/"$'\n'
      UP_N_OVER=$((UP_N_OVER+1))
      continue
    fi
    # A file the project does not have is not silently added: the layout may be intentional
    # (no Playbook, an older scaffold). It is reported by its absence from every list.
    [ -f "$UPDATE_DIR/$pf_dst" ] || continue
    if [ "$pf_pol" = "managed" ]; then
      map_place "$UPDATE_DIR"
      UP_OVER_LIST="${UP_OVER_LIST}${pf_dst}"$'\n'
      UP_N_OVER=$((UP_N_OVER+1))
    else
      # Ignore the stamp line when comparing: it is metadata, not content to reconcile.
      if diff -q \
           <(grep -v '^# ai-modernization-flow ' "$UPDATE_DIR/$pf_dst") \
           <(perl -pe "s/<HARNESS_VERSION>/${HARNESS_VERSION}/g" "$pf_src" | grep -v '^# ai-modernization-flow ') \
           >/dev/null 2>&1; then
        # Content already matches, so this file *is* current: refresh its stamp. That is not
        # the same as advancing the stamp before a merge -- here there is nothing to merge, and
        # leaving it stale would make --update-project report the wrong version forever.
        if map_has_attr "$pf_att" stamp; then
          perl -pi -e "s/^# ai-modernization-flow .*/# ai-modernization-flow ${HARNESS_VERSION}/" "$UPDATE_DIR/$pf_dst"
        fi
        UP_SAME_LIST="${UP_SAME_LIST}${pf_dst}"$'\n'
        UP_N_SAME=$((UP_N_SAME+1))
      else
        map_place "$UP_STAGE"
        UP_STAGE_LIST="${UP_STAGE_LIST}${pf_dst}"$'\n'
        UP_N_STAGE=$((UP_N_STAGE+1))
      fi
    fi
  done

  # Only 00-analysis/*.sh is checked for orphans: 00-analysis also holds project files, so a
  # broader comparison would report those as no longer part of the framework.
  if [ -d "$METHOD_DIR/tools" ]; then
    for up_have in "$UPDATE_DIR/00-analysis/"*.sh; do
      [ -f "$up_have" ] || continue
      if [ ! -f "$METHOD_DIR/tools/$(basename "$up_have")" ]; then
        UP_ORPHAN_LIST="${UP_ORPHAN_LIST}00-analysis/$(basename "$up_have")"$'\n'
      fi
    done
  fi

  if [ -n "$UP_OVER_LIST" ]; then
    msg up_over_head
    printf '%s' "$UP_OVER_LIST" | while IFS= read -r up_line; do msg up_over "${up_line}"; done
  fi
  if [ -n "$UP_STAGE_LIST" ]; then
    msg up_stage_head "${UP_STAGE_REL}/"
    printf '%s' "$UP_STAGE_LIST" | while IFS= read -r up_line; do msg up_stage "${up_line}"; done
  else
    msg up_none_stage
  fi
  if [ -n "$UP_ORPHAN_LIST" ]; then
    printf '%s' "$UP_ORPHAN_LIST" | while IFS= read -r up_line; do msg up_orphan "${up_line}"; done
  fi
  if [ -z "$PLAYBOOK_DIR" ]; then msg up_no_pb; fi
  msg up_summary "${UP_N_OVER}" "${UP_N_STAGE}" "${UP_N_SAME}"
  msg up_stamp "${UPDATE_DIR}"
  msg up_untracked "${UPDATE_DIR}"
fi

# -----------------------------------------------------------------------------
# 4. Turn timestamps and the declaration guard (default: on; disable with --no-turn-log / --no-work-guard)
# -----------------------------------------------------------------------------
# Installed only together with the hook wiring, so "installed but never firing" cannot
# happen quietly. Details and pitfalls: harness/README.md and the script headers.
if [ "$TURN_LOG" -eq 1 ]; then
  RECORDS_DIR=""
  if [ -d "$PROJECT_DIR" ]; then
    RECORDS_DIR="$PROJECT_DIR"
  else
    # --skip-project on a later day: the date inside PROJECT_DIR no longer matches.
    # Accept exactly one existing records repository; never guess between several.
    if [ -n "$PROJECT_NAME" ]; then
      set -- "$WORKSPACE/$PROJECT_NAME"-migration-*
    else
      set -- "$WORKSPACE"/*-migration-*
    fi
    if [ "$#" -eq 1 ] && [ -d "$1" ]; then RECORDS_DIR="$1"; fi
  fi
  [ -n "$RECORDS_DIR" ] || { msg e_tl_records >&2; exit 1; }

  TL_DIR="$RECORDS_DIR/03-worklog"
  HOOKS_COPY_DIR="$TL_DIR/hooks"
  mkdir -p "$TL_DIR" "$HOOKS_COPY_DIR"
  cp "$HARNESS_DIR/tools/turn-log.sh"    "$TL_DIR/turn-log.sh"
  cp "$HARNESS_DIR/tools/turn-report.sh" "$TL_DIR/turn-report.sh"
  chmod +x "$TL_DIR/turn-log.sh" "$TL_DIR/turn-report.sh"

  TL_PYTHON_BIN="$(resolve_python || true)"
  if [ -z "$TL_PYTHON_BIN" ]; then
    msg tl_no_python >&2
  fi
  stamp_python_bin "$TL_DIR/turn-log.sh"    "$TL_PYTHON_BIN"
  stamp_python_bin "$TL_DIR/turn-report.sh" "$TL_PYTHON_BIN"
  msg tl_installed "${TL_DIR}"

  TL_SCRIPT_ABS="$TL_DIR/turn-log.sh"
  RECORDS_REL="$(basename "$RECORDS_DIR")"
  WIRED=""
  # Every hook command below goes through hook_cmd() -- see its comment for why.
  # Kiro on Windows is untested either way; it gets the same treatment as Claude Code
  # because `bash "<path>"` also works where a shebang would have, so it is the safe side.
  TL_HOOK_CMD="$(hook_cmd "$TL_SCRIPT_ABS")"

  # The guard's trigger is "before the first code contact", which preToolUse is the only
  # hook event to match literally.
  KIRO_GUARD_HOOK=""
  CC_GUARD_HOOK=""
  if [ "$WORK_GUARD" -eq 1 ]; then
    cp "$HARNESS_DIR/tools/work-declaration-guard.sh" "$TL_DIR/work-declaration-guard.sh"
    chmod +x "$TL_DIR/work-declaration-guard.sh"
    stamp_python_bin "$TL_DIR/work-declaration-guard.sh" "$TL_PYTHON_BIN"
    KIRO_GUARD_HOOK=",
    \"preToolUse\": [
      { \"command\": \"$(hook_cmd "${TL_DIR}/work-declaration-guard.sh")\", \"timeout_ms\": 5000 }
    ]"
    # Claude Code matches on the tool name; Kiro has no matcher and the guard filters
    # the tool itself. Bash / execute_bash is deliberately out of scope in both.
    CC_GUARD_HOOK=",
    \"PreToolUse\": [ { \"matcher\": \"Edit|Write|NotebookEdit\", \"hooks\": [ { \"type\": \"command\", \"command\": \"$(hook_cmd "\${CLAUDE_PROJECT_DIR}/${RECORDS_REL}/03-worklog/work-declaration-guard.sh")\", \"timeout\": 5 } ] } ]"
    msg wg_installed
  fi

  # Kiro: hooks are read **only from the active agent**, and the built-in agent cannot
  # carry hooks. Hence a dedicated agent -- never the user's own default.json, whose
  # contents differ per user (one was measured carrying "tools": null, which leaves the
  # agent with no tools). A custom agent inherits neither tools nor resources.
  if [ "$TOOL" = "kiro" ] || [ "$TOOL" = "both" ]; then
    mkdir -p "$WORKSPACE/.kiro/agents"
    cat > "$WORKSPACE/.kiro/agents/migration.json" <<EOJ
{
  "name": "migration",
  "description": "AI Modernization Flow (records turn timestamps through hooks)",
  "tools": ["*"],
  "resources": [
    "file://.kiro/steering/**/*.md",
    "skill://${WORKSPACE}/.kiro/skills/**/SKILL.md"
  ],
  "hooks": {
    "userPromptSubmit": [
      { "command": "${TL_HOOK_CMD}", "timeout_ms": 5000 }
    ],
    "stop": [
      { "command": "${TL_HOOK_CMD}", "timeout_ms": 5000 }
    ]${KIRO_GUARD_HOOK}
  }
}
EOJ
    cp "$WORKSPACE/.kiro/agents/migration.json" "$HOOKS_COPY_DIR/kiro-agent-migration.json"
    WIRED=".kiro/agents/migration.json"
  fi

  # Claude Code: ${CLAUDE_PROJECT_DIR} resolves to the workspace root. The fragment is
  # written to the records repository first, so a failed merge still leaves something to
  # apply by hand -- the settings file belongs to the user and is never overwritten.
  if [ "$TOOL" = "claude-code" ] || [ "$TOOL" = "both" ]; then
    mkdir -p "$WORKSPACE/.claude"
    CC_FRAGMENT="$HOOKS_COPY_DIR/claude-settings-hooks.json"
    CC_CMD="$(hook_cmd "\${CLAUDE_PROJECT_DIR}/${RECORDS_REL}/03-worklog/turn-log.sh")"
    cat > "$CC_FRAGMENT" <<EOJ
{
  "hooks": {
    "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "${CC_CMD}", "timeout": 5 } ] } ],
    "Stop":             [ { "hooks": [ { "type": "command", "command": "${CC_CMD}", "timeout": 5 } ] } ],
    "StopFailure":      [ { "hooks": [ { "type": "command", "command": "${CC_CMD}", "timeout": 5 } ] } ]${CC_GUARD_HOOK}
  }
}
EOJ
    if merge_claude_hooks "$WORKSPACE/.claude/settings.json" "$CC_FRAGMENT"; then
      WIRED="${WIRED:+${WIRED}, }.claude/settings.json"
    else
      msg tl_cc_manual "${CC_FRAGMENT}"
    fi
  fi
  [ -n "$WIRED" ] && msg tl_wired "${WIRED}"
  # On the update path the records repository is already committed, so the files added
  # here stay untracked -- and repo-sync treats untracked files as a failure.
  [ "$SKIP_PROJECT" -eq 1 ] && msg tl_commit "${RECORDS_DIR}"
fi

# -----------------------------------------------------------------------------
# 5. git init for the records repository (after every file is in place, so that
#    nothing installed above is left untracked -- the repo-sync gate fails on
#    untracked files)
# -----------------------------------------------------------------------------
if [ "$SKIP_PROJECT" -eq 0 ]; then
  ( cd "$PROJECT_DIR" && git init -q && git add -A && \
    git commit -q -m "init: Initialize ${PROJECT_NAME} migration project (ai-modernization-flow ${HARNESS_VERSION})" )
  msg proj_created "${PROJECT_DIR}"
fi

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
msg done
next_steps
