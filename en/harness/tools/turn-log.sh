#!/bin/bash
# =============================================================================
# turn-log.sh — record the start/end time of each turn from the hook (capture only)
# =============================================================================
#
# A self-reported record cannot be detected when it is forgotten, so the times are taken by the hook.
# The table is built by `turn-report.sh` (`--worklog` / `--list` / `--declare`). Capture and reporting
# are split so that the path run every turn carries no unneeded code (a capture failure cannot write
# to stdout, so its errors never surface).
#
# From the hook: receive the event JSON on stdin, append one line to the TSV and exit 0. Wired by
#   install.sh --turn-log.
#   Output: `time <TAB> raw event <TAB> session_id` appended to `03-worklog/turn-log.tsv`
#   Supported: userPromptSubmit / stop (Kiro), UserPromptSubmit / Stop / StopFailure (Claude Code)
#
# Easy to break when editing:
#   - **Write nothing to stdout.** Both tools inject the stdout of the start hook into the agent's context
#   - **Do not capture the prompt text.** The times do not need it, and capturing it would leave API
#     keys and the like in plain text
#   - **Do not normalize event names.** The case of the raw value identifies the tool
#     (`Stop` = Claude Code / `stop` = Kiro)
#   - `session_id` comes from the payload first, otherwise from the environment variable (Kiro's
#     `--no-interactive` provides only the environment variable)
#   - **Do not use externally supplied values in the file name** — that keeps sanitizing and
#     rotation unnecessary
#   - Compare `cwd` at path boundaries (a prefix match lets `<root>-EVIL` through) / umask 077 + chmod 600 /
#     prefer an absolute python3 path (against PATH hijacking) / do not write through a link /
#     strip control characters
#   - Do not use `readlink -f` / `date -d` / `stat -c` (CP-12)
#
# Known limits: the time is when the hook ran, not the instant it appeared on screen. Claude Code's
#   `Stop` does not fire when the user interrupts (on an API error it fires `StopFailure`). Kiro's
#   behavior on interruption is unverified.
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"   # the workspace root
LOG_FILE="${TURN_LOG_FILE:-$SCRIPT_DIR/turn-log.tsv}"

# install.sh resolves the absolute python path once at install time and bakes it in here
# (stamp_python_bin). This path runs every turn, so it does not re-resolve `command -v python3` --
# otherwise the bug that mistakes the Windows App Execution Alias stub for the real binary (LL-1)
# would turn a one-time mistake at install into a silent failure on every turn
PY="__PYTHON_BIN__"
case "$PY" in __PYTHON_BIN__|"") PY="" ;; esac

umask 077   # file mode 600. Removes the dependency on the caller's umask

TS="$(date '+%Y-%m-%dT%H:%M:%S%z')"
PAYLOAD="$(cat 2>/dev/null || true)"

EVENT=""; SESSION=""; CWD=""
if [ -n "$PY" ]; then
  # `session_id` comes **from the payload first, otherwise from the environment variable**.
  # Kiro's `--no-interactive` does not pass `session_id` in the payload, only in the environment
  # variable (observed). Removing this leaves the third column empty for non-interactive launches.
  PARSED="$(printf '%s' "$PAYLOAD" | "$PY" -c '
import json, os, sys

try:
    d = json.load(sys.stdin)
    if not isinstance(d, dict):
        d = {}
except Exception:
    d = {}

raw = str(d.get("hook_event_name", ""))
session = str(d.get("session_id", "") or "") or os.environ.get("KIRO_SESSION_ID", "")

def clean(s):
    # Strip control characters (C0 and DEL) in addition to tabs and newlines
    return "".join(ch for ch in str(s) if ch >= " " and ch != "\x7f")

print("\t".join(clean(x) for x in (raw, session, d.get("cwd", ""))))
' 2>/dev/null || true)"
  if [ -n "$PARSED" ]; then
    EVENT="$(printf '%s' "$PARSED"   | cut -f1)"
    SESSION="$(printf '%s' "$PARSED" | cut -f2)"
    CWD="$(printf '%s' "$PARSED"     | cut -f3)"
  fi
fi

# Record only known events (so that invalid input, an empty stdin or events added in the future
# do not pollute the log). **Match case-insensitively** (Kiro uses lowercase, Claude Code uppercase).
case "$(printf '%s' "$EVENT" | tr 'A-Z' 'a-z')" in
  userpromptsubmit|stop|stopfailure) : ;;
  *) exit 0 ;;
esac

# The cwd from the hook can arrive in Windows native form (`D:\...`), while WORKSPACE_ROOT is in
# git-bash `pwd` form (`/d/...`). Normalize before comparing (observed: without normalization every
# entry mismatches and nothing is recorded). The drive letter is case-insensitive, and both `\` and
# `/` are accepted as separators
case "$CWD" in
  [A-Za-z]:[\\/]*)
    _drive="$(printf '%s' "${CWD%%:*}" | tr '[:upper:]' '[:lower:]')"
    _rest="${CWD#??}"
    _rest="${_rest//\\//}"
    CWD="/${_drive}${_rest}"
    ;;
esac

# Do not record events fired from outside the workspace. **Compare at path boundaries**
# (a prefix match alone lets a sibling directory such as `<root>-EVIL` through; verified).
# Record when the cwd is unavailable.
case "$CWD" in
  "" ) : ;;
  "$WORKSPACE_ROOT" | "$WORKSPACE_ROOT"/* ) : ;;
  * ) exit 0 ;;
esac

# Do not write if the target is a symbolic link (prevents swapping the target)
if [ -L "$LOG_FILE" ]; then exit 0; fi

printf '%s\t%s\t%s\n' "$TS" "$EVENT" "${SESSION:-no-session-id}" \
  >> "$LOG_FILE" 2>/dev/null || true
chmod 600 "$LOG_FILE" 2>/dev/null || true

exit 0
