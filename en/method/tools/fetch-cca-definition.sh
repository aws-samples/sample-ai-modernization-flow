#!/bin/bash
# Fetch the CCA definition used by agent-direct analysis (0a-5b) from upstream and verify its hash
#
# Usage:   ./fetch-cca-definition.sh <destination> [--ref <commit|branch>]
# Example: 00-analysis/fetch-cca-definition.sh 00-analysis/<repo-id>/cca-instructions.md
#
# Source: aws-managed-definitions/comprehensive-codebase-analysis/codebase-analysis.md in
#         aws-samples/aws-transform-custom-samples (MIT-0)
# By default it fetches from a pinned commit (PINNED_COMMIT below) and verifies the SHA-256; on a mismatch it aborts.
# With `--ref <value>` it fetches from that commit or branch (e.g. main). **No verification** (it warns).
#
# Output: the last 2 lines are `COMMIT=<ref>` and `DEFINITION=<destination>` (used for the origin line in 0a-5b)
# Exit code: 0 = success / 1 = fetch or verification failure / 2 = argument error
# Requires: curl, and either sha256sum or shasum
#
# Easy to break when editing:
#   - **Do not make the latest version (main) the default.** The definition ATX actually uses cannot be fetched
#     (reserved `AWS/` name), so its content cannot be checked. The pinned commit and hash let the definition
#     used for an analysis be identified later
#   - **Never leave a file that failed verification at the destination** (fetch to a temp file, move after verifying)
#   - On macOS bash 3.2, a full-width character right after `$var` may be read as part of the variable name.
#     Write variables in messages as `${var}`
#   - Do not use `readlink -f` / `date -d` / `stat -c` (CP-12)
#

set -u

PINNED_COMMIT="1b155b8fda921ba6abb504f9916fee75c33b81c4"   # 2026-03-27
PINNED_SHA256="96bb6c3f5a820aae566e68efc6d1b694afdeefee76e424964edd2ce181926b68"
REPO_PATH="aws-samples/aws-transform-custom-samples"
FILE_PATH="aws-managed-definitions/comprehensive-codebase-analysis/codebase-analysis.md"

usage() { echo "Usage: $0 <destination> [--ref <commit|branch>]" >&2; exit 2; }

DEST=""; REF=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ref) [ "$#" -ge 2 ] || usage; REF="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) [ -z "$DEST" ] || usage; DEST="$1"; shift ;;
  esac
done
[ -n "$DEST" ] || usage

command -v curl >/dev/null 2>&1 || { echo "Error: curl not found" >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  echo "Error: neither sha256sum nor shasum found" >&2; exit 1
fi

COMMIT="${REF:-$PINNED_COMMIT}"
URL="https://raw.githubusercontent.com/${REPO_PATH}/${COMMIT}/${FILE_PATH}"

DEST_DIR="$(dirname "$DEST")"
mkdir -p "$DEST_DIR" || { echo "Error: cannot create the destination directory: ${DEST_DIR}" >&2; exit 1; }
TMP="$(mktemp "${DEST_DIR}/.cca-definition.XXXXXX")" || { echo "Error: cannot create a temp file" >&2; exit 1; }
trap 'rm -f "$TMP"' EXIT

if ! curl -fsSL --retry 2 -o "$TMP" "$URL"; then
  echo "Error: cannot fetch the definition: ${URL}" >&2
  exit 1
fi
if [ ! -s "$TMP" ]; then
  echo "Error: the fetched definition is empty: ${URL}" >&2
  exit 1
fi

GOT="$(sha256 "$TMP")"
if [ -z "$REF" ]; then
  if [ "$GOT" != "$PINNED_SHA256" ]; then
    echo "Error: the definition hash does not match (expected ${PINNED_SHA256} / actual ${GOT})." >&2
    echo "       Never proceed with the analysis using this definition. Source: ${URL}" >&2
    exit 1
  fi
  echo "Fetched the definition and verified its hash (commit ${COMMIT}, SHA-256 ${GOT})"
else
  echo "Warning: fetched with --ref ${REF}, so the hash was not verified (SHA-256 ${GOT})." >&2
  echo "         Keep this file in the records repository so the definition used can be identified later" >&2
fi

mv "$TMP" "$DEST" || { echo "Error: cannot write the destination: ${DEST}" >&2; exit 1; }
trap - EXIT
echo "COMMIT=${COMMIT}"
echo "DEFINITION=${DEST}"
exit 0
