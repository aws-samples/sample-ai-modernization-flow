#!/bin/bash
# Convert ATX CCA results (Markdown) into browsable HTML
#
# Usage: ./generate-html.sh <input dir> <output dir>
# Example: cd 00-analysis/<repo-id> && ../generate-html.sh ATXDocumentation ATXDocumentation_html
#
# Requires: pandoc (brew install pandoc / sudo dnf install pandoc) and python3 (sidebar generation)
#
# Notes:
#   - Give the input and output directories as relative paths (absolute paths are unsupported)
#   - They are resolved relative to the current directory
#   - The output holds index.html + style.css + mermaid.min.js + one HTML page per document
#   - Works on both BSD (macOS) and GNU (Linux): the incompatible `sed -i` is avoided
#   - ``` mermaid ``` blocks are rendered as diagrams. ASCII-art diagrams stay as text, so the real
#     remedy is to pass "All diagrams MUST be mermaid not ASCII art." when running ATX (0a-4)
#


set -e

SRC="${1:?Usage: $0 <input MD dir> <output HTML dir>}"
DST="${2:?Usage: $0 <input MD dir> <output HTML dir>}"

mkdir -p "$DST"

# Generate style.css
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

# Bundle Mermaid.js locally (renders ```mermaid as diagrams; works offline)
MERMAID_OK=0
if curl -fsSL -o "$DST/mermaid.min.js" https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js 2>/dev/null && [ -s "$DST/mermaid.min.js" ]; then
  MERMAID_OK=1
  echo "Bundled mermaid.min.js ($(wc -c < "$DST/mermaid.min.js" | tr -d ' ') bytes)"
else
  echo "Warning: could not download mermaid.min.js; falling back to the CDN (viewing then needs internet access)" >&2
fi

# Convert every MD file to HTML
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
<html lang="en">
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

# Rewrite .md links to .html (BSD/GNU portable: via a temp file, since sed -i is incompatible)
find "$DST" -name "*.html" | while read -r hf; do
  tmp="${hf}.tmp.$$"
  sed 's/href="\([^"]*\)\.md"/href="\1.html"/g' "$hf" > "$tmp" && mv "$tmp" "$hf"
done

# Generate index.html (with the sidebar)
# Build the sidebar by walking the .html files actually generated.
# Because it is not a fixed list there are no dead links or orphan pages (it follows per-repository differences).
# Each top-level directory gets a section name, and known files get a display name.
python3 - "$DST" <<'PY'
import os, sys, html, re

dst = sys.argv[1]

# top-level directory -> section name (an unknown directory becomes the heading as-is)
SECTION_TITLES = {
    "_top": "Overview", "architecture": "Architecture", "behavior": "Behaviour",
    "analysis": "Code analysis", "reference": "Reference", "diagrams": "Diagrams",
    "migration": "Migration plan", "technical-debt": "Technical debt", "specialized": "Specialised analysis",
}
SECTION_ORDER = ["_top", "architecture", "behavior", "analysis", "reference",
                 "diagrams", "migration", "technical-debt", "specialized"]

# relative path -> display name (known ones only; otherwise fall back to the H1, then the file name)
NAME_MAP = {
    "README.html": "README", "project-overview.html": "Project overview",
    "technical-debt-report.html": "Technical debt report",
    "architecture/system-overview.html": "System overview", "architecture/components.html": "Components",
    "architecture/dependencies.html": "Dependencies", "architecture/patterns.html": "Patterns",
    "behavior/business-logic.html": "Business logic", "behavior/decision-logic.html": "Decision logic",
    "behavior/error-handling.html": "Error handling", "behavior/workflows.html": "Workflows",
    "analysis/code-metrics.html": "Code metrics", "analysis/complexity-analysis.html": "Complexity analysis",
    "analysis/dependency-analysis.html": "Dependency analysis", "analysis/security-patterns.html": "Security patterns",
    "analysis/tech-debt.html": "Technical debt",
    "reference/api-reference.html": "API reference", "reference/data-models.html": "Data models",
    "reference/interfaces.html": "Interfaces", "reference/modules.html": "Modules",
    "reference/program-structure.html": "Program structure",
    "migration/component-order.html": "Component migration order", "migration/test-specifications.html": "Test specifications",
    "migration/validation-criteria.html": "Validation criteria",
    "technical-debt/summary.html": "Summary", "technical-debt/outdated-components.html": "Outdated components",
    "technical-debt/maintenance-burden.html": "Maintenance burden", "technical-debt/remediation-plan.html": "Remediation plan",
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
    # A README such as diagrams/<x>/README.html is shown under its directory name
    if os.path.basename(rel) == "README.html" and len(parts) >= 2:
        return parts[-2]
    return h1_of(full) or os.path.basename(rel)[:-5].replace("-", " ").replace("_", " ")

# Collect the .html files that exist (excluding index.html / style.css)
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

# Section order: the known order first, then unknown ones alphabetically at the end
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
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ATX Analysis Documentation</title>
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
<h1>ATX Analysis Documentation</h1>
<div class="subtitle">comprehensive-codebase-analysis results</div>
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
print(f"Sidebar entries: {len(pages)} / default: {default_page}")
PY

# Verify the artifacts exist. `set -e` only guarantees "it stops partway"; it cannot prevent the
# symptomless failure of "it reported 33 files generated but there is no index".
# In practice a GNU-only `sed -i` failed and took index.html and the link rewriting with it.
if [ ! -f "$DST/index.html" ]; then
  echo "Error: ${DST}/index.html was not generated (without the index the results are unreachable)" >&2
  exit 1
fi
if grep -rl 'href="[^"]*\.md"' "$DST" >/dev/null 2>&1; then
  echo "Error: links to .md remain under ${DST} (the .md -> .html rewrite failed)" >&2
  grep -rl 'href="[^"]*\.md"' "$DST" | head -5 >&2
  exit 1
fi

echo "Done: open $DST/index.html in a browser"
