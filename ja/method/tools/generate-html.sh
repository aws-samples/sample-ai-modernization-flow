#!/bin/bash
# ATX の CCA 結果(Markdown) → 閲覧用 HTML 変換スクリプト
#
# 使い方: ./generate-html.sh <入力ディレクトリ> <出力ディレクトリ>
# 例:     cd 00-analysis/<repo-id> && ../generate-html.sh ATXDocumentation ATXDocumentation_html
#
# 依存: pandoc（brew install pandoc / sudo dnf install pandoc）、python3（サイドバー生成）
#
# 注意:
#   - 入力・出力ディレクトリは相対パスで指定すること（絶対パス非対応）
#   - カレントディレクトリから見た相対パスで動作する
#   - 出力先に index.html + style.css + mermaid.min.js + 各ページHTML が生成される
#   - BSD(macOS) / GNU(Linux) の双方で動作する（sed -i の非互換を避けている）
#   - ``` mermaid ``` ブロックは図として描画する。ASCII アート図はテキストのまま残るため、
#     ATX 実行時に「All diagrams MUST be mermaid not ASCII art.」を渡すのが根本対策（0a-4）
#

set -e

SRC="${1:?使い方: $0 <入力MDディレクトリ> <出力HTMLディレクトリ>}"
DST="${2:?使い方: $0 <入力MDディレクトリ> <出力HTMLディレクトリ>}"

mkdir -p "$DST"

# style.css生成
cat > "$DST/style.css" <<'CSS'
:root {
  --primary: #1a73e8; --primary-dark: #1557b0; --bg: #f8f9fb;
  --sidebar-bg: #232f3e; --sidebar-text: #d5dbdb; --card-bg: #ffffff;
  --border: #e3e8ee; --text: #1a2233; --text-secondary: #5f6b7a;
  --accent: #ff9900; --code-bg: #f1f3f5;
}
* { box-sizing: border-box; }
body { margin: 0; padding: 2rem; max-width: 960px; margin: 0 auto;
  font-family: "Amazon Ember", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  background: var(--bg); color: var(--text); line-height: 1.7; }
h1, h2, h3, h4 { color: var(--text); margin-top: 1.8em; }
h1 { font-size: 1.8rem; border-bottom: 2px solid var(--primary); padding-bottom: 0.4em; }
h2 { font-size: 1.4rem; border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
h3 { font-size: 1.15rem; color: var(--primary-dark); }
h1:first-child { margin-top: 0; }
a { color: var(--primary); text-decoration: none; }
a:hover { text-decoration: underline; color: var(--primary-dark); }
table { border-collapse: collapse; width: 100%; margin: 1em 0; font-size: 0.9rem; border: 1px solid var(--border); }
th { background: var(--sidebar-bg); color: #fff; padding: 10px 12px; text-align: left; font-weight: 500; border: 1px solid #3d4f5f; }
td { border: 1px solid var(--border); padding: 9px 12px; }
tr:nth-child(even) { background: #f8f9fb; }
code { background: var(--code-bg); padding: 2px 6px; border-radius: 4px; font-size: 1.2em; color: #c7254e; }
pre { background: #282c34; color: #abb2bf; padding: 1.2rem; border-radius: 6px; overflow-x: auto;
  font-size: 0.85rem; line-height: 1.4;
  font-family: "HackGen", "Ricty", "SFMono-Regular", "Menlo", "Monaco", "Consolas", "Liberation Mono", "Courier New", monospace; }
pre code { background: none; color: inherit; padding: 0; font-family: inherit; white-space: pre; }
blockquote { border-left: 4px solid var(--accent); margin: 1em 0; padding: 0.5em 1em; background: #fff8e6; color: #5a4a00; border-radius: 0 4px 4px 0; }
ul, ol { padding-left: 1.5em; }
li { margin: 0.3em 0; }
hr { border: none; border-top: 1px solid var(--border); margin: 2em 0; }
.mermaid { background: #fff; border: 1px solid var(--border); border-radius: 6px; padding: 1rem; margin: 1em 0; text-align: center; overflow-x: auto; }
CSS

# Mermaid.js をローカル同梱（```mermaid を図として描画。オフラインでも開ける）
MERMAID_OK=0
if curl -fsSL -o "$DST/mermaid.min.js" https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js 2>/dev/null && [ -s "$DST/mermaid.min.js" ]; then
  MERMAID_OK=1
  echo "mermaid.min.js を同梱しました ($(wc -c < "$DST/mermaid.min.js" | tr -d ' ') bytes)"
else
  echo "警告: mermaid.min.js のダウンロードに失敗。CDN 参照にフォールバックします（閲覧時にインターネットが必要）" >&2
fi

# 各MDファイルをHTML変換
cd "$SRC"
find . -name "*.md" | while read f; do
  dir=$(dirname "$f")
  mkdir -p "../$DST/$dir"
  outfile="../$DST/${f%.md}.html"

  depth=$(echo "$dir" | tr -cd '/' | wc -c | tr -d ' ')
  relprefix=""
  i=0; while [ "$i" -lt "$depth" ]; do relprefix="../$relprefix"; i=$((i+1)); done
  csspath="${relprefix}style.css"
  if [ "$MERMAID_OK" = "1" ]; then
    mermaidsrc="${relprefix}mermaid.min.js"
  else
    mermaidsrc="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"
  fi

  pandoc "$f" -o "$outfile" --standalone --template=/dev/stdin <<TEMPLATE
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>\$title\$</title>
<link rel="stylesheet" href="${csspath}">
</head>
<body>
\$body\$
<script src="${mermaidsrc}"></script>
<script>
document.addEventListener('DOMContentLoaded', function () {
  document.querySelectorAll('pre.mermaid > code, code.language-mermaid').forEach(function (c) {
    var pre = c.closest('pre');
    var d = document.createElement('div');
    d.className = 'mermaid';
    d.textContent = c.textContent;
    (pre || c).replaceWith(d);
  });
  if (window.mermaid) {
    try { mermaid.initialize({ startOnLoad: false, securityLevel: 'loose' }); mermaid.run(); }
    catch (e) { console.error('mermaid render error', e); }
  }
});
</script>
</body>
</html>
TEMPLATE
done
cd ..

# .md リンクを .html に置換 (BSD/GNU 両対応: sed -i は非互換なため一時ファイル経由)
find "$DST" -name "*.html" | while read -r hf; do
  tmp="${hf}.tmp.$$"
  sed 's/href="\([^"]*\)\.md"/href="\1.html"/g' "$hf" > "$tmp" && mv "$tmp" "$hf"
done

# index.html生成（サイドバー付き）
# 実際に生成された .html をツリーから走査してサイドバーを作る。
# 固定リストではないため dead link や孤立ページが出ない（リポジトリ差異にも追従）。
# トップレベルディレクトリごとに日本語セクション名を付与し、既知ファイルは日本語表示名にする。
python3 - "$DST" <<'PY'
import os, sys, html, re

dst = sys.argv[1]

# トップレベルディレクトリ -> 日本語セクション名（未知のディレクトリはそのまま見出しに）
SECTION_TITLES = {
    "_top": "概要", "architecture": "アーキテクチャ", "behavior": "動作分析",
    "analysis": "コード分析", "reference": "リファレンス", "diagrams": "ダイアグラム",
    "migration": "移行計画", "technical-debt": "技術的負債", "specialized": "専門分析",
}
SECTION_ORDER = ["_top", "architecture", "behavior", "analysis", "reference",
                 "diagrams", "migration", "technical-debt", "specialized"]

# 相対パス -> 日本語表示名（既知のもののみ。無ければ H1 → ファイル名にフォールバック）
NAME_MAP = {
    "README.html": "README", "project-overview.html": "プロジェクト概要",
    "technical-debt-report.html": "技術的負債レポート",
    "architecture/system-overview.html": "システム概要", "architecture/components.html": "コンポーネント",
    "architecture/dependencies.html": "依存関係", "architecture/patterns.html": "パターン",
    "behavior/business-logic.html": "ビジネスロジック", "behavior/decision-logic.html": "決定ロジック",
    "behavior/error-handling.html": "エラーハンドリング", "behavior/workflows.html": "ワークフロー",
    "analysis/code-metrics.html": "コードメトリクス", "analysis/complexity-analysis.html": "複雑度分析",
    "analysis/dependency-analysis.html": "依存関係分析", "analysis/security-patterns.html": "セキュリティパターン",
    "analysis/tech-debt.html": "技術的負債",
    "reference/api-reference.html": "APIリファレンス", "reference/data-models.html": "データモデル",
    "reference/interfaces.html": "インターフェース", "reference/modules.html": "モジュール",
    "reference/program-structure.html": "プログラム構造",
    "migration/component-order.html": "コンポーネント移行順序", "migration/test-specifications.html": "テスト仕様",
    "migration/validation-criteria.html": "検証基準",
    "technical-debt/summary.html": "サマリー", "technical-debt/outdated-components.html": "古いコンポーネント",
    "technical-debt/maintenance-burden.html": "メンテナンス負担", "technical-debt/remediation-plan.html": "改善計画",
}

def h1_of(path):
    try:
        with open(path, encoding="utf-8") as fh:
            m = re.search(r"<h1[^>]*>(.*?)</h1>", fh.read(), re.S)
        if m:
            t = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", m.group(1))).strip()
            if t:
                return t
    except Exception:
        pass
    return None

def disp_name(rel, full):
    if rel in NAME_MAP:
        return NAME_MAP[rel]
    parts = rel.split("/")
    # diagrams/<x>/README.html のような README はディレクトリ名で表示
    if os.path.basename(rel) == "README.html" and len(parts) >= 2:
        return parts[-2]
    return h1_of(full) or os.path.basename(rel)[:-5].replace("-", " ").replace("_", " ")

# 実在する .html を収集（index.html/style.css除く）
pages = []
for root, _, files in os.walk(dst):
    for fn in files:
        if fn.endswith(".html") and fn != "index.html":
            pages.append(os.path.relpath(os.path.join(root, fn), dst).replace(os.sep, "/"))

groups = {}
for rel in pages:
    top = "_top" if "/" not in rel else rel.split("/")[0]
    groups.setdefault(top, []).append(rel)

def esc(s): return html.escape(s, quote=True)

# セクション表示順: 既知順 → 未知は末尾にアルファベット順
ordered = [g for g in SECTION_ORDER if g in groups] + sorted(g for g in groups if g not in SECTION_ORDER)

sb = []
for g in ordered:
    title = SECTION_TITLES.get(g, g.replace("-", " "))
    items = sorted(groups[g], key=lambda r: (r.count("/"), r))
    sb.append(f'<h3>{esc(title)}</h3><ul>')
    for rel in items:
        sb.append(f'<li><a href="{esc(rel)}" target="doc">{esc(disp_name(rel, os.path.join(dst, rel)))}</a></li>')
    sb.append('</ul>')
sb = "\n".join(sb)

default_page = "project-overview.html" if "project-overview.html" in pages else ("README.html" if "README.html" in pages else (pages[0] if pages else ""))

index = f'''<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ATX分析ドキュメント</title>
<link rel="stylesheet" href="style.css">
<style>
body {{ display: flex; flex-direction: column; height: 100vh; overflow: hidden; padding: 0; max-width: none; }}
.page-header {{ flex-shrink: 0; background: linear-gradient(135deg, #232f3e 0%, #37475a 100%); color: #fff; padding: 1.5rem 2rem; border-bottom: 3px solid #ff9900; }}
.page-header h1 {{ margin: 0; font-size: 1.4rem; font-weight: 600; border: none; padding: 0; color: #fff; }}
.page-header .subtitle {{ color: #d5dbdb; font-size: 0.85rem; margin-top: 0.3rem; }}
.layout {{ display: flex; flex: 1; overflow: hidden; }}
.sidebar {{ width: 280px; min-width: 280px; background: #232f3e; color: #d5dbdb; overflow-y: auto; padding: 1rem 0; font-size: 0.85rem; }}
.sidebar h3 {{ color: #ff9900; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; padding: 0.8rem 1.2rem 0.3rem; margin: 0; border: none; }}
.sidebar ul {{ list-style: none; margin: 0; padding: 0; }}
.sidebar li a {{ display: block; padding: 0.35rem 1.2rem 0.35rem 1.6rem; color: #d5dbdb; text-decoration: none; transition: background 0.15s, color 0.15s; }}
.sidebar li a:hover {{ background: rgba(255,255,255,0.08); color: #fff; }}
.sidebar li a.active {{ background: #1a73e8; color: #fff; }}
.main-content {{ flex: 1; overflow: hidden; }}
.main-content iframe {{ width: 100%; height: 100%; border: none; }}
</style>
</head>
<body>
<div class="page-header">
<h1>ATX分析ドキュメント</h1>
<div class="subtitle">comprehensive-codebase-analysis 結果</div>
</div>
<div class="layout">
<nav class="sidebar" id="sidebar">
{sb}
</nav>
<main class="main-content"><iframe name="doc" src="{esc(default_page)}"></iframe></main>
</div>
<script>
const sidebar = document.getElementById('sidebar');
sidebar.querySelectorAll('a').forEach(a => a.addEventListener('click', function() {{
  sidebar.querySelectorAll('a').forEach(x => x.classList.remove('active'));
  this.classList.add('active');
}}));
</script>
</body>
</html>
'''
with open(os.path.join(dst, "index.html"), "w", encoding="utf-8") as fh:
    fh.write(index)
print(f"サイドバー項目数: {len(pages)} / デフォルト: {default_page}")
PY

# 成果物の存在検査。`set -e` は「途中で止まる」ことしか保証せず、
# 「33ファイル生成と表示されたのに索引が無い」型の無症状の失敗を防げない。
# 実際に GNU 専用の `sed -i` で失敗し、index.html とリンク書き換えが丸ごと飛んだ事例がある。
if [ ! -f "$DST/index.html" ]; then
  echo "エラー: ${DST}/index.html が生成されなかった（索引が無いと成果物を辿れない）" >&2
  exit 1
fi
if grep -rl 'href="[^"]*\.md"' "$DST" >/dev/null 2>&1; then
  echo "エラー: ${DST} に .md へのリンクが残っている（.md → .html の書き換えが失敗している）" >&2
  grep -rl 'href="[^"]*\.md"' "$DST" | head -5 >&2
  exit 1
fi

echo "完了: $DST/index.html をブラウザで開いてください"
