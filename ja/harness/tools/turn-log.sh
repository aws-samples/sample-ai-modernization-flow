#!/bin/bash
# =============================================================================
# turn-log.sh — ターンの開始/終了時刻を hook で記録する（採取専用）
# =============================================================================
#
# 自己申告の記録は忘れても検出されないため、時刻は hook で採る。
# 表の生成は `turn-report.sh`（`--worklog` / `--list` / `--declare`）。採取とレポートを分けるのは、
# 毎ターン走る経路に不要なコードを置かないため（採取の失敗は stdout を汚せないのでエラーが表に出ない）。
#
# hook から: stdin にイベント JSON を受け、TSV に1行追記して exit 0 する。配線は install.sh --turn-log。
#   出力: `03-worklog/turn-log.tsv` に `時刻 <TAB> イベント生値 <TAB> session_id`
#   対応: userPromptSubmit / stop（Kiro）、UserPromptSubmit / Stop / StopFailure（Claude Code）
#
# 触るときに壊しやすい点:
#   - **標準出力に何も書かない。** 両ツールとも開始 hook の stdout をエージェントの文脈に注入する
#   - **プロンプト本文は採らない。** 時刻に本文は不要であり、採れば API キー等が平文で残る
#   - **イベント名は正規化しない。** 生値の大小文字がツールの判別情報を保っている
#     （`Stop`=Claude Code / `stop`=Kiro）
#   - `session_id` はペイロード優先、無ければ環境変数（Kiro の `--no-interactive` は環境変数のみ）
#   - **ファイル名に外部由来の値を使わない** — サニタイズ・ローテートが不要な操作になる
#   - `cwd` はパス境界で比較（前方一致だと `<root>-EVIL` が通る）/ umask 077 + chmod 600 /
#     python3 は絶対パス優先（PATH 乗っ取り対策）/ リンク先には書かない / 制御文字は除去する
#   - `readlink -f` / `date -d` / `stat -c` は使わない（CP-12）
#
# 既知の限界: hook が走った時刻であり画面に出た瞬間ではない。Claude Code の `Stop` は
#   ユーザー中断時に発火しない（API エラー時は `StopFailure`）。Kiro の中断時挙動は未確認。
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"   # ワークスペースのルート
LOG_FILE="${TURN_LOG_FILE:-$SCRIPT_DIR/turn-log.tsv}"

# python の絶対パスは install.sh が実行時に一度だけ解決し、ここに焼き込む（stamp_python_bin）。
# 毎ターン走るこの経路で `command -v python3` を再解決しない -- Windows の App Execution
# Alias スタブを実体と誤検知するバグ（LL-1）が、install 時の一度のミスから
# ターンごとの継続的なサイレント失敗に化けるのを避けるため
PY="__PYTHON_BIN__"
case "$PY" in __PYTHON_BIN__|"") PY="" ;; esac

umask 077   # ファイル 600。umask への依存を断つ

TS="$(date '+%Y-%m-%dT%H:%M:%S%z')"
PAYLOAD="$(cat 2>/dev/null || true)"

EVENT=""; SESSION=""; CWD=""
if [ -n "$PY" ]; then
  # `session_id` は**ペイロード優先、無ければ環境変数**。
  # Kiro の `--no-interactive` はペイロードに `session_id` を渡さず環境変数のみである
  # （実測）。ここを削ると非対話起動で3列目が空になる。
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
    # タブ・改行に加えて制御文字（C0 と DEL）を除去する
    return "".join(ch for ch in str(s) if ch >= " " and ch != "\x7f")

print("\t".join(clean(x) for x in (raw, session, d.get("cwd", ""))))
' 2>/dev/null || true)"
  if [ -n "$PARSED" ]; then
    EVENT="$(printf '%s' "$PARSED"   | cut -f1)"
    SESSION="$(printf '%s' "$PARSED" | cut -f2)"
    CWD="$(printf '%s' "$PARSED"     | cut -f3)"
  fi
fi

# 既知のイベント以外は記録しない（不正な入力・空の stdin・将来追加されるイベントで
# ログを汚さないため）。**大小無視で照合する**（Kiro は小文字、Claude Code は大文字）。
case "$(printf '%s' "$EVENT" | tr 'A-Z' 'a-z')" in
  userpromptsubmit|stop|stopfailure) : ;;
  *) exit 0 ;;
esac

# hook 払い出しの cwd は Windows ネイティブ形式（`D:\...`）で来ることがある一方、
# WORKSPACE_ROOT は git-bash の `pwd`（`/d/...`）形式である。比較前に正規化する（実測: 正規化なしでは
# 全件が非一致になり記録が一切残らない）。ドライブ文字は大小無視、区切りは `\` と `/` の両方を受理する
case "$CWD" in
  [A-Za-z]:[\\/]*)
    _drive="$(printf '%s' "${CWD%%:*}" | tr '[:upper:]' '[:lower:]')"
    _rest="${CWD#??}"
    _rest="${_rest//\\//}"
    CWD="/${_drive}${_rest}"
    ;;
esac

# ワークスペース外からの発火は記録しない。**パス境界で比較する**
# （前方一致だけだと `<root>-EVIL` のような兄弟ディレクトリが通過する。実測済み）。
# cwd が取れないときは記録する。
case "$CWD" in
  "" ) : ;;
  "$WORKSPACE_ROOT" | "$WORKSPACE_ROOT"/* ) : ;;
  * ) exit 0 ;;
esac

# 追記先がシンボリックリンクなら書かない（追記先の差し替えを防ぐ）
if [ -L "$LOG_FILE" ]; then exit 0; fi

printf '%s\t%s\t%s\n' "$TS" "$EVENT" "${SESSION:-no-session-id}" \
  >> "$LOG_FILE" 2>/dev/null || true
chmod 600 "$LOG_FILE" 2>/dev/null || true

exit 0
