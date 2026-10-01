#!/bin/bash
# =============================================================================
# turn-report.sh — 採取したターン時刻から表と宣言行を作る（レポート専用。読むだけ）
# =============================================================================
#
#   --worklog   worklog に貼る表（未記録のターンのみ）。**貼った表だけが恒久記録である**
#               （生ログは git-ignored）。契機は skills/migration-recording にある
#   --list      記録のあるセッション一覧（hook が発火しているかの確認）
#   --declare   着手時の宣言行（work-declaration-guard.sh が照合する行）
#
# 出す2つの時間: **所要（AI）** = 指示→返答 / **待機（人）** = 直前の返答→次の指示。
#   待機は実時間であり思考時間ではない。`TURN_LOG_IDLE_LIMIT` 秒（既定 3600）超は離席として
#   集計から除外し、括弧付きで出す。
#
# 触るときに壊しやすい点:
#   - **prompt→stop の対応と待機の起点はセッション内で取る。** 時刻順に並べた列で測ると
#     並行セッションの返答を起点にして負の値が出る（実測 -93s）
#   - **未記録の判定は返答時刻で行う。** 指示時刻で判定すると、前回「進行中」として貼った
#     ターンが完了しても二度と出力されず、所要が恒久記録から落ちる
#   - 下限は worklog 内の最新ターン時刻を機械が読む（人に範囲を覚えさせない）
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

# --- 表の生成 -----------------------------------------------------------------

run_report() {  # $1 = 下限時刻（空可）
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

def fmt(s):  # 秒 → 人が読める形
    if s is None:
        return "—"
    if s >= 3600:
        return f"{s // 3600}h{(s % 3600) // 60:02d}m"
    if s >= 60:
        return f"{s // 60}m{s % 60:02d}s"
    return f"{s}s"

# **人の反応時間の上限**: これを超える間隔は「考えていた時間」ではなく
# セッションを離れていた時間なので、統計から除外して表に理由を書く。
IDLE_LIMIT = int(os.environ.get("TURN_LOG_IDLE_LIMIT", "3600"))  # 既定 1 時間

# --- 行を読む（3列: 時刻 / イベント生値 / session_id）--------------------------
by_session = {}   # session_id -> [(ts, event), ...]  出現順を保つ
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

# --- ターンを組み立てる（prompt → stop の対応は**セッション内で**取る）---------
# セッションをまたいで対応させると、並行セッションがあったときに誤って組む。
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

# --- 所要と待機を**全ターン**で計算する ---------------------------------------
# 下限より前のターンも計算に含める。そうしないと、新しく記録する最初の1行の
# 「待機」（＝前回の返答から今回の指示まで）が失われる。
#
# **待機は「セッション内の」直前の返答から測る。** 全ターンを時刻順に並べた列で測ると、
# 並行セッション（サブプロセスで起動した別ツール等）が混ざったときに
# **他セッションの返答を起点にしてしまい、負の値が出る**（実測: -93s）。
# 「人の反応時間」は1つの対話の中でしか定義できない量である。
last_stop = {}   # session -> 直前の返答時刻
for t in turns:
    a, b = epoch(t["p"]), epoch(t["e"])
    t["dur"] = int(b - a) if (a and b) else None
    t["wait"] = None
    prev = last_stop.get(t["s"])
    if t["p"] and prev:
        c, d = epoch(prev), a
        if c and d and d >= c:
            t["wait"] = int(d - c)
    # 中断されたターン（返答時刻なし）は、次の待機の起点にできない
    last_stop[t["s"]] = t["e"] if t["e"] else None

def cut_key(t):
    """未記録かどうかの判定は**返答時刻**（あれば）で行う。
    指示時刻で判定すると、前回「進行中」として貼ったターンが完了しても
    二度と出力されず、**そのターンの所要が恒久記録から落ちる**。
    返答時刻で判定すれば、完了時にもう一度出て記録が完成する
    （前回の行は「進行中」と明記されているので、重複ではなく追記になる）。"""
    return epoch(t["e"] or t["p"]) or 0.0

bound = epoch(since_raw) if since_raw else None
sel = [t for t in turns if bound is None or cut_key(t) > bound]

if not sel:
    print(f"（未記録のターンはない。worklog 既記録の最終ターン: {since_raw}）")
    raise SystemExit(0)

# --- 表 -----------------------------------------------------------------------
with_sess = len({t["s"] for t in sel}) > 1
cols = ["#"] + (["セッション"] if with_sess else []) \
     + ["指示（受領）", "返答（返却）", "所要（AI）", "待機（人）", "備考"]
print("| " + " | ".join(cols) + " |")
print("|" + "|".join(["---"] * len(cols)) + "|")

durs, waits, excluded = [], [], []
for i, t in enumerate(sel, 1):
    note = ""
    if t["ev"] == "stop-failure":
        note = "API エラーで終了（StopFailure）。所要の統計から除外"
    elif t["ev"] == "interrupted":
        note = "終了記録なし（中断の可能性）"
    elif t["ev"] == "open":
        note = "進行中、または終了記録なし"
    if t["p"] is None:
        note = "開始記録なし"
    if t["dur"] is not None and t["ev"] == "stop":
        durs.append(t["dur"])
    w = "—"
    if t["wait"] is not None:
        if t["wait"] > IDLE_LIMIT:
            w = f"({fmt(t['wait'])})"
            excluded.append(t["wait"])
            note = (note + " / " if note else "") + "セッション間の中断（待機の統計から除外）"
        else:
            w = fmt(t["wait"])
            waits.append(t["wait"])
    cells = [str(i)] + ([t["s"][:8]] if with_sess else []) \
          + [t["p"] or "—", t["e"] or "—", fmt(t["dur"]), w, note]
    print("| " + " | ".join(cells) + " |")
print()

def stat(label, xs, unit_note=""):
    if not xs:
        print(f"- **{label}**: 標本なし")
        return
    xs = sorted(xs)
    med = xs[len(xs) // 2] if len(xs) % 2 else (xs[len(xs) // 2 - 1] + xs[len(xs) // 2]) // 2
    print(f"- **{label}**: n={len(xs)} / 中央値 {fmt(med)} / 最小 {fmt(xs[0])} / "
          f"最大 {fmt(xs[-1])} / 合計 {fmt(sum(xs))}{unit_note}")

print("### 集計")
print()
stat("所要（AI の処理時間）", durs, "（`stop-failure` は除外）")
stat("待機（人の反応時間）", waits, f"（{fmt(IDLE_LIMIT)} 超の間隔は除外）")
if excluded:
    print(f"- 除外した長時間の間隔: {len(excluded)}件（{', '.join(fmt(g) for g in sorted(excluded))}）"
          f" — 席を離れていた時間であり反応時間ではない")
print()
print("⚠️ **「待機（人）」は指示が届くまでの実時間であり、人が考えていた時間とは一致しない**")
print("（読む・別作業・離席が混ざる）。**中断されたターンの直後は起点が無いため `—` になる。**")
print()
src = ", ".join(f"`{s[:8]}`" for s in sorted({t["s"] for t in sel}))
rng = f"{sel[0]['p'] or sel[0]['e']} 〜 {sel[-1]['e'] or sel[-1]['p']}"
if bound:
    rng += f"（worklog 既記録の {since_raw} より後）"
print(f"出所: 生ログ {src} / 対象範囲 {rng}（hook が機械的に記録。自己申告ではない）")
PY
}

worklog_report() {  # worklog に未記録のターンだけを出す（恒久記録の生成口）
  local since wl
  wl="${TURN_LOG_WORKLOG_FILE:-$SCRIPT_DIR/worklog.md}"
  require_log
  # 下限 = worklog.md に既に書かれている最も新しいターン時刻。
  # **人に範囲を覚えさせない**ための機械読み取りである（申告漏れは二重記録/欠落として現れる）。
  # 注: 文字列の max で比較しているため、記録に**複数のタイムゾーンオフセットが混在すると
  # 正しく最大が取れない**。本フレームワークの記録は hook 実行ホストのローカル時刻に統一される。
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
    if len(p) >= 2 and p[1].strip().lower() == "userpromptsubmit":
        last = p[0]
if not last:
    print("記録がまだない（hook が発火していない可能性がある。--list で確認する）")
else:
    print(f"- **This turn ({last}):** <このターンで何をやろうとしているのか>")
'
}

case "${1:-}" in
  --worklog) worklog_report; exit 0 ;;
  --list)    list_sessions; exit 0 ;;
  --declare) declare_line;  exit 0 ;;
  *) echo "使い方: $0 --worklog | --list | --declare" >&2; exit 1 ;;
esac
