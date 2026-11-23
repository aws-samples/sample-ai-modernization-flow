#!/bin/bash
# エージェント直接分析（0a-5b）で使う CCA の指示書を upstream から取得し、ハッシュで照合する
#
# 使い方: ./fetch-cca-definition.sh <保存先> [--ref <コミット|ブランチ>]
# 例:     00-analysis/fetch-cca-definition.sh 00-analysis/<repo-id>/cca-instructions.md
#
# 取得元: aws-samples/aws-transform-custom-samples（MIT-0）の
#         aws-managed-definitions/comprehensive-codebase-analysis/codebase-analysis.md
# 既定は固定コミット（下の PINNED_COMMIT）から取得し、SHA-256 を照合する。不一致なら中止する。
# `--ref <値>` を付けると、そのコミットやブランチ（例: main）から取得する。**照合しない**（警告を出す）。
#
# 出力: 最後の 2 行に `COMMIT=<参照>` と `DEFINITION=<保存先>` を出す（0a-5b の生成元の記録に使う）
# 終了コード: 0 = 成功 / 1 = 取得または照合の失敗 / 2 = 引数エラー
# 依存: curl と、sha256sum か shasum のどちらか
#
# 触るときに壊しやすい点:
#   - **既定を最新版（main）にしない。** ATX が実際に使う定義は `AWS/` 予約名で取得できず中身を確かめられない。
#     固定コミットとハッシュで、分析に使った指示書を後から特定できるようにしている
#   - **照合に失敗したファイルを保存先に残さない**（一時ファイルに取得し、照合後に移す）
#   - macOS の bash 3.2 では `$var` の直後に全角文字を置くと変数名の一部として読まれることがある。
#     メッセージ内の変数は `${var}` と書く
#   - `readlink -f` / `date -d` / `stat -c` は使わない（CP-12）
#

set -u

PINNED_COMMIT="1b155b8fda921ba6abb504f9916fee75c33b81c4"   # 2026-03-27
PINNED_SHA256="96bb6c3f5a820aae566e68efc6d1b694afdeefee76e424964edd2ce181926b68"
REPO_PATH="aws-samples/aws-transform-custom-samples"
FILE_PATH="aws-managed-definitions/comprehensive-codebase-analysis/codebase-analysis.md"

usage() { echo "使い方: $0 <保存先> [--ref <コミット|ブランチ>]" >&2; exit 2; }

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

command -v curl >/dev/null 2>&1 || { echo "エラー: curl が見つからない" >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  echo "エラー: sha256sum も shasum も見つからない" >&2; exit 1
fi

COMMIT="${REF:-$PINNED_COMMIT}"
URL="https://raw.githubusercontent.com/${REPO_PATH}/${COMMIT}/${FILE_PATH}"

DEST_DIR="$(dirname "$DEST")"
mkdir -p "$DEST_DIR" || { echo "エラー: 保存先のディレクトリを作れない: ${DEST_DIR}" >&2; exit 1; }
TMP="$(mktemp "${DEST_DIR}/.cca-definition.XXXXXX")" || { echo "エラー: 一時ファイルを作れない" >&2; exit 1; }
trap 'rm -f "$TMP"' EXIT

if ! curl -fsSL --retry 2 -o "$TMP" "$URL"; then
  echo "エラー: 指示書を取得できない: ${URL}" >&2
  exit 1
fi
if [ ! -s "$TMP" ]; then
  echo "エラー: 取得した指示書が空である: ${URL}" >&2
  exit 1
fi

GOT="$(sha256 "$TMP")"
if [ -z "$REF" ]; then
  if [ "$GOT" != "$PINNED_SHA256" ]; then
    echo "エラー: 指示書のハッシュが一致しない（期待 ${PINNED_SHA256} / 実際 ${GOT}）。" >&2
    echo "        この指示書を使って分析を進めてはならない。取得元: ${URL}" >&2
    exit 1
  fi
  echo "指示書を取得し、ハッシュを照合した（コミット ${COMMIT}、SHA-256 ${GOT}）"
else
  echo "警告: --ref ${REF} で取得したため、ハッシュを照合していない（SHA-256 ${GOT}）。" >&2
  echo "      分析時点の指示書を特定できるよう、このファイルを記録リポジトリに残すこと" >&2
fi

mv "$TMP" "$DEST" || { echo "エラー: 保存先に書けない: ${DEST}" >&2; exit 1; }
trap - EXIT
echo "COMMIT=${COMMIT}"
echo "DEFINITION=${DEST}"
exit 0
