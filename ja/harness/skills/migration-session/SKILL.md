---
name: migration-session
description: セッションの開始・終了手順の詳細。セッション再開時の状態復元、終了時の両リポジトリのコミット・push・整合確認。セッションをまたぐ作業の引き継ぎに参照する。
---

# セッション開始・終了手順

## セッション開始（再開）手順

1. `03-worklog/session-context.md` を読む:
   - Last Checkpoint / Current Status / Next Actions / Blockers
   - **Decision Queue**（保留中のユーザー判断があれば最初に報告する）
   - **Verification Queue**（未検証の修正があれば検証から始める）
   - リポジトリ同期状態テーブル（未pushがあれば報告）
2. `tail -80 03-worklog/worklog.md` で直近の作業を確認する
3. テスト環境をセットアップする（`02-test/test-procedures.md`「前提条件」。
   デーモン・環境変数等は揮発しているため毎回必要）
4. `./verify.sh` で「壊れていないこと」を確認してから作業を再開する
5. 中断されたサブタスクがあれば、そのディレクトリの plan.md / investigation.md を読んで継続する
6. 作業ツリーが dirty なら継続前に分類する: session-context の `This turn` 宣言と作業ツリー台帳を
   `git log` と突き合わせ、各変更を diagnostic（revert）/ candidate-fix（未検証扱いで再検証）に分ける。
   記録が皆無なら diff から意図を復元して記録してから進む

## セッション終了チェックリスト（Tier 1・非同期レビューゾーン — 指示を待たず実行）

**2リポジトリ運用では片方だけのコミット・pushは未完了とみなす。**

1. `03-worklog/worklog.md` に本日分のエントリがあることを確認（なければ追記）
2. `03-worklog/session-context.md` を更新:
   - Last Checkpoint（日時・両リポジトリのgit ref・Phase/Step）
   - Current Status / Next Actions / 再開手順
   - Decision Queue / Verification Queue
   - リポジトリ同期状態テーブル
3. **migration（記録系）リポジトリ**: `git status` がクリーンになるまでコミット
4. **実装ツリー**: 検証済みの変更をコミット
   （未検証の変更は Verification Queue に記録して退避）
5. **リモートが設定されている場合は両リポジトリを push**。
   リモート未設定の場合はその旨を session-context.md に明記する
6. 最後に両リポジトリの `git log --oneline -1` と `git status --short` を表示して整合を報告する
   （`./verify.sh repo-sync` で両リポジトリの未コミットゼロを機械確認する）
7. 未処理の Decision Queue があれば終了報告で明示する

## リポジトリ同期状態テーブル（session-context.md 内）

| リポジトリ | 最新コミット | 未コミット変更 | リモート | push状態 |
|-----------|-------------|--------------|---------|---------|
| migration | <sha> | なし/あり(<内容>) | <remote or 未設定> | ✅ pushed / ⚠️ 未push |
| 実装ツリー | <sha> | なし/あり(<内容>) | <remote or 未設定> | ✅ pushed / ⚠️ 未push |
