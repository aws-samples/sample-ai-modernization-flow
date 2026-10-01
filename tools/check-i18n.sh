#!/bin/bash
# =============================================================================
# check-i18n.sh — verify that the generated English tree is in sync with ja/
# =============================================================================
#
# ja/ is the source of truth; en/ and the root README.md are generated.
# This script fails if any of the following holds:
#
#   1. A manifest entry's source or target file is missing
#   2. tools/i18n.lock has no record for an entry
#   3. The ja/ file changed since the target was generated
#      -> the translation must be redone
#   4. The target changed without going through generation
#      -> someone edited a generated file directly; discard and regenerate
#   5. ja/ and en/ do not have identical file sets
#   6. The shared anchors (CP-N / DP-N / HOLD-N) do not match 1:1 between a
#      source and its target
#   7. A shell script fails `bash -n` on either side
#   8. A `code-identical` entry has diverging code lines (non-comment, non-echo)
#   9. A `root-readme` entry links into method/ harness/ playbooks/ without the
#      en/ prefix
#
# Usage:  tools/check-i18n.sh [-q]
# Exit:   0 = PASS, 1 = FAIL
# =============================================================================
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$REPO/tools/i18n-manifest.tsv"
LOCK="$REPO/tools/i18n.lock"
QUIET=0
[ "${1:-}" = "-q" ] && QUIET=1

FAIL=0
note() { [ "$QUIET" -eq 1 ] || echo "$@"; }
err()  { echo "❌ $*"; FAIL=1; }

[ -f "$MANIFEST" ] || { echo "❌ manifest not found: $MANIFEST"; exit 1; }
[ -f "$LOCK" ]     || { echo "❌ lock not found: $LOCK (run tools/build-en.sh --bootstrap)"; exit 1; }

hash_file() {
  [ -f "$1" ] || { echo "MISSING"; return; }
  if command -v sha1sum >/dev/null 2>&1; then sha1sum "$1" | cut -c1-12
  else shasum -a 1 "$1" | cut -c1-12; fi
}
entries() { grep -v '^#' "$MANIFEST" | grep -v '^[[:space:]]*$'; }
# Compare the SET of anchors, not their occurrence counts: a range expression
# legitimately differs between languages (e.g. "DP-1〜7" vs "DP-1 through DP-7").
ids()      { grep -Eo 'CP-[0-9]+|DP-[0-9]+|HOLD-[0-9]+' "$1" 2>/dev/null | LC_ALL=C sort -u; }
codelines() {
  grep -vE '^[[:space:]]*#' "$1" \
    | grep -vE '^[[:space:]]*(echo|printf)([[:space:]]|$)' \
    | sed -E 's/[[:space:]]+$//' | grep -vE '^$'
}

# --- 1-4, 6, 8, 9: per-entry checks -------------------------------------------
n=0
while IFS=$'\t' read -r src tgt cls flags; do
  n=$((n+1))
  ja="$REPO/ja/$src"; en="$REPO/$tgt"
  [ -f "$ja" ] || { err "missing source: ja/$src"; continue; }
  [ -f "$en" ] || { err "missing target: $tgt (run tools/build-en.sh)"; continue; }

  lock_line="$(awk -F'\t' -v p="$src" '$1==p' "$LOCK")"
  if [ -z "$lock_line" ]; then
    err "no lock record: $src (run tools/build-en.sh --stamp $src)"
    continue
  fi
  lock_src="$(printf '%s' "$lock_line" | cut -f2)"
  lock_tgt="$(printf '%s' "$lock_line" | cut -f3)"
  cur_src="$(hash_file "$ja")"
  cur_tgt="$(hash_file "$en")"

  if [ "$cur_src" != "$lock_src" ]; then
    err "out of sync: ja/$src changed ($lock_src -> $cur_src)"
    note "     the translation in $tgt must be redone, then: tools/build-en.sh --stamp $src"
  fi
  if [ "$cur_tgt" != "$lock_tgt" ]; then
    err "generated file edited directly: $tgt ($lock_tgt -> $cur_tgt)"
    note "     $tgt is generated from ja/$src. Discard the edit and regenerate"
  fi

  # shared anchors must correspond 1:1
  if ! diff -q <(ids "$ja") <(ids "$en") >/dev/null 2>&1; then
    err "anchor mismatch (CP-N/DP-N/HOLD-N) between ja/$src and $tgt"
    [ "$QUIET" -eq 1 ] || diff <(ids "$ja") <(ids "$en") | sed 's/^/       /'
  fi

  case ",$flags," in
    *,code-identical,*)
      if ! diff -q <(codelines "$ja") <(codelines "$en") >/dev/null 2>&1; then
        err "code lines diverge in $tgt (flag: code-identical)"
        [ "$QUIET" -eq 1 ] || diff <(codelines "$ja") <(codelines "$en") | sed 's/^/       /'
      fi ;;
  esac

  case ",$flags," in
    *,root-readme,*)
      if grep -nE '\]\((method|harness|playbooks)/' "$en" >/dev/null 2>&1; then
        err "$tgt links into method/ harness/ playbooks/ without the en/ prefix"
        [ "$QUIET" -eq 1 ] || grep -nE '\]\((method|harness|playbooks)/' "$en" | sed 's/^/       /'
      fi ;;
  esac
done < <(entries)

# --- 5: ja/ and en/ must hold the same file set --------------------------------
# ja/README.md is generated to the repository root, so it has no en/ counterpart.
ja_files() { (cd "$REPO/ja" && find . -type f | grep -v '^\./README\.md$' | LC_ALL=C sort); }
en_files() { (cd "$REPO/en" && find . -type f | LC_ALL=C sort); }
if ! diff -q <(ja_files) <(en_files) >/dev/null 2>&1; then
  err "ja/ and en/ file sets differ (ja/README.md is generated to the repository root, so it is excluded)"
  [ "$QUIET" -eq 1 ] || diff <(ja_files) <(en_files) | sed 's/^/       /'
fi

# --- 7: shell syntax on both sides --------------------------------------------
while IFS= read -r f; do
  bash -n "$f" 2>/dev/null || err "bash -n failed: ${f#"$REPO"/}"
done < <(find "$REPO/ja" "$REPO/en" -type f \( -name '*.sh' -o -name '*.sh.template' \) | LC_ALL=C sort)

# --- result -------------------------------------------------------------------
echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "✅ PASS — $n entries in sync (ja/ -> en/ + root README.md)"
  exit 0
fi
echo "FAIL — see the messages above. Regenerate with tools/build-en.sh"
exit 1
