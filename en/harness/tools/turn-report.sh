#!/bin/bash
# =============================================================================
# turn-report.sh — build the table and the declaration line from the captured
#                  turn timestamps (report only; read-only)
# =============================================================================
#
#   --worklog   The table to paste into the worklog (unrecorded turns only). **The pasted table is
#               the only permanent record** (the raw log is git-ignored). The trigger is in
#               skills/migration-recording
#   --list      The sessions that have records (to check that the hook is firing)
#   --declare   The at-start declaration line (the line work-declaration-guard.sh matches)
#
# The two times reported: **Duration (AI)** = prompt -> reply / **Wait (human)** = previous reply ->
#   next prompt. The wait is wall-clock time, not thinking time. Gaps over `TURN_LOG_IDLE_LIMIT`
#   seconds (default 3600) are treated as time away, excluded from the statistics and shown in
#   parentheses.
#
# Easy to break when editing:
#   - **Pair prompt -> stop, and take the start of the wait, within a session.** Measuring over
#     all turns sorted by time uses a parallel session's reply as the start and yields negative
#     values (observed: -93s)
#   - **Decide "unrecorded" by the reply time.** Deciding by the prompt time means a turn pasted
#     earlier as "in progress" is never output again after it completes, and its duration drops
#     out of the permanent record
#   - The lower bound is read by machine from the latest turn time in the worklog (nobody has to
#     remember the range)
#   - Do not use `readlink -f` / `date -d` / `stat -c` (CP-12)
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="${TURN_LOG_FILE:-$SCRIPT_DIR/turn-log.tsv}"

# install.sh bakes in the absolute python path it resolved once (see turn-log.sh)
PY="__PYTHON_BIN__"
case "$PY" in __PYTHON_BIN__|"") PY="" ;; esac

# On Windows, python encodes stdout in the console code page by default (e.g. cp1252) and raises
# UnicodeEncodeError on non-ASCII output such as the em dash. Always pin it to UTF-8, whether or
# not the output goes to a real terminal
export PYTHONIOENCODING="utf-8"

require_log() {
  if [ ! -f "$LOG_FILE" ]; then echo "No records: ${LOG_FILE}" >&2; exit 1; fi
  if [ -z "$PY" ]; then echo "python not found (re-run install.sh to resolve it)" >&2; exit 1; fi
}

# --- Build the table ----------------------------------------------------------

run_report() {  # $1 = lower bound time (may be empty)
  TURN_LOG_PATH="$LOG_FILE" TURN_LOG_SINCE="$1" "$PY" - <<'PY'
import io, os, datetime

path = os.environ["TURN_LOG_PATH"]
since_raw = os.environ.get("TURN_LOG_SINCE", "").strip()

EVENTS = {"userpromptsubmit": "prompt", "stop": "stop", "stopfailure": "stop-failure"}

def parse(ts):
    for f in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.datetime.strptime(ts, f)
        except ValueError:
            continue
    return None

def epoch(ts):
    d = parse(ts) if ts else None
    return d.timestamp() if d else None

def fmt(s):  # seconds -> human-readable form
    if s is None:
        return "—"
    if s >= 3600:
        return f"{s // 3600}h{(s % 3600) // 60:02d}m"
    if s >= 60:
        return f"{s // 60}m{s % 60:02d}s"
    return f"{s}s"

# **Upper limit of human response time**: a gap beyond this is not "time spent thinking" but
# time away from the session, so it is excluded from the statistics with the reason in the table.
IDLE_LIMIT = int(os.environ.get("TURN_LOG_IDLE_LIMIT", "3600"))  # default 1 hour

# --- Read the lines (3 columns: time / raw event / session_id) -----------------
by_session = {}   # session_id -> [(ts, event), ...]  keeps the order of appearance
order = []
for line in io.open(path, encoding="utf-8", errors="replace"):
    parts = line.rstrip("\n").split("\t")
    if len(parts) < 3:
        continue
    ts, raw, sess = parts[0], parts[1], parts[2]
    ev = EVENTS.get(raw.strip().lower())
    if ev is None:
        continue
    if sess not in by_session:
        by_session[sess] = []
        order.append(sess)
    by_session[sess].append((ts, ev))

# --- Assemble turns (pair prompt -> stop **within a session**) -----------------
# Pairing across sessions mismatches turns when parallel sessions exist.
turns = []
for sess in order:
    pending = None
    for ts, ev in by_session[sess]:
        if ev == "prompt":
            if pending is not None:
                turns.append({"s": sess, "p": pending, "e": None, "ev": "interrupted"})
            pending = ts
        else:  # stop / stop-failure
            turns.append({"s": sess, "p": pending, "e": ts, "ev": ev})
            pending = None
    if pending is not None:
        turns.append({"s": sess, "p": pending, "e": None, "ev": "open"})

turns.sort(key=lambda t: epoch(t["p"] or t["e"]) or 0.0)

# --- Compute duration and wait over **all turns** -------------------------------
# Turns before the lower bound are included in the computation. Otherwise the "wait"
# (previous reply to this prompt) of the first newly recorded row is lost.
#
# **The wait is measured from the previous reply "within the session".** Measuring over all
# turns sorted by time, a mix of parallel sessions (another tool started as a subprocess, etc.)
# **uses another session's reply as the start and yields negative values** (observed: -93s).
# "Human response time" is only defined within a single conversation.
last_stop = {}   # session -> previous reply time
for t in turns:
    a, b = epoch(t["p"]), epoch(t["e"])
    t["dur"] = int(b - a) if (a and b) else None
    t["wait"] = None
    prev = last_stop.get(t["s"])
    if t["p"] and prev:
        c, d = epoch(prev), a
        if c and d and d >= c:
            t["wait"] = int(d - c)
    # An interrupted turn (no reply time) cannot be the start of the next wait
    last_stop[t["s"]] = t["e"] if t["e"] else None

def cut_key(t):
    """Decide whether a turn is unrecorded by its **reply time** (when present).
    Deciding by the prompt time means a turn pasted earlier as "in progress" is never
    output again after it completes, and **its duration drops out of the permanent record**.
    Deciding by the reply time outputs it once more on completion and completes the record
    (the earlier row is marked "in progress", so this is an addition, not a duplicate)."""
    return epoch(t["e"] or t["p"]) or 0.0

bound = epoch(since_raw) if since_raw else None
sel = [t for t in turns if bound is None or cut_key(t) > bound]

if not sel:
    print(f"(No unrecorded turns. Last turn already in the worklog: {since_raw})")
    raise SystemExit(0)

# --- Table --------------------------------------------------------------------
with_sess = len({t["s"] for t in sel}) > 1
cols = ["#"] + (["Session"] if with_sess else []) \
     + ["Prompt (received)", "Reply (returned)", "Duration (AI)", "Wait (human)", "Notes"]
print("| " + " | ".join(cols) + " |")
print("|" + "|".join(["---"] * len(cols)) + "|")

durs, waits, excluded = [], [], []
for i, t in enumerate(sel, 1):
    note = ""
    if t["ev"] == "stop-failure":
        note = "Ended with an API error (StopFailure). Excluded from the duration statistics"
    elif t["ev"] == "interrupted":
        note = "No end record (possibly interrupted)"
    elif t["ev"] == "open":
        note = "In progress, or no end record"
    if t["p"] is None:
        note = "No start record"
    if t["dur"] is not None and t["ev"] == "stop":
        durs.append(t["dur"])
    w = "—"
    if t["wait"] is not None:
        if t["wait"] > IDLE_LIMIT:
            w = f"({fmt(t['wait'])})"
            excluded.append(t["wait"])
            note = (note + " / " if note else "") + "Break between sessions (excluded from the wait statistics)"
        else:
            w = fmt(t["wait"])
            waits.append(t["wait"])
    cells = [str(i)] + ([t["s"][:8]] if with_sess else []) \
          + [t["p"] or "—", t["e"] or "—", fmt(t["dur"]), w, note]
    print("| " + " | ".join(cells) + " |")
print()

def stat(label, xs, unit_note=""):
    if not xs:
        print(f"- **{label}**: no samples")
        return
    xs = sorted(xs)
    med = xs[len(xs) // 2] if len(xs) % 2 else (xs[len(xs) // 2 - 1] + xs[len(xs) // 2]) // 2
    print(f"- **{label}**: n={len(xs)} / median {fmt(med)} / min {fmt(xs[0])} / "
          f"max {fmt(xs[-1])} / total {fmt(sum(xs))}{unit_note}")

print("### Summary")
print()
stat("Duration (AI processing time)", durs, " (`stop-failure` excluded)")
stat("Wait (human response time)", waits, f" (gaps over {fmt(IDLE_LIMIT)} excluded)")
if excluded:
    print(f"- Long gaps excluded: {len(excluded)} ({', '.join(fmt(g) for g in sorted(excluded))})"
          f" — time away, not response time")
print()
print("⚠️ **\"Wait (human)\" is the wall-clock time until the prompt arrives. It does not match the time a person spent thinking**")
print("(it mixes reading, other work and time away). **Right after an interrupted turn there is no start point, so it shows `—`.**")
print()
src = ", ".join(f"`{s[:8]}`" for s in sorted({t["s"] for t in sel}))
rng = f"{sel[0]['p'] or sel[0]['e']} to {sel[-1]['e'] or sel[-1]['p']}"
if bound:
    rng += f" (after {since_raw}, already in the worklog)"
print(f"Source: raw log {src} / range {rng} (recorded mechanically by the hook, not self-reported)")
PY
}

worklog_report() {  # output only the turns not yet in the worklog (the source of the permanent record)
  local since wl
  wl="${TURN_LOG_WORKLOG_FILE:-$SCRIPT_DIR/worklog.md}"
  require_log
  # Lower bound = the latest turn time already written in worklog.md.
  # Read by machine **so that nobody has to remember the range** (a missed entry shows up as a
  # duplicate or a gap).
  # Note: this compares by string max, so **if the records mix several time zone offsets, the
  # maximum is not found correctly**. This framework records the local time of the host running
  # the hook throughout.
  since="$(TURN_LOG_WORKLOG="$wl" "$PY" -c '
import io, os, re
try:
    t = io.open(os.environ["TURN_LOG_WORKLOG"], encoding="utf-8", errors="replace").read()
except OSError:
    t = ""
m = re.findall(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4}", t)
print(max(m) if m else "")
' 2>/dev/null || true)"
  run_report "$since"
}

list_sessions() {  # check whether records exist (used to detect a forgotten `--agent` after the fact)
  require_log
  TURN_LOG_PATH="$LOG_FILE" "$PY" -c '
import io, os, collections
n = collections.Counter()
first, last = {}, {}
for line in io.open(os.environ["TURN_LOG_PATH"], encoding="utf-8", errors="replace"):
    p = line.rstrip("\n").split("\t")
    if len(p) < 3:
        continue
    ts, sess = p[0], p[2]
    n[sess] += 1
    first.setdefault(sess, ts)
    last[sess] = ts
for sess, c in sorted(n.items(), key=lambda kv: last[kv[0]], reverse=True):
    print(f"{sess}\t{c} lines\t{first[sess]} to {last[sess]}")
'
}

declare_line() {  # output the declaration line before starting (the line work-declaration-guard.sh matches)
  require_log
  # **This runs outside the hook, so the session cannot be identified.** Use the latest
  # `UserPromptSubmit` (correct for a single session). If it misses with parallel sessions, the
  # guard prints a message with the correct time when it blocks, so use that instead.
  TURN_LOG_PATH="$LOG_FILE" "$PY" -c '
import io, os
last = ""
for line in io.open(os.environ["TURN_LOG_PATH"], encoding="utf-8", errors="replace"):
    p = line.rstrip("\n").split("\t")
    if len(p) >= 2 and p[1].strip().lower() == "userpromptsubmit":
        last = p[0]
if not last:
    print("No records yet (the hook may not be firing. Check with --list)")
else:
    print(f"- **This turn ({last}):** <what you are about to do in this turn>")
'
}

case "${1:-}" in
  --worklog) worklog_report; exit 0 ;;
  --list)    list_sessions; exit 0 ;;
  --declare) declare_line;  exit 0 ;;
  *) echo "Usage: $0 --worklog | --list | --declare" >&2; exit 1 ;;
esac
