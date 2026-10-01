---
name: migration-tree-setup
description: 実装ツリー（実装ツリー）の作成手順と起点情報の記録。Phase 3 Step 1 でsetup-modernized.shを実行するとき、または2リポジトリ運用の構成を確認するときに参照する。
---

# 実装ツリーのセットアップ（Phase 3 Step 1）

## 2リポジトリ運用の構成

| リポジトリ | 内容 | コミット対象 |
|-----------|------|-------------|
| `<project>-migration-<date>/` | 記録・計画・検証（worklog, plan, test, docs） | 記録・知見・検証スクリプト |
| `<product>-modernized/` | 実装ツリーソース＋ビルドシステム | コード変更（成果物は.gitignore） |

- 両者は**同列**（兄弟ディレクトリ）に置く。verify.sh は `MODERNIZED=../<product>-modernized` で参照
- 対象ソース（オリジナル）は**直接変更しない**（Off-limits）

## setup-modernized.sh の実行

migration プロジェクト直下で:

```bash
./setup-modernized.sh <ソースパス> <target-os>-<arch> [base-ref]
# 例: ./setup-modernized.sh /path/to/myapp amzn2023-x86_64-lp64
```

- 移行元が git 管理: clone で履歴を引き継ぎ、ブランチ `modernize/<target-os>-<arch>` を切り、
  起点に `modernize-base` タグを打つ
- 移行元が非 git: コピーして `git init`、初期コミット + `modernize-base` タグ
- ビルド成果物（言語に応じた生成物。Playbook の modernized-gitignore.template を使用）は 実装ツリー側 .gitignore で除外（再生成可能）

## 起点情報の記録（再現性のため必須）

実行後、以下を `03-worklog/session-context.md` と `01-plan/work-plan.md` に記録する:

- 移行元 source パス（と git/非git の別）
- 起点 base-ref（タグ or SHA）と `modernize-base` タグの SHA
- modernize ブランチ名（`modernize/<target-os>-<arch>`）
- 変更差分の確認コマンド: `(cd ../<product>-modernized && git diff modernize-base..HEAD)`

## 移行元が git の場合の注意

- clone 元（upstream）の保護ブランチに push/commit しない
- 作業は `modernize/<target>` ブランチでのみ行う

## Step 1 完了の条件

- 実装ツリーが作成され、起点情報が記録されている
- **verify.sh の smoke ゲートが実装されている**（未実装のまま Step 2 以降に進むのは禁止 — コア規律 Tier 1・非同期レビューゾーン 参照）
