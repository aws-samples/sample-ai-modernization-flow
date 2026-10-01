#!/bin/bash
# =============================================================================
# work-declaration-guard.sh — 着手時の宣言が「そのターンで」書かれたことを強制する
# =============================================================================
#
# 記録義務は完了時に発火するため、中断された作業を守れない。よって「変更系ツールを使う前に
# 宣言があること」を hook で強制する。**`preToolUse` は「最初のコード接触の前」という引き金に
# 文字どおり一致する唯一のイベントであり、Phase に依存しない**（verify.sh 側の検査は
# dirty＝接触後にしか動かず、実装ツリー単位なので Phase 0a〜2 では走らない）。
#
# hook から: `preToolUse`（Kiro）/ `PreToolUse`（Claude Code）に配線する（install.sh --work-guard）。
# 判定: `session-context.md` の "In-progress Investigation" 節に `This turn (<T_prompt>)` があること。
#   `T_prompt` = `turn-log.tsv` の**自セッションの**最後の `UserPromptSubmit`。
#   宣言行は `turn-report.sh --declare` で生成できる。
#
# 素通しする条件（fail-open。guard が作業を不能にしてはならない）:
#   1. 変更系ツール以外  2. `session-context.md` 自身  3. 自セッションの prompt 記録なし
#   4. `python3` なし / 壊れた入力
#   **`Bash` / `execute_bash` は対象外**（読み書き両方を担い機械的に分類できない）。抜け道として残る。
#
# 触るときに壊しやすい点:
#   - **mtime を見ない。** session-context は無関係な理由で頻繁に触るため素通りする
#   - **`T_prompt` はセッションで絞る。** 絞らないと並行セッションの prompt を自分のものとして拾い、
#     正しい宣言がブロックされる
#   - **ツール名は `_`/`-` を除去して照合する**（Claude Code は `Edit`/`Write`、Kiro は `fs_write`）
#   - **警告モードを持たない。** exit 0 の stderr はエージェントに届かない（実測）。
#     exit 2 は両ツールでツールを止め、メッセージが届く
#   - **本スクリプトは読むだけである**（ファイルに書かない）。`cwd` はパス境界で比較する
#   - guard は宣言の**存在**を強制できるが**恒久化はできない**（close-out で worklog へ写す）
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SESSION_CONTEXT="${WORK_DECL_SESSION_CONTEXT:-$SCRIPT_DIR/session-context.md}"
TURN_LOG="${TURN_LOG_FILE:-$SCRIPT_DIR/turn-log.tsv}"

# install.sh が一度だけ解決した python の絶対パスをここに焼き込む（turn-log.sh 参照）
PY="__PYTHON_BIN__"
case "$PY" in __PYTHON_BIN__|"") PY="" ;; esac
[ -z "$PY" ] && exit 0                      # 素通し条件4

PAYLOAD="$(cat 2>/dev/null || true)"

# ツール名と対象パスを取り出す（両ツールでキー名が違うため候補を順に見る）
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
[ -z "$PARSED" ] && exit 0                  # 素通し条件4

TOOL="$(printf '%s' "$PARSED" | cut -f1)"
TARGET="$(printf '%s' "$PARSED" | cut -f2)"
CWD="$(printf '%s' "$PARSED" | cut -f3)"
SESSION="$(printf '%s' "$PARSED" | cut -f4)"

# hook 払い出しの cwd は Windows ネイティブ形式（`D:\...`）で来ることがある一方、
# WORKSPACE_ROOT は git-bash の `pwd`（`/d/...`）形式である。比較前に正規化する（turn-log.sh 参照）
case "$CWD" in
  [A-Za-z]:[\\/]*)
    _drive="$(printf '%s' "${CWD%%:*}" | tr '[:upper:]' '[:lower:]')"
    _rest="${CWD#??}"
    _rest="${_rest//\\//}"
    CWD="/${_drive}${_rest}"
    ;;
esac

# ワークスペース外からの発火は関知しない（パス境界で比較する）
case "$CWD" in
  "" ) : ;;
  "$WORKSPACE_ROOT" | "$WORKSPACE_ROOT"/* ) : ;;
  * ) exit 0 ;;
esac

# 素通し条件1: 変更系ツール以外（Bash / execute_bash は意図的に対象外）。
# **大小無視 + `_`/`-` を除去して照合する** — Claude Code は `Edit`/`Write`/`NotebookEdit`、
# Kiro は **`fs_write`**（アンダースコア付き）である。実測で気づいた差異なので正規化して吸収する。
case "$(printf '%s' "$TOOL" | tr 'A-Z' 'a-z' | tr -d '_-')" in
  edit|write|notebookedit|multiedit|fswrite|fsreplace) : ;;
  *) exit 0 ;;
esac

# 素通し条件2: session-context.md 自身の編集（これが無いと宣言を書けない）
case "$TARGET" in
  *session-context.md) exit 0 ;;
esac

# T_prompt を取る（素通し条件3: 無ければ関知しない）。
# **セッションで絞る。** `turn-log.tsv` は全セッションが1ファイルに追記するため、
# 絞らないと**並行セッション（サブプロセスで起動した別ツール等）の prompt を自分のものとして拾い、
# 正しい宣言がブロックされる**。session_id が取れないときだけ全体の最後にフォールバックする。
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

# 宣言の検査: 該当節に `This turn (<T_prompt>)` が存在するか。
# `This turn (...)` は日英で翻訳しない共有アンカーである（本スクリプトが機械照合するため）。
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

printf '%s\n' "⛔ 作業前の宣言がありません。
   ${TOOL} で ${TARGET} を変更する前に、03-worklog/session-context.md の
   \"In-progress Investigation / Working-tree State\" 節に次の1行を書いてください:

     - **This turn (${T_PROMPT}):** <このターンで何をやろうとしているのか>

   ./03-worklog/turn-report.sh --declare でこの行を生成できます。
   目的は中断耐性です。宣言が無いまま中断すると、何をしていたかが失われます。
   前のターンの時刻の使い回しは検知されます（時刻は一致で照合します）。
   完了時は宣言行を worklog へ写してください（guard は存在を強制できますが恒久化はできません）。" >&2

exit 2            # 両ツールでツールを止め、上のメッセージがエージェントに届く
