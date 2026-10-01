#!/bin/bash
# =============================================================================
# build-en.sh — drive generation of the English tree (en/) from the Japanese
#               source of truth (ja/)
# =============================================================================
#
# ja/ is the source of truth. en/ and the root README.md are generated artifacts.
# Translation itself is performed by a human or an AI agent; this script decides
# *what* needs translating and records the sync state once it is done.
#
# Usage:
#   tools/build-en.sh                  Show the files that need (re)generation
#   tools/build-en.sh --stamp <path>   Record the sync state for one entry
#                                      (<path> is relative to ja/)
#   tools/build-en.sh --bootstrap      Record the sync state for ALL entries.
#                                      Only for initial setup, or after a bulk
#                                      regeneration you have already reviewed
#   tools/build-en.sh --list           Print the manifest (no hashing)
#
# Typical workflow:
#   1. vi ja/method/flow.md
#   2. tools/build-en.sh                     -> reports method/flow.md as stale
#   3. (translate ja/method/flow.md into en/method/flow.md, per the glossary)
#   4. tools/build-en.sh --stamp method/flow.md
#   5. tools/check-i18n.sh                   -> PASS
# =============================================================================
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$REPO/tools/i18n-manifest.tsv"
GLOSSARY="$REPO/tools/glossary.tsv"
LOCK="$REPO/tools/i18n.lock"

[ -f "$MANIFEST" ] || { echo "Error: manifest not found: $MANIFEST" >&2; exit 1; }

hash_file() {
  [ -f "$1" ] || { echo "MISSING"; return; }
  if command -v sha1sum >/dev/null 2>&1; then sha1sum "$1" | cut -c1-12
  else shasum -a 1 "$1" | cut -c1-12; fi
}

lock_get() {  # $1=source path, $2=field (2=source hash, 3=generated hash)
  [ -f "$LOCK" ] || return 0
  awk -F'\t' -v p="$1" -v f="$2" '$1==p {print $f; found=1} END{if(!found) print ""}' "$LOCK"
}

entries() { grep -v '^#' "$MANIFEST" | grep -v '^[[:space:]]*$'; }

# --- --list -------------------------------------------------------------------
if [ "${1:-}" = "--list" ]; then
  printf '%-64s %-24s %s\n' "SOURCE (ja/)" "CLASS" "TARGET"
  entries | while IFS=$'\t' read -r src tgt cls flags; do
    printf '%-64s %-24s %s\n' "$src" "$cls" "$tgt"
  done
  exit 0
fi

# --- --stamp / --bootstrap ----------------------------------------------------
stamp_one() {  # $1=source path relative to ja/
  local src="$1" line tgt cls flags
  line="$(entries | awk -F'\t' -v p="$src" '$1==p')"
  if [ -z "$line" ]; then
    echo "Error: not in manifest: $src" >&2
    return 1
  fi
  IFS=$'\t' read -r _ tgt cls flags <<<"$line"
  if [ ! -f "$REPO/ja/$src" ]; then echo "Error: missing ja/$src" >&2; return 1; fi
  if [ ! -f "$REPO/$tgt" ];     then echo "Error: missing $tgt (generate it first)" >&2; return 1; fi
  local sh gh tmp
  sh="$(hash_file "$REPO/ja/$src")"
  gh="$(hash_file "$REPO/$tgt")"
  tmp="$(mktemp)"
  if [ -f "$LOCK" ]; then awk -F'\t' -v p="$src" '$1!=p' "$LOCK" > "$tmp"; else : > "$tmp"; fi
  printf '%s\t%s\t%s\n' "$src" "$sh" "$gh" >> "$tmp"
  LC_ALL=C sort -t$'\t' -k1,1 "$tmp" > "$LOCK"
  rm -f "$tmp"
  echo "  stamped $src  (source=$sh generated=$gh)"
}

if [ "${1:-}" = "--stamp" ]; then
  [ $# -ge 2 ] || { echo "Usage: $0 --stamp <path relative to ja/>" >&2; exit 1; }
  shift
  rc=0
  for p in "$@"; do stamp_one "$p" || rc=1; done
  exit $rc
fi

if [ "${1:-}" = "--bootstrap" ]; then
  echo "=== Bootstrapping tools/i18n.lock for all manifest entries ==="
  : > "$LOCK"
  rc=0
  entries | while IFS=$'\t' read -r src tgt cls flags; do
    sh="$(hash_file "$REPO/ja/$src")"
    gh="$(hash_file "$REPO/$tgt")"
    if [ "$sh" = "MISSING" ] || [ "$gh" = "MISSING" ]; then
      echo "  ⚠️  skipped $src (ja=$sh target=$gh)" >&2
      continue
    fi
    printf '%s\t%s\t%s\n' "$src" "$sh" "$gh"
  done | LC_ALL=C sort -t$'\t' -k1,1 > "$LOCK"
  echo "  recorded $(wc -l < "$LOCK" | tr -d ' ') entries in tools/i18n.lock"
  exit $rc
fi

if [ $# -gt 0 ]; then
  echo "Usage: $0 [--list | --stamp <path>... | --bootstrap]" >&2
  exit 1
fi

# --- default: report what needs (re)generation --------------------------------
stale_src=""; missing_tgt=""; edited_tgt=""
while IFS=$'\t' read -r src tgt cls flags; do
  cur_src="$(hash_file "$REPO/ja/$src")"
  cur_tgt="$(hash_file "$REPO/$tgt")"
  lock_src="$(lock_get "$src" 2)"
  lock_tgt="$(lock_get "$src" 3)"
  if [ "$cur_tgt" = "MISSING" ]; then
    missing_tgt="${missing_tgt}${src}|${tgt}|${cls}|${flags}"$'\n'
  elif [ -z "$lock_src" ]; then
    missing_tgt="${missing_tgt}${src}|${tgt}|${cls}|${flags} (not in lock)"$'\n'
  elif [ "$cur_src" != "$lock_src" ]; then
    stale_src="${stale_src}${src}|${tgt}|${cls}|${flags}"$'\n'
  elif [ "$cur_tgt" != "$lock_tgt" ]; then
    edited_tgt="${edited_tgt}${src}|${tgt}|${cls}|${flags}"$'\n'
  fi
done < <(entries)

total=$(entries | wc -l | tr -d ' ')
n_stale=$(printf '%s' "$stale_src" | grep -c . || true)
n_missing=$(printf '%s' "$missing_tgt" | grep -c . || true)
n_edited=$(printf '%s' "$edited_tgt" | grep -c . || true)

echo "=== build-en: $total manifest entries ==="
if [ "$n_stale" -eq 0 ] && [ "$n_missing" -eq 0 ] && [ "$n_edited" -eq 0 ]; then
  echo "  ✅ Nothing to do — en/ is in sync with ja/"
  exit 0
fi

show() {  # $1=title, $2=payload
  [ -n "$2" ] || return 0
  echo ""
  echo "$1"
  printf '%s' "$2" | while IFS='|' read -r src tgt cls flags; do
    [ -n "$src" ] || continue
    printf '    ja/%-58s ->  %-40s [%s%s]\n' "$src" "$tgt" "$cls" \
      "$([ "$flags" != "-" ] && [ -n "$flags" ] && echo ", $flags")"
  done
}

show "-- Target missing: generate it --"                       "$missing_tgt"
show "-- Source changed: retranslate the target --"            "$stale_src"
show "-- Target edited directly: discard and regenerate it --"  "$edited_tgt"

cat <<EOF

--- Translation rules ---
  * ja/ is the source of truth. Never edit the target to "fix" content —
    edit ja/ and regenerate.
  * Use the terminology dictionary: tools/glossary.tsv
    (CP-N / DP-N / HOLD-N / Tier / Phase / Mode A-C are never translated)
  * class=translate           : translate the whole file
  * class=translate-comments  : translate comments and user-facing strings only.
                                Code lines MUST stay byte-identical
  * class=copy                : copy verbatim
  * flag=code-identical       : check-i18n.sh enforces byte-identical code lines
  * flag=root-readme          : generated at the repository root. Relative links to
                                method/ harness/ playbooks/ MUST be prefixed with en/
  * Preserve structure exactly: heading levels, table rows, code blocks, list nesting

--- After translating ---
  tools/build-en.sh --stamp <path>    # record the sync state
  tools/check-i18n.sh                 # verify
EOF
exit 1
