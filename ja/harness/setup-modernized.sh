#!/bin/bash
# =============================================================================
# 実装ツリー(<product>-modernized) セットアップスクリプト
# =============================================================================
#
# Phase 3 Step 1（ソース取得時）に実行する。
# 対象ソースから作業用ツリーを用意し、独立 git リポジトリとして初期化する。
#
#   - 移行元が git 管理されている場合: clone して履歴を引き継ぎ、
#     作業ブランチ modernize/<target> を切り、起点に modernize-base タグを打つ。
#   - 移行元が git 管理されていない場合: コピーして git init し、初期コミット + modernize-base。
#
# 配置: 作成する <product>-modernized は移行元と同じ親ディレクトリ（=移行プロジェクトと同列）に置く。
#
# 使い方:
#   ./setup-modernized.sh <source-path> <target> [base-ref]
#     <source-path> : 対象ソースのパス（git作業ツリー or 通常ディレクトリ）
#     <target>      : ブランチ名サフィックス。規約 <target-os>-<arch>
#                     例: amzn2023-x86_64-lp64  → ブランチ modernize/amzn2023-x86_64-lp64
#     [base-ref]    : 起点にするタグ/コミット（省略時は移行元の現在 HEAD）
#
# 例:
#   ./setup-modernized.sh /path/to/workspace/myapp-1.0 amzn2023-x86_64-lp64 myapp-1.0
# =============================================================================
set -euo pipefail

SRC="${1:-}"
TARGET="${2:-}"
BASE_REF="${3:-}"

if [ -z "$SRC" ] || [ -z "$TARGET" ]; then
  echo "Usage: $0 <source-path> <target> [base-ref]"
  echo "  例: $0 /path/to/workspace/myapp-1.0 amzn2023-x86_64-lp64 myapp-1.0"
  exit 1
fi

if [ ! -d "$SRC" ]; then
  echo "Error: source not found: $SRC"
  exit 1
fi

SRC="$(cd "$SRC" && pwd)"                 # 絶対パス化
PARENT="$(dirname "$SRC")"
NAME="$(basename "$SRC")"
MODERNIZED="${PARENT}/${NAME}-modernized"
BRANCH="modernize/${TARGET}"

if [ -e "$MODERNIZED" ]; then
  echo "Error: target already exists: $MODERNIZED"
  exit 1
fi

# ビルド成果物の ignore
#   優先1: スクリプトと同じディレクトリの modernized-gitignore.template（Playbookが提供、install.shが配置）
#   優先2: 環境変数 MODERNIZED_IGNORE_FILE で指定されたファイル
#   フォールバック: 最小限の汎用パターン（★Step 1 でビルドシステムに合わせ調整すること）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
write_artifact_gitignore() {
  local dst="$1"
  local src="${MODERNIZED_IGNORE_FILE:-$SCRIPT_DIR/modernized-gitignore.template}"
  if [ -f "$src" ]; then
    { echo ""; cat "$src"; } >> "$dst"
    echo "  (gitignore: $src を適用)"
  else
    cat >> "$dst" <<'EOF'

# --- [port] build artifacts (generic fallback / ビルドシステムに合わせ調整すること) ---
# Playbook の modernized-gitignore.template が見つからなかったため最小パターンのみ。
*~
*.log
*.tmp
EOF
    echo "  (gitignore: 汎用フォールバックを適用 — 要調整)"
  fi
}

echo "=== 実装ツリーのセットアップ ==="
echo "  source : $SRC"
echo "  実装ツリー : $MODERNIZED"
echo "  branch : $BRANCH"

if git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
  # ---- git 管理ソース: clone + branch + modernize-base ----
  MODE="git-clone"
  git clone "$SRC" "$MODERNIZED"
  cd "$MODERNIZED"
  git fetch --all --tags >/dev/null 2>&1 || true
  if [ -n "$BASE_REF" ]; then
    git switch -c "$BRANCH" "$BASE_REF"
  else
    git switch -c "$BRANCH"
  fi
  BASE_SHA="$(git rev-parse HEAD)"
  git tag modernize-base
  # upstream の .gitignore を尊重し、移行で生じる成果物だけ追記
  touch .gitignore
  write_artifact_gitignore .gitignore
  git add .gitignore
  git commit -q -m "[port] add build-artifact ignores for ${TARGET}"
else
  # ---- 非 git ソース: copy + init + modernize-base ----
  MODE="copy-init"
  cp -a "$SRC" "$MODERNIZED"
  cd "$MODERNIZED"
  rm -rf .git 2>/dev/null || true
  : > .gitignore
  write_artifact_gitignore .gitignore
  git init -q
  git add -A
  git commit -q -m "Initial commit: ${NAME} 実装ツリー (${TARGET})"
  git branch -m "$BRANCH"
  BASE_SHA="$(git rev-parse HEAD)"
  git tag modernize-base
fi

echo ""
echo "=== 完了 ($MODE) ==="
echo "  実装ツリー   : $MODERNIZED"
echo "  branch    : $BRANCH"
echo "  modernize-base : $BASE_SHA"
echo ""
echo "次に、移行プロジェクトの session-context.md / work-plan.md の「起点情報」に以下を記録すること:"
echo "  - 移行元(source)     : $SRC  (mode=$MODE)"
echo "  - 起点 base-ref      : ${BASE_REF:-HEAD}"
echo "  - 起点 SHA(modernize-base): $BASE_SHA"
echo "  - portブランチ       : $BRANCH"
echo ""
echo "変更差分はいつでも: (cd $MODERNIZED && git diff modernize-base..HEAD)"
