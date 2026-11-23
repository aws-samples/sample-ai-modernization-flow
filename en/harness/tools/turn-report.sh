#!/bin/bash
# =============================================================================
# turn-report.sh — build the table and the declaration line from the captured
#                  turn timestamps (report only; read-only)
# =============================================================================
#
#   --by-entry  AI time and human time per worklog entry (the source of `time-summary.md`).
#               A turn and an entry are joined by "prompt time = the entry's declaration line
#               `This turn (<time>)`". It is rebuilt in full every time, so overwrite and commit it
#               (do not edit by hand). The triggers (session start and session end) are in
#               skills/migration-session
#   --list      The sessions that have records (to check that the hook is firing)
#   --declare   The at-start declaration line (the line work-declaration-guard.sh matches)
#
# The two times reported: **AI working time** = prompt -> reply / **Human time** = previous reply ->
#   next prompt. Human time is wall-clock time, not thinking time. Gaps over `TURN_LOG_IDLE_LIMIT`
#   seconds (default 3600) are treated as time away, left out and shown in parentheses. A turn
#   started by a completion notification (kind notify) is treated as a continuation of the
#   previous prompt.
#
# Easy to break when editing:
#   - **Pair prompt -> stop, and take the start of the wait, within a session.** Measuring over
#     all turns sorted by time uses a parallel session's reply as the start and yields negative
#     values (observed: -93s)
#   - **Count only declaration lines at the start of a line.** Picking up quotations in
#     the body merges entries wrongly
#   - **Do not put the generation time in the output.** With no new turns there is then no diff
#     (keeps commits free of noise)
#   - Rows in the old format without a kind column (3 columns) are still read (unknown = counted
#     as a human prompt)
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

# --- Per-entry summary (--by-entry) -----------------------------------------

by_entry_report() {
  local wl
  wl="${TURN_LOG_WORKLOG_FILE:-$SCRIPT_DIR/worklog.md}"
  require_log
  TURN_LOG_PATH="$LOG_FILE" TURN_LOG_WORKLOG="$wl" "$PY" - <<'PY'
import io, os, re, datetime

path = os.environ["TURN_LOG_PATH"]
wl_path = os.environ["TURN_LOG_WORKLOG"]

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

def fmt(s):  # seconds -> human-readable
    if s is None:
        return "—"
    if s >= 3600:
        return f"{s // 3600}h{(s % 3600) // 60:02d}m"
    if s >= 60:
        return f"{s // 60}m{s % 60:02d}s"
    return f"{s}s"

# **Upper bound on human reaction time**: a gap beyond this is not "time spent thinking" but
# time away from the session, so it is left out of the human time and shown in parentheses.
IDLE_LIMIT = int(os.environ.get("TURN_LOG_IDLE_LIMIT", "3600"))  # default 1 hour

# --- Read the rows (time / raw event / session_id / kind) ---------------------
# Rows in the old format without a kind column (3 columns) get kind unknown and are counted as
# human prompts (backward compatibility).
by_session = {}   # session_id -> [(ts, event, kind), ...]  keeps the order of appearance
order = []
for line in io.open(path, encoding="utf-8", errors="replace"):
    parts = line.rstrip("\n").split("\t")
    if len(parts) < 3:
        continue
    ts, raw, sess = parts[0], parts[1], parts[2]
    kind = parts[3].strip() if len(parts) >= 4 else ""
    ev = EVENTS.get(raw.strip().lower())
    if ev is None:
        continue
    if ev == "prompt" and kind not in ("human", "notify"):
        kind = "unknown"
    if sess not in by_session:
        by_session[sess] = []
        order.append(sess)
    by_session[sess].append((ts, ev, kind))

# --- Build turns (pair prompt -> stop **within a session**) ------------------
# Pairing across sessions mismatches them when parallel sessions exist.
turns = []
for sess in order:
    pending = None   # (prompt time, kind)
    for ts, ev, kind in by_session[sess]:
        if ev == "prompt":
            if pending is not None:
                turns.append({"s": sess, "p": pending[0], "k": pending[1], "e": None, "ev": "interrupted"})
            pending = (ts, kind)
        else:  # stop / stop-failure
            turns.append({"s": sess, "p": pending[0] if pending else None,
                          "k": pending[1] if pending else "unknown", "e": ts, "ev": ev})
            pending = None
    if pending is not None:
        turns.append({"s": sess, "p": pending[0], "k": pending[1], "e": None, "ev": "open"})

turns.sort(key=lambda t: epoch(t["p"] or t["e"]) or 0.0)

# --- Duration and wait (**the wait is measured from the previous reply in the same session**) ---
# Measuring over all turns sorted by time uses a parallel session's reply as the start and
# yields negative values (observed: -93s).
last_stop = {}   # session -> previous reply time
for t in turns:
    a, b = epoch(t["p"]), epoch(t["e"])
    t["dur"] = int(b - a) if (a and b) else None
    t["wait"] = None
    prev = last_stop.get(t["s"])
    if t["p"] and prev:
        c = epoch(prev)
        if c and a and a >= c:
            t["wait"] = int(a - c)
    # An interrupted turn (no reply time) cannot be the start of the next wait
    last_stop[t["s"]] = t["e"] if t["e"] else None

# --- Turn -> declaration-line time (the matching key) -------------------------
# **A notification turn is treated as a continuation of the previous human prompt in the same
# session.** Its AI time is added there, and the wait before it is not counted as human time
# (nobody gave an instruction).
lead = {}   # session -> previous human prompt time
for t in turns:
    if t["k"] == "notify" and t["s"] in lead:
        t["key"] = lead[t["s"]]
    else:
        t["key"] = t["p"]
        if t["k"] != "notify" and t["p"]:
            lead[t["s"]] = t["p"]

# --- Read the worklog: a `## ` heading = an entry, a declaration-line time = the matching key ---
# **Only declaration lines at the start of a line count** (`- **This turn (<time>):**`).
# Picking up a quotation of another entry's declaration line in the body would wrongly merge the entry
# with the quoted one.
ANCHOR = re.compile(r"^\s*[-*]\s+\*\*This turn \((\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:[+-]\d{4})?)\):\*\*")
entries = []
try:
    for line in io.open(wl_path, encoding="utf-8", errors="replace"):
        if line.startswith("## "):
            entries.append({"h": line[3:].strip(), "anchors": []})
            continue
        m = ANCHOR.match(line)
        if m and entries:
            entries[-1]["anchors"].append(m.group(1))
except OSError:
    pass

# Entry -> row. An entry without a declaration line (the second and later entries written in one turn)
# and an entry whose declaration line already appeared are folded into the matching row.
groups, by_anchor = [], {}
for e in entries:
    known = [by_anchor[a] for a in e["anchors"] if a in by_anchor]
    if known:
        g = known[0]
    elif e["anchors"] or not groups:
        g = {"h": e["h"], "n": 0, "turns": []}
        groups.append(g)
    else:
        g = groups[-1]
    g["n"] += 1
    for a in e["anchors"]:
        by_anchor.setdefault(a, g)

none_group = {"h": "(no entry)", "n": 0, "turns": []}
for t in turns:
    (by_anchor.get(t["key"]) or none_group)["turns"].append(t)

# --- Table --------------------------------------------------------------------
def summarize(ts):
    # No samples -> None ("—"). Printing 0s would read as "measured, and it was 0"
    durs = [t["dur"] for t in ts if t["ev"] == "stop" and t["dur"] is not None]
    ai = sum(durs) if durs else None
    human_waits = [t["wait"] for t in ts if t["k"] != "notify" and t["wait"] is not None]
    kept = [w for w in human_waits if w <= IDLE_LIMIT]
    human = sum(kept) if kept else None
    idle = [w for w in human_waits if w > IDLE_LIMIT]
    c = {k: sum(1 for t in ts if cond(t)) for k, cond in (
        ("notify", lambda t: t["k"] == "notify"),
        ("fail", lambda t: t["ev"] == "stop-failure"),
        ("open", lambda t: t["ev"] == "open"),
        ("interrupted", lambda t: t["ev"] == "interrupted"),
        ("unknown", lambda t: t["k"] == "unknown"))}
    return ai, human, idle, c

def human_cell(human, idle):
    cell = fmt(human)
    if idle:
        cell += f" ({fmt(sum(idle))} away)"
    return cell

def notes(g, c):
    n = []
    if g["n"] > 1:
        n.append(f"{g['n']} entries merged")
    if c["notify"]:
        n.append(f"{c['notify']} notification(s) added to the AI side")
    if c["fail"]:
        n.append(f"{c['fail']} ended by API error (excluded from the AI time)")
    if c["open"]:
        n.append("in progress, or no end record")
    if c["interrupted"]:
        n.append(f"{c['interrupted']} possibly interrupted")
    if g["n"] and not g["turns"]:
        n.append("no matching turn (check the time in the declaration line)")
    return " / ".join(n)

print("# Turn time summary")
print()
print("<!-- Generated by turn-report.sh --by-entry. Do not edit by hand (it is rebuilt in full and overwritten every time) -->")
print()
print("| # | Entry (heading) | Turns | AI working time | Human time | Notes |")
print("|---|---|---|---|---|---|")
rows = groups + ([none_group] if none_group["turns"] else [])
for i, g in enumerate(rows, 1):
    ai, human, idle, c = summarize(g["turns"])
    num = "—" if g is none_group else str(i)
    print(f"| {num} | {g['h']} | {len(g['turns']) - c['notify']} | {fmt(ai)} | "
          f"{human_cell(human, idle)} | {notes(g, c)} |")
ai, human, idle, c = summarize(turns)
total_note = [f"{len(idle)} away gap(s)" if idle else "", f"{c['notify']} notification(s)" if c["notify"] else ""]
total_note = " and ".join(x for x in total_note if x)
print(f"| | **Total** | {len(turns) - c['notify']} | {fmt(ai)} | {human_cell(human, idle)} | "
      f"{'Excludes ' + total_note if total_note else ''} |")
print()
print("- **AI working time** = sum of prompt -> reply. **Human time** = sum of previous reply -> next prompt")
print(f"- Human time is the wall-clock time until the prompt arrives, not the time spent thinking. "
      f"Gaps over {fmt(IDLE_LIMIT)} are treated as time away, left out and shown in parentheses")
print("- Turns counts human prompts. A turn started by a background task's completion notification "
      "is a continuation of the previous prompt; its time is added to the AI side")
if c["unknown"]:
    print(f"- {c['unknown']} record(s) in the old format without a kind column were counted as human prompts")
if turns:
    src = ", ".join(f"`{s[:8]}`" for s in sorted({t["s"] for t in turns}))
    print(f"- Source: `turn-log.tsv` (recorded mechanically by the hook) / sessions {src} / "
          f"{turns[0]['p'] or turns[0]['e']} to {turns[-1]['e'] or turns[-1]['p']}")
PY
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
    # Skip kind notify (a completion-notification turn continues the previous prompt; same as the guard)
    if len(p) >= 2 and p[1].strip().lower() == "userpromptsubmit" \
            and not (len(p) >= 4 and p[3].strip() == "notify"):
        last = p[0]
if not last:
    print("No records yet (the hook may not be firing. Check with --list)")
else:
    print(f"- **This turn ({last}):** <what you are about to do in this turn>")
'
}

case "${1:-}" in
  --by-entry) by_entry_report; exit 0 ;;
  --list)    list_sessions; exit 0 ;;
  --declare) declare_line;  exit 0 ;;
  *) echo "Usage: $0 --by-entry | --list | --declare" >&2; exit 1 ;;
esac
