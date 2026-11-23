#!/bin/bash
# Render the mermaid diagrams of the HTML-converted analysis results in a headless browser and detect syntax errors
#
# Usage:   ./check-mermaid.sh <HTML directory>
# Example: cd 00-analysis/<repo-id> && ../check-mermaid.sh ATXDocumentation_html
#          (run it on the output of generate-html.sh; 0a-6)
#
# Verdict: for each page with diagrams, in the rendered DOM
#            the count of "Syntax error in" = 0  and  rendered diagrams (<svg id="mermaid-...">) = diagrams
#          The diagram count is the number of <pre class="mermaid"> in the HTML before rendering.
#          If elements carry a mermaid class but no <pre class="mermaid"> is found, it fails as a detection miss
#          (when newer pandoc highlights them into <pre class="sourceCode mermaid">, 0 diagrams would pass silently).
# Exit code: 0 = every diagram rendered (with no diagrams at all, it prints ⚠️ and exits 0) /
#            1 = an error, an unrendered diagram or a detection miss / 2 = argument error
#            **Without a browser it prints "not verified" and exits 0** (the work does not stop;
#            record "not verified" in analysis-runs.md)
#
# Browser search order: the MERMAID_CHECK_BROWSER environment variable -> chrome / chromium / msedge etc.
#   on the PATH -> the standard locations per OS (macOS Chrome / Chromium / Edge, Windows Chrome / Edge).
#   Windows 10/11 ship with Edge.
#
# Easy to break when editing:
#   - **On Windows (Git Bash), pass the browser Windows-style paths** (`C:/...` via `cygpath -m`).
#     The browser does not understand `/c/...`. The same goes for the working profile directory
#   - **Do not use the `timeout` command** (macOS has none; on Windows it collides with cmd's timeout).
#     The browser is started in the background and stopped after `MERMAID_CHECK_TIMEOUT` seconds (default 60)
#   - A diagram with a syntax error is also rendered as <svg id="mermaid-...">. Errors are counted by their text
#   - Do not use `readlink -f` / `date -d` / `stat -c` (CP-12). Runs on macOS bash 3.2
#   - Not verified on Windows (Edge / Chrome); verified with Chrome on macOS
#

set -u

DIR="${1:-}"
if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
  echo "Usage: $0 <HTML directory> (the output of generate-html.sh)" >&2
  exit 2
fi
LIMIT="${MERMAID_CHECK_TIMEOUT:-60}"

# --- Find a browser -----------------------------------------------------------
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
  echo "The browser set in MERMAID_CHECK_BROWSER cannot be run: ${BROWSER}" >&2
  exit 2
fi
if [ -z "$BROWSER" ]; then
  echo "Not verified: no browser usable headless (Chrome / Chromium / Edge) was found."
  echo "              Re-run with MERMAID_CHECK_BROWSER=<browser path>, or record \"mermaid not verified\" in analysis-runs.md"
  exit 0
fi

# On Windows (Git Bash), give the browser Windows-style paths
to_native() {  # $1 = absolute path
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

PROFILE="$(mktemp -d 2>/dev/null || mktemp -d -t mmcheck)"
DOM="$PROFILE/dom.html"
trap 'rm -rf "$PROFILE"' EXIT

# --- Render one page and dump its DOM (cut off after the time limit) ---------
render() {  # $1 = absolute path of the HTML. 0 on success
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
    # A page that looks like it has no diagrams but does carry an element with a mermaid
    # class is a detection miss. Newer pandoc highlights mermaid blocks and emits
    # <pre class="sourceCode mermaid">: the browser still renders them, but this gate
    # reports 0 diagrams = pass. Do not let that through silently
    if grep -q 'class="[^"]*mermaid' "$f"; then suspect=$((suspect + 1)); fi
    continue
  fi
  pages=$((pages + 1)); diagrams=$((diagrams + want))
  rel="${f#"$ABS_DIR"/}"
  if ! render "$f"; then
    echo "❌ ${rel}: rendering did not finish in ${LIMIT} seconds (extend with MERMAID_CHECK_TIMEOUT)"
    bad=$((bad + 1)); continue
  fi
  err="$(grep -o 'Syntax error in' "$DOM" | wc -l | tr -d ' ')"
  got="$(grep -o '<svg[^>]*id="mermaid-' "$DOM" | wc -l | tr -d ' ')"
  if [ "$err" -gt 0 ] || [ "$got" -ne "$want" ]; then
    echo "❌ ${rel}: diagrams ${want} / rendered ${got} / syntax errors ${err}"
    bad=$((bad + 1))
  fi
done < <(find "$ABS_DIR" -type f -name '*.html' | LC_ALL=C sort)

echo "Browser: ${BROWSER}"
if [ "$suspect" -gt 0 ]; then
  echo "❌ mermaid: ${suspect} pages carry an element with a mermaid class, yet not a single <pre class=\"mermaid\"> was found."
  echo "   Suspect the HTML generator. When pandoc highlights a mermaid block it becomes <pre class=\"sourceCode mermaid\">,"
  echo "   which disables this gate (check that generate-html.sh turns highlighting off)"
  exit 1
fi
if [ "$pages" -eq 0 ]; then
  echo "⚠️ mermaid: scanned ${htmls} pages and found no mermaid diagram. Rendering was not verified"
  exit 0
fi
if [ "$bad" -eq 0 ]; then
  echo "✅ mermaid: rendered all ${diagrams} diagrams on ${pages} pages (0 syntax errors)"
  exit 0
fi
echo "❌ mermaid: ${bad} of ${pages} pages have problems (${diagrams} diagrams in total)."
echo "   A failing diagram is identified by its position among the <svg> elements on the page. Common causes: ';' in a"
echo "   sequence diagram message, a second ':' in a state diagram label, a classDiagram class body on one line split by ';'"
exit 1
