#!/bin/bash
# =============================================================================
# turn-report.sh — 採取したターン時刻から表と宣言行を作る（レポート専用。読むだけ）
# =============================================================================
#
#   --by-entry  worklog のエントリごとの AI の時間・人の時間（`time-summary.md` の生成口）。
#               ターンとエントリは「指示時刻 = エントリの宣言行 `This turn (<時刻>)`」で結ぶ。
#               毎回全体を作り直すので、上書きして commit する（手で直さない）。
#               契機（セッションの開始時と終了時）は skills/migration-session にある
#   --list      記録のあるセッション一覧（hook が発火しているかの確認）
#   --declare   着手時の宣言行（work-declaration-guard.sh が照合する行）
#
# 出す2つの時間: **AI の作業時間** = 指示→返答 / **人の時間** = 直前の返答→次の指示。
#   人の時間は実時間であり思考時間ではない。`TURN_LOG_IDLE_LIMIT` 秒（既定 3600）超は離席として
#   外し、括弧付きで出す。完了通知で起動したターン（種別 notify）は直前の指示の続きとして扱う。
#
# 触るときに壊しやすい点:
#   - **prompt→stop の対応と待機の起点はセッション内で取る。** 時刻順に並べた列で測ると
#     並行セッションの返答を起点にして負の値が出る（実測 -93s）
#   - **行頭の宣言行だけを数える。** 本文中の引用まで拾うと、エントリが誤って結合される
#   - **出力に生成時刻を入れない。** 新しいターンがなければ差分が出ない（commit の雑音を防ぐ）
#   - 種別の列がない旧形式（3列）の行も読む（unknown = 人の指示として集計）
#   - `readlink -f` / `date -d` / `stat -c` は使わない（CP-12）
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="${TURN_LOG_FILE:-$SCRIPT_DIR/turn-log.tsv}"

# install.sh が一度だけ解決した python の絶対パスをここに焼き込む（turn-log.sh 参照）
PY="__PYTHON_BIN__"
case "$PY" in __PYTHON_BIN__|"") PY="" ;; esac

# Windows の python は stdout を既定でコンソールのコードページ（例: cp1252）にエンコードし、
# 全角チルダ等の日本語出力で UnicodeEncodeError を起こす。出力先が実際のターミナルかに関わらず
# 常に UTF-8 に固定する
export PYTHONIOENCODING="utf-8"

require_log() {
  if [ ! -f "$LOG_FILE" ]; then echo "記録がない: ${LOG_FILE}" >&2; exit 1; fi
  if [ -z "$PY" ]; then echo "python が見つからない（install.sh を再実行して解決する）" >&2; exit 1; fi
}

# --- エントリごとの集計（--by-entry）------------------------------------------

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

def fmt(s):  # 秒 → 人が読める形
    if s is None:
        return "—"
    if s >= 3600:
        return f"{s // 3600}h{(s % 3600) // 60:02d}m"
    if s >= 60:
        return f"{s // 60}m{s % 60:02d}s"
    return f"{s}s"

# **人の反応時間の上限**: これを超える間隔は「考えていた時間」ではなく
# セッションを離れていた時間なので、人の時間から外して括弧で示す。
IDLE_LIMIT = int(os.environ.get("TURN_LOG_IDLE_LIMIT", "3600"))  # 既定 1 時間

# --- 行を読む（時刻 / イベント生値 / session_id / 種別）-----------------------
# 種別の列がない旧形式（3列）の行は種別 unknown とし、人の指示として集計する（後方互換）。
by_session = {}   # session_id -> [(ts, event, kind), ...]  出現順を保つ
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

# --- ターンを組み立てる（prompt → stop の対応は**セッション内で**取る）---------
# セッションをまたいで対応させると、並行セッションがあったときに誤って組む。
turns = []
for sess in order:
    pending = None   # (指示時刻, 種別)
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

# --- 所要と待機（**待機はセッション内の直前の返答から測る**）-------------------
# 全ターンを時刻順に並べた列で測ると、並行セッションの返答を起点にして負の値が出る（実測 -93s）。
last_stop = {}   # session -> 直前の返答時刻
for t in turns:
    a, b = epoch(t["p"]), epoch(t["e"])
    t["dur"] = int(b - a) if (a and b) else None
    t["wait"] = None
    prev = last_stop.get(t["s"])
    if t["p"] and prev:
        c = epoch(prev)
        if c and a and a >= c:
            t["wait"] = int(a - c)
    # 中断されたターン（返答時刻なし）は、次の待機の起点にできない
    last_stop[t["s"]] = t["e"] if t["e"] else None

# --- ターン → 宣言行の時刻（照合のキー）-------------------------------------------
# **通知のターンは、同じセッションの直前の人の指示の続きとして扱う。** AI の時間はそこに足し、
# 直前の待機は人の時間に数えない（人は何も指示していない）。
lead = {}   # session -> 直前の人の指示時刻
for t in turns:
    if t["k"] == "notify" and t["s"] in lead:
        t["key"] = lead[t["s"]]
    else:
        t["key"] = t["p"]
        if t["k"] != "notify" and t["p"]:
            lead[t["s"]] = t["p"]

# --- worklog を読む: `## ` 見出し = エントリ、宣言行の時刻 = 照合のキー --------------
# **行頭の宣言行だけを数える**（`- **This turn (<時刻>):**`）。本文中で他のエントリの
# 宣言行を引用した箇所まで拾うと、そのエントリが引用先と誤って結合される。
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

# エントリ → 行。宣言行のないエントリ（1ターンで複数書いた2本目以降）と、既出の宣言行を持つエントリは
# 該当する行にまとめる。
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

none_group = {"h": "（エントリなし）", "n": 0, "turns": []}
for t in turns:
    (by_anchor.get(t["key"]) or none_group)["turns"].append(t)

# --- 表 -----------------------------------------------------------------------
def summarize(ts):
    # 標本がなければ None（「—」）にする。0s と出すと「測って 0 だった」と読まれる
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
        cell += f" ({fmt(sum(idle))} 離席)"
    return cell

def notes(g, c):
    n = []
    if g["n"] > 1:
        n.append(f"{g['n']} エントリを結合")
    if c["notify"]:
        n.append(f"通知 {c['notify']} 件を AI 側に合算")
    if c["fail"]:
        n.append(f"API エラー終了 {c['fail']} 件（AI 時間から除外）")
    if c["open"]:
        n.append("進行中、または終了記録なし")
    if c["interrupted"]:
        n.append(f"中断の可能性 {c['interrupted']} 件")
    if g["n"] and not g["turns"]:
        n.append("対応するターンなし（宣言行の時刻を確認）")
    return " / ".join(n)

print("# ターン時刻の集計")
print()
print("<!-- turn-report.sh --by-entry が生成する。手で直さない（毎回全体を作り直して上書きする） -->")
print()
print("| # | エントリ（見出し） | ターン数 | AI の作業時間 | 人の時間 | 備考 |")
print("|---|---|---|---|---|---|")
rows = groups + ([none_group] if none_group["turns"] else [])
for i, g in enumerate(rows, 1):
    ai, human, idle, c = summarize(g["turns"])
    num = "—" if g is none_group else str(i)
    print(f"| {num} | {g['h']} | {len(g['turns']) - c['notify']} | {fmt(ai)} | "
          f"{human_cell(human, idle)} | {notes(g, c)} |")
ai, human, idle, c = summarize(turns)
total_note = [f"離席 {len(idle)} 件" if idle else "", f"通知 {c['notify']} 件" if c["notify"] else ""]
total_note = "・".join(x for x in total_note if x)
print(f"| | **合計** | {len(turns) - c['notify']} | {fmt(ai)} | {human_cell(human, idle)} | "
      f"{total_note + 'を除外' if total_note else ''} |")
print()
print("- **AI の作業時間** = 指示 → 返答の合計。**人の時間** = 直前の返答 → 次の指示の合計")
print(f"- 人の時間は指示が届くまでの実時間であり、考えていた時間とは一致しない。"
      f"{fmt(IDLE_LIMIT)} 超の間隔は離席として外し、括弧で示す")
print("- ターン数は人の指示の数。バックグラウンド処理の完了通知で起動したターンは、"
      "直前の指示の続きとして AI の時間に足す")
if c["unknown"]:
    print(f"- 種別の列がない旧形式の記録 {c['unknown']} 件は、人の指示として集計した")
if turns:
    src = ", ".join(f"`{s[:8]}`" for s in sorted({t["s"] for t in turns}))
    print(f"- 出所: `turn-log.tsv`（hook が機械的に記録）/ セッション {src} / "
          f"{turns[0]['p'] or turns[0]['e']} 〜 {turns[-1]['e'] or turns[-1]['p']}")
PY
}

list_sessions() {  # 記録の有無の確認（`--agent` 付け忘れの事後検知に使う）
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
    print(f"{sess}\t{c} lines\t{first[sess]} 〜 {last[sess]}")
'
}

declare_line() {  # 着手前の宣言行を出す（work-declaration-guard.sh が照合する行）
  require_log
  # **hook の外から走るのでセッションを特定できない。** 直近の `UserPromptSubmit` を使う
  # （単一セッションでは正しい）。並行セッションで外した場合は、guard がブロック時に
  # 正しい時刻を含むメッセージを出すので、そちらを使う。
  TURN_LOG_PATH="$LOG_FILE" "$PY" -c '
import io, os
last = ""
for line in io.open(os.environ["TURN_LOG_PATH"], encoding="utf-8", errors="replace"):
    p = line.rstrip("\n").split("\t")
    # 種別 notify（完了通知のターン）は直前の指示の続きなので飛ばす（guard と同じ扱い）
    if len(p) >= 2 and p[1].strip().lower() == "userpromptsubmit" \
            and not (len(p) >= 4 and p[3].strip() == "notify"):
        last = p[0]
if not last:
    print("記録がまだない（hook が発火していない可能性がある。--list で確認する）")
else:
    print(f"- **This turn ({last}):** <このターンで何をやろうとしているのか>")
'
}

case "${1:-}" in
  --by-entry) by_entry_report; exit 0 ;;
  --list)    list_sessions; exit 0 ;;
  --declare) declare_line;  exit 0 ;;
  *) echo "使い方: $0 --by-entry | --list | --declare" >&2; exit 1 ;;
esac
