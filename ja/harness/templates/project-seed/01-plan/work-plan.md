# 作業計画

<!-- Phase 2 完了時に analysis-procedure.md の手順に従い作成する -->

<!-- WORK-PLAN-STATUS: DRAFT -->
<!-- ↑ verify.sh がこのマーカーで検証ゲートの適用可否を判定する（機械可読。書式を変えないこと）。
     Phase 2 の Phaseゲート（HOLD-8）で本計画を承認したら CONFIRMED に書き換える。
     CONFIRMED にした時点で build/smoke/integration ゲートが本適用になり、
     期待リストが空のままなら FAIL する（CP-7）。 -->

## 概要

| 項目 | 値 |
|------|---|
| 移行対象 | <PRODUCT_NAME> |
| 移行元 | <SOURCE_OS> (<SOURCE_ARCH>) |
| 移行先 | <TARGET_OS> (<TARGET_ARCH>) |
| 開始日 | YYYY-MM-DD |
| baseline モード | A（旧環境実測） / B（コードリーディング） / C（既存テスト資産） ← Phase 1 (1-2) で確定 |

## 非機能要件のスコープ（Phase 1 (1-3) の判断結果を反映）

| 項目 | 対象/対象外 | ADR | 検証方法（対象の場合） |
|------|-----------|-----|---------------------|
| 性能 | | ADR-N | verify-nonfunc (nonfunc-perf) |
| リソースリーク | | ADR-N | verify-nonfunc (nonfunc-leak) |
| 障害耐性 | | ADR-N | 02-test/integration/ |
| セキュリティ | | ADR-N | |
