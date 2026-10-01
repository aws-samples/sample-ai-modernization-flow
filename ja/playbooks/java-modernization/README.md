# Playbook: Java モダナイゼーション

レガシーJavaアプリケーション（Java 8/11、javax名前空間、旧世代フレームワーク）を
モダンスタック（Java 21 LTS、Jakarta EE、現行フレームワーク）へ移行するための
**Playbook（中位・実務文書層）**。

> フロー（Phase 0-4）・3つの終了点・利用者判断項目は `../../method/flow.md`、
> AI実行規律は `../../harness/` を参照。セットアップはリポジトリルートの `install.sh`。

## このドメインの特徴（clang-solarisx86-to-amznlinux Playbook との違い）

- **サイレント障害が主要な失敗モード**: フレームワークのセキュリティ強化デフォルトにより、
  例外なく「空になる・不発になる」障害が多い（コンパイル・ユニットテストでは検出不能。
  E2Eテストが必須）
- **既存テスト資産が存在することが多い**: baseline はモードC（既存テストを流用。既存ユニット/E2Eテストの
  モダナイズ）が第一候補。テスト基盤自体の移行を work-plan に計上する

## 構成

| ファイル | 内容 | プロジェクトへのコピー先 |
|---------|------|------------------------|
| `practices.md` | Javaドメインのプラクティス集（DP-1〜） | `docs/knowledge/practices.md` |
| `analysis-appendix.md` | ドメイン固有の分析観点（EOL/互換マトリクス、名前空間影響数） | `00-analysis/analysis-appendix.md` |
| `baseline-themes.md` | このドメインで壊れやすい振る舞いのテストパターン（サイレント障害、CSRF等） | `02-test/baseline-themes.md` |
| `verify-snippets.md` | verify.sh 各ゲートのJava/Maven向け実装例 | `02-test/verify-snippets.md` |
| `modernized-gitignore.template` | ビルド成果物のignore（target/, *.class等） | 記録リポジトリのルート |
| `transform-config-cca-template.yaml` | AWS Transform custom (ATX) の構造分析（CCA）の設定 | `00-analysis/transform-config-cca-template.yaml`（0a-4 でこれを元に `00-analysis/<repo-id>/transform-config-cca.yaml` を作る） |
| `reference/java-modernization-considerations.md` | フレームワーク移行の考慮事項集 | `docs/reference/` |

## クイックスタート

```bash
cd /path/to/workspace
/path/to/sample-ai-modernization-flow/install.sh --project <product-version> \
    --playbook java-modernization
```

## このドメインの特徴的な論点

- **多段メジャージャンプ**: Struts 2.5→7.1 のような移行はバージョン境界ごとに公式ガイドが
  複数存在する（CP-9）。破壊的変更の事前抽出が最重要
- **javax → jakarta 名前空間移行**: 影響ファイル数を事前に定量化（analysis-appendix参照）
- **セキュリティデフォルト変更のサイレント障害**: OGNLアローリスト、パラメータバインド必須
  アノテーション、CSRF等（DP-2, baseline-themes参照）
- **検証コマンドは test-compile を含める**: `mvn clean install -DskipTests`（DP-1）
- **UI フレームワーク移行**（Bootstrap等メジャー更新を伴う場合）: モーダル・レイアウト・
  生成要素IDの変化は E2E でのみ検出可能

## 指示に含めるべき情報

| 項目 | 例 |
|------|---|
| ソースコードのパス | `/path/to/<product>/` |
| 現行スタック（例） | Java 8/11, Struts 2.x, Spring Framework 5.x, javax名前空間, Bootstrap 3/4 |
| 目標スタック（例） | Java 17/21 LTS, Struts 6.x/7.x, Spring Framework 6.x, Jakarta EE 10, Bootstrap 5 |
| ビルドコマンド | `mvn clean install -DskipTests`（JAVA_HOMEの指定を含む） |
| テスト実行方法 | `mvn test` / E2Eモジュールの有無（例: `mvn verify -pl it-selenium`） |
| 制約（あれば） | 削除してよいレガシー機能（例: XML-RPC）、維持すべきプロトコル |

## 実施例（公開サンプルでの実測）

- 公開サンプル（OSSのApache Roller。ブログサーバ）での実測（Java 11→21, Struts 2.x→7.x, Bootstrap 3→5, Spring Security CSRF導入）:
  フロー適用前の実施。本Playbookの
  プラクティスとテーマ集はこの実測の lessons-learned から抽出された
