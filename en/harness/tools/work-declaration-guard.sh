#!/bin/bash
# =============================================================================
# work-declaration-guard.sh — enforce that the at-start declaration was written "in this turn"
# =============================================================================
#
# The recording duty fires at completion, so it cannot protect interrupted work. Hence the hook
# enforces that "a declaration exists before a modifying tool is used". **`preToolUse` is the only
# event that literally matches the trigger "before the first code contact", and it does not depend
# on the Phase** (the check on the verify.sh side runs only when dirty, i.e. after contact, and per
# implementation tree, so it does not run in Phase 0a-2).
#
# From the hook: wire to `preToolUse` (Kiro) / `PreToolUse` (Claude Code) (install.sh --work-guard).
# Check: `This turn (<T_prompt>)` exists in the "In-progress Investigation" section of `session-context.md`.
#   `T_prompt` = the last `UserPromptSubmit` **of this session** in `turn-log.tsv`.
#   The declaration line can be generated with `turn-report.sh --declare`.
#
# Pass-through conditions (fail-open; the guard must never make work impossible):
#   1. Not a modifying tool  2. `session-context.md` itself  3. No prompt record for this session
#   4. No `python3` / broken input
#   **`Bash` / `execute_bash` are out of scope** (they both read and write and cannot be classified
#   mechanically). This remains a loophole.
#
# Easy to break when editing:
#   - **Do not look at mtime.** session-context is touched often for unrelated reasons, so it would pass
#   - **Filter `T_prompt` by session.** Without the filter, a parallel session's prompt is taken as
#     this session's, and a correct declaration is blocked
#   - **Match tool names with `_`/`-` removed** (Claude Code uses `Edit`/`Write`, Kiro `fs_write`)
#   - **There is no warning mode.** stderr with exit 0 does not reach the agent (observed).
#     exit 2 stops the tool in both tools and the message reaches the agent
#   - **This script only reads** (it writes no files). Compare `cwd` at path boundaries
#   - The guard can enforce the **existence** of the declaration but **cannot make it permanent**
#     (copy it to the worklog at close-out)
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SESSION_CONTEXT="${WORK_DECL_SESSION_CONTEXT:-$SCRIPT_DIR/session-context.md}"
TURN_LOG="${TURN_LOG_FILE:-$SCRIPT_DIR/turn-log.tsv}"

# install.sh bakes in the absolute python path it resolved once (see turn-log.sh)
PY="__PYTHON_BIN__"
case "$PY" in __PYTHON_BIN__|"") PY="" ;; esac
[ -z "$PY" ] && exit 0                      # pass-through condition 4

PAYLOAD="$(cat 2>/dev/null || true)"

# Extract the tool name and the target path (the key names differ between the tools, so try candidates in order)
PARSED="$(printf '%s' "$PAYLOAD" | "$PY" -c '
import json, os, sys

try:
    d = json.load(sys.stdin)
    if not isinstance(d, dict):
        d = {}
except Exception:
    d = {}

tool = str(d.get("tool_name") or d.get("toolName") or d.get("tool") or "")
session = str(d.get("session_id", "") or "") or os.environ.get("KIRO_SESSION_ID", "")
inp  = d.get("tool_input") or d.get("toolInput") or d.get("input") or {}
if not isinstance(inp, dict):
    inp = {}
path = ""
for k in ("file_path", "filePath", "path", "notebook_path", "notebookPath"):
    v = inp.get(k)
    if isinstance(v, str) and v:
        path = v
        break

def clean(s):
    return "".join(ch for ch in str(s) if ch >= " " and ch != "\x7f")

print("\t".join(clean(x) for x in (tool, path, d.get("cwd", ""), session)))
' 2>/dev/null || true)"
[ -z "$PARSED" ] && exit 0                  # pass-through condition 4

TOOL="$(printf '%s' "$PARSED" | cut -f1)"
TARGET="$(printf '%s' "$PARSED" | cut -f2)"
CWD="$(printf '%s' "$PARSED" | cut -f3)"
SESSION="$(printf '%s' "$PARSED" | cut -f4)"

# The cwd from the hook can arrive in Windows native form (`D:\...`), while WORKSPACE_ROOT is in
# git-bash `pwd` form (`/d/...`). Normalize before comparing (see turn-log.sh)
case "$CWD" in
  [A-Za-z]:[\\/]*)
    _drive="$(printf '%s' "${CWD%%:*}" | tr '[:upper:]' '[:lower:]')"
    _rest="${CWD#??}"
    _rest="${_rest//\\//}"
    CWD="/${_drive}${_rest}"
    ;;
esac

# Ignore events fired from outside the workspace (compare at path boundaries)
case "$CWD" in
  "" ) : ;;
  "$WORKSPACE_ROOT" | "$WORKSPACE_ROOT"/* ) : ;;
  * ) exit 0 ;;
esac

# Pass-through condition 1: not a modifying tool (Bash / execute_bash are deliberately out of scope).
# **Match case-insensitively with `_`/`-` removed** — Claude Code uses `Edit`/`Write`/`NotebookEdit`,
# Kiro uses **`fs_write`** (with an underscore). This difference was found in practice, so normalization absorbs it.
case "$(printf '%s' "$TOOL" | tr 'A-Z' 'a-z' | tr -d '_-')" in
  edit|write|notebookedit|multiedit|fswrite|fsreplace) : ;;
  *) exit 0 ;;
esac

# Pass-through condition 2: editing session-context.md itself (without this the declaration cannot be written)
case "$TARGET" in
  *session-context.md) exit 0 ;;
esac

# Get T_prompt (pass-through condition 3: ignore if absent).
# **Filter by session.** All sessions append to the single `turn-log.tsv`, so without the filter
# **a parallel session's prompt (another tool started as a subprocess, etc.) is taken as this session's,
# and a correct declaration is blocked**. Fall back to the last prompt overall only when session_id is unavailable.
T_PROMPT="$(TURN_LOG_PATH="$TURN_LOG" WORK_DECL_SESSION="$SESSION" "$PY" -c '
import io, os
want = os.environ.get("WORK_DECL_SESSION", "")
scoped, any_last = "", ""
try:
    for line in io.open(os.environ["TURN_LOG_PATH"], encoding="utf-8", errors="replace"):
        p = line.rstrip("\n").split("\t")
        if len(p) >= 2 and p[1].strip().lower() == "userpromptsubmit":
            any_last = p[0]
            if want and len(p) >= 3 and p[2] == want:
                scoped = p[0]
except OSError:
    pass
print(scoped or ("" if want else any_last))
' 2>/dev/null || true)"
[ -z "$T_PROMPT" ] && exit 0

# Check the declaration: does `This turn (<T_prompt>)` exist in the section?
# `This turn (...)` is a shared anchor not translated between ja and en (this script matches it mechanically).
FOUND="$(WORK_DECL_SC="$SESSION_CONTEXT" WORK_DECL_TS="$T_PROMPT" "$PY" -c '
import io, os
path, ts = os.environ["WORK_DECL_SC"], os.environ["WORK_DECL_TS"]
needle = "This turn (" + ts + ")"
inside, found = False, False
try:
    for line in io.open(path, encoding="utf-8", errors="replace"):
        if line.startswith("## "):
            inside = "In-progress Investigation" in line
            continue
        if inside and needle in line:
            found = True
            break
except OSError:
    pass
print("1" if found else "0")
' 2>/dev/null || echo 1)"

[ "$FOUND" = "1" ] && exit 0

printf '%s\n' "⛔ No declaration before work.
   Before modifying ${TARGET} with ${TOOL}, write the following line in the
   \"In-progress Investigation / Working-tree State\" section of 03-worklog/session-context.md:

     - **This turn (${T_PROMPT}):** <what you are about to do in this turn>

   ./03-worklog/turn-report.sh --declare generates this line.
   The purpose is resilience to interruption. If work is interrupted without a declaration, what was being done is lost.
   Reusing the time of a previous turn is detected (the time is matched exactly).
   At completion, copy the declaration line to the worklog (the guard can enforce its existence but cannot make it permanent)." >&2

exit 2            # stops the tool in both tools, and the message above reaches the agent
