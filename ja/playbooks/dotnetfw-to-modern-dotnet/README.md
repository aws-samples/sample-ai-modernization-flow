# Playbook: .NET Framework → モダン .NET 移行

.NET Framework（4.x 系）で稼働するアプリケーション（ASP.NET MVC 5 / OWIN / EF6 / IIS ホスト）を
モダン .NET（クロスプラットフォーム、Linux 実行可能）へ移行するための
**Playbook（中位・実務文書層）**。

> フロー（Phase 0-4）・3つの終了点・利用者判断項目は `../../method/flow.md`、
> AI 実行規律は `../../harness/` を参照。セットアップはリポジトリルートの `install.sh`。

## このドメインの特徴（他 Playbook との違い）

- **ATX は分析（CCA）にだけ使う。** コード変換は、フロー共通の方針どおりエージェントが直接修正で行う。
  ATX の作業は分析系ジョブを長時間走らせることが中心になるので、中断と再開の扱いは DP-2 に従う
- **既存テスト資産が無いことが多い。** baseline は**モードB（コード読解で定義）**が
  第一候補になる。その際 **`.cs` だけでなく `.cshtml` と `.config` を網羅の基準に含める**
  （実測で落として踏んだ。`baseline-themes.md`）
- **サイレント障害が主要な失敗モード。** 型の差し替えで検証属性が無効化される、既定値の変更で
  データがサイレント障害として欠落する、といった「ビルド緑・例外なし・結果が違う」障害が中心である。
  **観点表 26件のうち③（素直な修正が別の何かを壊す）が8件**を占める
- **移行元をビルドできないことがある。** 作業ホストが macOS / Linux だと .NET Framework の
  MSBuild が動かず、**移行元のツールチェーン警告が原理的に取れない**。
  移行対応台帳の供給源が1本減ることを前提に計画する（`analysis-appendix.md`「分析入力」）
- **移行先の版が速く腐る。** .NET は毎年11月に版が切り替わり LTS でも3年で切れる。
  自動分析や LLM の推奨と作業時点の最適が容易に1〜2世代ずれる（DP-1）

## 構成

| ファイル | 内容 | プロジェクトへのコピー先 |
|---------|------|------------------------|
| `practices.md` | .NET ドメインのプラクティス集（`DP-1`〜`DP-9`） | `docs/knowledge/practices.md` |
| `analysis-appendix.md` | **観点表（`MP-1`〜`MP-26`。節F はデプロイ経路・設定注入）**。移行対応台帳の網羅の基準の供給元 | `00-analysis/analysis-appendix.md` |
| `baseline-themes.md` | 壊れやすい振る舞いのテストパターン（15テーマ） | `02-test/baseline-themes.md` |
| `verify-snippets.md` | `verify.sh` 各ゲートの .NET 向け実装例 + **否定テスト手順** + 禁止パターン | `02-test/verify-snippets.md` |
| `modernized-gitignore.template` | ビルド成果物の ignore（`bin/` `obj/` 等） | 記録リポジトリ直下（`setup-modernized.sh` が読み、実装ツリーの `.gitignore` に適用する） |
| `transform-config-cca-template.yaml` | AWS Transform custom (ATX) の構造分析（CCA）の設定 | `00-analysis/transform-config-cca-template.yaml`（Phase 0a-4 でリポジトリごとに `00-analysis/<repo-id>/transform-config-cca.yaml` として実体化する） |
| `reference/runtime-generation-differences.md` | **一次情報つき差異カタログ**（NLS→ICU / EF6→EF Core / 差異が無かった項目） | `docs/reference/` |
| `reference/compat-switches.md` | 互換スイッチ一覧と読み方 | `docs/reference/` |

## クイックスタート

```bash
cd /path/to/workspace
/path/to/sample-ai-modernization-flow/install.sh --project <product-version> \
    --playbook dotnetfw-to-modern-dotnet
```

## このドメインの特徴的な論点

- **「現行と同値」を成功基準にできない箇所がある。** MVC 5 に残る `asp-*` 属性は不発であり、
  移行で有効化されて**壊れていた機能が動き出す**。等価性を機械適用すると
  「壊れたままの再現」が正解になってしまう → 箇所ごとに期待動作を定める ADR が必要（DP-3 / MP-3）
- **型の差し替えで検証がサイレント障害として無効になる。** `HttpPostedFileBase` → `IFormFile` の定型置換で
  カスタム検証属性が全部通るようになる。**静的検査では「実際に拒否される」を言えない**
  → runtime negative test を同じ Step で入れる（DP-6 / MP-2）
- **NLS → ICU はランタイム世代差であって OS 差ではない。** 「Windows なら安全」は誤りで、
  Windows 上で .NET Framework から上げるだけの案件でも文字列比較・ソート順の結果が変わる
  （`reference/runtime-generation-differences.md` §2）
- **EF6 → EF Core は既定値の変更が最も危険。** 遅延読み込みが既定 OFF になるため、
  `Include` 漏れが**例外なく `null` / 空コレクション**になる（`reference/` §4-1）
- **静的ファイルは2つの理由で 404 になる。** `wwwroot` 不使用構成の `UseStaticFiles` 既定（MP-7）と、
  Linux の大文字小文字区別（MP-9）。**後者の検出器は FS に問い合わせてはならない**（CP-12）
- **一次情報で確認したら差異が無かった項目も記録する。** タイムゾーン ID の非互換や
  `decimal` の丸め変更は**通説であって事実ではない**。「無い」ことの再調査コストは
  「有る」より高いので実値として残す（`reference/` §5）

## 指示に含めるべき情報

| 項目 | 例 |
|------|---|
| ソースコードのパス | `/path/to/<product>/` |
| 現行スタック（例） | .NET Framework 4.8, ASP.NET MVC 5, OWIN self-host, EF6, Autofac + FW 統合パッケージ |
| 目標スタック | **未定でよい**（Phase 0b で ADR として決める。`transform-config` にも書かない） |
| ターゲット OS / 実行基盤 | 例: Amazon Linux（実行基盤 EC2/ECS/Lambda は未定でよい） |
| ビルドコマンド | `dotnet build <Solution>.sln -c Release`（**移行元のビルド可否も併記する**） |
| テスト実行方法 | 既存テストの有無。無ければ baseline モードB（コード読解で定義）を選ぶ |
| 制約（あれば） | DB スキーマを変更してよいか / 削除してよいレガシー機能 / 対象アーキテクチャ（x64 / arm64） |

## 実施例（公開サンプルでの実測）

- **ASP.NET MVC 5 + EF6 + OWIN / .NET Framework 4.8 → .NET 10 on Linux コンテナ**
  （Web / Data / Domain / Common / IaC の5プロジェクト、約 8,400 行、テスト資産ゼロ、
  現行稼働環境なし、作業ホスト macOS）。対象は AWS の公開サンプルアプリ Bob's Used Bookstore である。
  本 Playbook の観点表・プラクティス・差異カタログは、この公開サンプルでの実測（移行対応台帳・
  ADR・lessons-learned）から抽出された。
  実測: 台帳41行のうち**約24行はビルドが列挙する項目**で、TFM 切り替え後に未対応は 41→9 に落ち、
  **残った9行は全部②③（ビルドが沈黙する / 誤誘導する）**だった。
