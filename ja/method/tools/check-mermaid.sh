#!/bin/bash
# HTML 化した分析結果の mermaid 図を、ヘッドレスブラウザで描画して構文エラーを検出する
#
# 使い方: ./check-mermaid.sh <HTMLディレクトリ>
# 例:     cd 00-analysis/<repo-id> && ../check-mermaid.sh ATXDocumentation_html
#         （generate-html.sh の出力に対して実行する。0a-6）
#
# 判定: 図を含むページごとに、描画後の DOM で
#         「Syntax error in」の数 = 0  かつ  描画された図（<svg id="mermaid-…">）の数 = 図の数
#       図の数は描画前の HTML の <pre class="mermaid"> の数である。
#       mermaid の class を持つ要素があるのに <pre class="mermaid"> が 0 件なら検出漏れとして失敗にする
#       （新しい pandoc がハイライトして <pre class="sourceCode mermaid"> を出すと、黙って 0 図で合格になるため）。
# 終了コード: 0 = 全図が描画された（図が 1 件も無いときは ⚠️ を出して 0）/ 1 = エラー・未描画・検出漏れ / 2 = 引数エラー
#             **ブラウザが見つからないときは「未検証」と出して 0 で終わる**（作業を止めない。
#             analysis-runs.md に未検証と記録する）
#
# ブラウザを探す順: 環境変数 MERMAID_CHECK_BROWSER → PATH 上の chrome / chromium / msedge 等
#   → OS ごとの標準の場所（macOS の Chrome・Chromium・Edge、Windows の Chrome・Edge）。
#   Windows 10/11 には Edge が標準で入っている。
#
# 触るときに壊しやすい点:
#   - **Windows（Git Bash）ではブラウザに Windows 形式のパスを渡す**（`cygpath -m` で `C:/…`）。
#     `/c/…` はブラウザに通じない。作業用プロファイルの場所も同じ
#   - **`timeout` コマンドを使わない**（macOS には無く、Windows では cmd の timeout と衝突する）。
#     バックグラウンドで起動し、`MERMAID_CHECK_TIMEOUT` 秒（既定 60）で止める
#   - 構文エラーの図も <svg id="mermaid-…"> として描画される。エラーは文字列で数える
#   - `readlink -f` / `date -d` / `stat -c` は使わない（CP-12）。macOS の bash 3.2 で動かす
#   - Windows（Edge・Chrome）での動作は未検証（macOS の Chrome で検証済み）
#

set -u

DIR="${1:-}"
if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
  echo "使い方: $0 <HTMLディレクトリ>（generate-html.sh の出力）" >&2
  exit 2
fi
LIMIT="${MERMAID_CHECK_TIMEOUT:-60}"

# --- ブラウザを探す -------------------------------------------------------------
find_browser() {
  local c
  if [ -n "${MERMAID_CHECK_BROWSER:-}" ]; then
    printf '%s\n' "$MERMAID_CHECK_BROWSER"; return 0
  fi
  for c in chrome chromium chromium-browser google-chrome google-chrome-stable msedge microsoft-edge; do
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return 0; fi
  done
  for c in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
    "/c/Program Files/Google/Chrome/Application/chrome.exe" \
    "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
    "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
    "/c/Program Files/Microsoft/Edge/Application/msedge.exe"; do
    if [ -x "$c" ]; then printf '%s\n' "$c"; return 0; fi
  done
  if [ -n "${LOCALAPPDATA:-}" ] && command -v cygpath >/dev/null 2>&1; then
    c="$(cygpath -u "$LOCALAPPDATA")/Google/Chrome/Application/chrome.exe"
    if [ -x "$c" ]; then printf '%s\n' "$c"; return 0; fi
  fi
  return 1
}

BROWSER="$(find_browser || true)"
if [ -n "${MERMAID_CHECK_BROWSER:-}" ] && [ ! -x "$BROWSER" ] && ! command -v "$BROWSER" >/dev/null 2>&1; then
  echo "MERMAID_CHECK_BROWSER に指定したブラウザが実行できない: ${BROWSER}" >&2
  exit 2
fi
if [ -z "$BROWSER" ]; then
  echo "未検証: ヘッドレスで使えるブラウザ（Chrome / Chromium / Edge）が見つからない。"
  echo "        MERMAID_CHECK_BROWSER=<ブラウザのパス> を指定して再実行するか、analysis-runs.md に「mermaid 未検証」と記録する"
  exit 0
fi

# Windows（Git Bash）ではブラウザに渡すパスを Windows 形式にする
to_native() {  # $1 = 絶対パス
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

PROFILE="$(mktemp -d 2>/dev/null || mktemp -d -t mmcheck)"
DOM="$PROFILE/dom.html"
trap 'rm -rf "$PROFILE"' EXIT

# --- 1ページを描画して DOM を書き出す（時間で打ち切る）----------------------------
render() {  # $1 = HTML の絶対パス。成功で 0
  local url pid waited=0
  url="file:///$(to_native "$1" | sed 's|^/*||')"
  "$BROWSER" --headless=new --no-sandbox --disable-gpu --no-first-run \
    --user-data-dir="$(to_native "$PROFILE/prof")" --virtual-time-budget=20000 \
    --dump-dom "$url" > "$DOM" 2>/dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$LIMIT" ]; then
      kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
      return 1
    fi
    sleep 1; waited=$((waited + 1))
  done
  wait "$pid" 2>/dev/null
  return 0
}

ABS_DIR="$(cd "$DIR" && pwd)"
pages=0; diagrams=0; bad=0; htmls=0; suspect=0
while IFS= read -r f; do
  htmls=$((htmls + 1))
  want="$(grep -o '<pre class="mermaid"' "$f" | wc -l | tr -d ' ')"
  if [ "$want" -eq 0 ]; then
    # 図が 0 件に見えるのに mermaid の class が付いた要素があるページは、検出漏れである。
    # 新しい pandoc は mermaid ブロックをハイライトして <pre class="sourceCode mermaid"> を出し、
    # ブラウザでは描画されるのにこのゲートが 0 図 = 合格と誤報する。黙って通さない
    if grep -q 'class="[^"]*mermaid' "$f"; then suspect=$((suspect + 1)); fi
    continue
  fi
  pages=$((pages + 1)); diagrams=$((diagrams + want))
  rel="${f#"$ABS_DIR"/}"
  if ! render "$f"; then
    echo "❌ ${rel}: ${LIMIT} 秒で描画が終わらない（MERMAID_CHECK_TIMEOUT で延ばせる）"
    bad=$((bad + 1)); continue
  fi
  err="$(grep -o 'Syntax error in' "$DOM" | wc -l | tr -d ' ')"
  got="$(grep -o '<svg[^>]*id="mermaid-' "$DOM" | wc -l | tr -d ' ')"
  if [ "$err" -gt 0 ] || [ "$got" -ne "$want" ]; then
    echo "❌ ${rel}: 図 ${want} / 描画 ${got} / 構文エラー ${err}"
    bad=$((bad + 1))
  fi
done < <(find "$ABS_DIR" -type f -name '*.html' | LC_ALL=C sort)

echo "ブラウザ: ${BROWSER}"
if [ "$suspect" -gt 0 ]; then
  echo "❌ mermaid: ${suspect} ページに mermaid の class を持つ要素があるのに <pre class=\"mermaid\"> を 1 件も検出できない。"
  echo "   HTML の生成側を疑う。pandoc が mermaid ブロックをハイライトすると <pre class=\"sourceCode mermaid\"> になり、"
  echo "   このゲートが無効化される（generate-html.sh がハイライトを切っているか確認する）"
  exit 1
fi
if [ "$pages" -eq 0 ]; then
  echo "⚠️ mermaid: ${htmls} ページを調べたが mermaid 図は 1 件もない。描画は検証していない"
  exit 0
fi
if [ "$bad" -eq 0 ]; then
  echo "✅ mermaid: ${pages} ページ・${diagrams} 図をすべて描画した（構文エラー 0）"
  exit 0
fi
echo "❌ mermaid: ${pages} ページ中 ${bad} ページに問題がある（図は合計 ${diagrams}）。"
echo "   エラーの図は、ページ内で何番目の <svg> かで特定できる。よくある原因: シーケンス図のメッセージ中の ';'、"
echo "   状態遷移図のラベル中の 2 つ目以降の ':'、classDiagram のクラス本体を 1 行に ';' 区切りで書く形式"
exit 1
