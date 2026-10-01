---
name: migration-recording
description: 移行プロジェクトの記録フォーマット詳細。worklogエントリ、gitコミットメッセージ、知見（PB/LL/ADR）の追記ルール。作業記録・コミット・知見追記を行うときに参照する。
---

# 記録フォーマット詳細

## gitコミットメッセージ

```
[Step X] X-N: <要約>

理由: <なぜこの修正が必要か>
検証: <何を観測したか>
Ref: work-plan.md §Step X, DP-<N>
```

- コードは 実装ツリー、記録は migration リポジトリでコミットする（2リポジトリ運用）
- サブタスクの場合は `[subtask/<taskname>]` プレフィックスを使う

## worklog追記（03-worklog/worklog.md）

- 各エントリ: 日時（YYYY-MM-DD HH:MM）・Phase/Step・実施内容・結果（成功/失敗 + 観測事実）・コミットハッシュ
- **並び順: 古いエントリが先頭、新しいエントリを末尾に追記する（時系列順）**
- トラブルシュートを含む場合は仮説ログ表を含める（skills/migration-troubleshooting）

### ターン時刻表の転記（`--turn-log` 有効時のみ）

**契機: worklog エントリを1つ書くたび**に `./03-worklog/turn-report.sh --worklog` を実行し、
出力をそのエントリに貼る（範囲は機械が決めるので人は覚えなくてよい）。
**生ログは git-ignored であり、貼った表だけが恒久記録である。**

## 知見の蓄積（4ファイル）

| ファイル | 形式 | 内容 |
|---------|------|------|
| `docs/knowledge/practices-common.md` | `CP-<project>-N` | 共通知見（ドメイン・言語を問わず使える） |
| `docs/knowledge/practices.md` | `DP-<project>-N` | ドメイン知見（同ドメインの他プロジェクトで使える） |
| `docs/knowledge/lessons-learned.md` | LL-N | プロジェクト固有の技術的教訓 |
| `docs/decisions/decisions.md` | ADR-N | 設計上の意思決定（判断日・フェーズ・背景・選択肢・決定・理由・影響） |

- プロジェクト完了時、practices-common / practices への追記分はフローのリポジトリ
  （method/practices-common.md / playbooks/<domain>/practices.md）へ還元する

- **無印の `CP-N` / `DP-N` をプロジェクト側で採番してはならない。** プロジェクトでの追記は
  `CP-<project>-N` / `DP-<project>-N` の名前空間を使い、完了時の還元で本体が無印を採番する
  （実際に無印 `DP-5` を採番して本体と衝突した事故がある。詳細: practices-common.md「採番の権限」）

- **採用した知見だけでなく、試して棄却した選択肢とその理由も記録する**（同じ失敗ルートの再走を防ぐ）
- lessons-learned には ADR への参照のみ残す（本文は decisions.md）
- 過去の ADR は変更しない（追記専用）。覆す場合は新規 ADR で `Supersedes: ADR-N` と参照する

### 棚卸しのタイミング（LL/DP化）

worklogへの詳細記録だけでは知見の抽象化は起きない。以下のタイミングで必ず
「今回の区間で得た教訓をlessons-learned.md / practices.mdに反映すべきか」を確認する
（棚卸しの実施自体はTier 1、指示不要）:
- Phase/Step完了時（次の作業に進む前に）
- サブタスク完了時（results.md作成と同じタイミング）
- Tier 2（HOLD）トリガー対応完了時（ADR確定、除外決定等の直後）

「該当なし」も明示的な判定として扱う（暗黙スキップしない）。完了報告に一行
「LL/DP棚卸し: 追記N件 / 該当なし」を含める。

### 統合・削除は機械的に強制する

**上記の棚卸しは「追記」しか生まない。** 実際、Phaseゲートごとに棚卸し提案は出たのに
統合・削除が一度も実行されなかった実例がある。そこで削減側は
`./verify.sh knowledge` が機械的に発火させる:

- 1ファイルのエントリ数が上限（既定15件）を超えたら **FAIL**
- 統合しない判断をする場合は、当該ファイル冒頭に理由を記録すれば通る:
  `<!-- KNOWLEDGE-REVIEWED: YYYY-MM-DD (N entries, consolidation deferred: <理由>) -->`
- 1エントリの本文が上限（既定80行）を超えたら、詳細を `docs/reference/` へ分離する

**記録なき超過だけを弾く**設計であり、判断そのものは人に残す。

### 追記方法（3ファイル共通）

- いずれも「エントリ追記型」。各ファイル冒頭の「このドキュメントについて」に採番・節構成ルールがある
- 新エントリは本体末尾の `ENTRIES END` マーカー（HTML コメント1行）の**直前**に挿入し、マーカーは移動させない
  （`grep -n '^<!-- ENTRIES END -->$'` で行全体一致の行を探し、その直前に挿入する。ファイル末尾への append はしない）
- サマリ表があるファイル（practices.md）は表にも行を追加する

## 記録不要の例外

- 単純な質問への回答（コード修正・テスト実行を伴わない）
- ユーザーが「記録不要」と明示した場合
