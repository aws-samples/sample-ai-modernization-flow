# 新しい移行ドメインへの適用（Playbookの作成）

新しい移行ドメインに対応するときは、Playbookを1つ追加するだけでよい。
Method層（`method/`）とHarness層（`harness/`）は変更しない。

---

## Playbook層とは何か（作る前に読む）

Playbookは、そのドメインでしか通用しない知見を置く場所である。
汎用側（Method / Harness）にドメイン固有の目印を書くと、その目印を使わない対象では手順が機能しなくなる。

PlaybookとMethod / Harnessのどちらに書くかは、次の表を基準に判断する。

| Playbookに書くもの | Method / Harnessに書くもの |
|-------------------|-------------------------|
| `mvn clean install -DskipTests`のような具体的なビルドコマンド | 「検証コマンドはテストコードのコンパイルを含む」という原則 |
| `struts.allowlist.packageNames`のような設定キー | 「セキュリティ既定値の変更はサイレント障害を生む」という原則 |
| `#if 0` / `UnsupportedOperationException`のような禁止パターン | 「意図せぬスタブ化を機械検知する」という仕組み |
| SolarisとLinuxのAPI差分表 | 「環境差異テーブルを作る」という手順 |
| 「この型に替えると検証属性がサイレント障害として失効する」という経路固有の罠 | 「ビルドが沈黙する／誤誘導する観点を持つ」という原則（CP-11） |

汎用側には具体名を書かない。別のフレームワークでは、特定のアノテーション名を汎用の手順書に書いた事例が実際にある。
その結果、そのアノテーションを使わない対象では網羅性の分母がゼロになり、突合の計算ができなくなった。

## 作成手順

### 1. ディレクトリを作る

Playbookのディレクトリを作り、既存のPlaybookと同じ構成にする。
置き場所は任意で、`install.sh --playbook <path>`で指定できる。フレームワーク本体に取り込む場合は`ja/playbooks/<new-domain>/`に置く。
ドメイン名は、移行元と移行先が分かる形にする（例: `clang-solarisx86-to-amznlinux`、`java-modernization`）。

| ファイル | 内容 | 必須 |
|---------|------|------|
| `README.md` | ドメイン概要と構成 | 必須 |
| `practices.md` | 知見集（`DP-N`。サマリ表が空でよい） | 必須 |
| `analysis-appendix.md` | 観点表（移行対応台帳の網羅の基準の供給元。下記「観点表の書き方」）+ changelog調査の勘所 | 必須 |
| `baseline-themes.md` | このドメインで不具合が起きやすい振る舞いのテストパターン | 必須 |
| `verify-snippets.md` | 各ゲートの言語別実装例、禁止パターン定義、golden-path E2Eの例 | 必須 |
| `modernized-gitignore.template` | ビルド成果物のignoreパターン（例: Javaなら`target/`, `*.class`） | 必須 |
| `transform-config-cca-template.yaml` | 構造分析（`AWS/comprehensive-codebase-analysis`）の設定 | 必須 |
| `reference/` | ドメイン知見（差分一覧、考慮事項） | 任意 |

### 2. transform-configを書く

`additionalPlanContext`はATXの上限である4096バイト以内に収める。上限を超えると分析を実行できない。
書いたら必ず、次のコマンドでバイト数を確認する。

```bash
python3 -c "
import yaml
c = yaml.safe_load(open('<playbook-dir>/transform-config-cca-template.yaml'))['additionalPlanContext']
print(len(c.encode()), 'bytes')"
```

設定は、移行先が未定でも分析できる内容にする。目標欄が空のときは、ATXに目標を仮定させない。
代わりに、現行スタックの棚卸しと、実行可能な移行先候補の列挙（LTS・破壊的変更の規模・互換連鎖）を追加で報告させる観点を入れる。
移行方針は、Phase 0bでユーザーがADRとして決める。

日本語版が4096バイトに収まらない場合は、表現を短くする。既存のclang Playbookは、略記スタイルで3990バイトに収めている。

### 3. verify-snippetsを書く

`verify-snippets.md`には、`verify.sh`の各ゲートをこのドメインで実装するときのスニペットを置く。最低限、次のスニペットを用意する。

- buildゲートの期待成果物の例（実行ファイル / `.so` / `.jar` / `.war`など）
- smokeゲートの実装例（CLIなら`--help`がrc=0、デーモンなら数秒生存、サーバならポート応答）
- integrationゲートの実装例
- 禁止パターンの定義（`FORBIDDEN_PATTERNS`と`FORBIDDEN_SCAN_PATHS`）
- golden-path E2E（UI描画型なら`REQUIRE_GOLDEN_PATH=1`を推奨）
- 複数リポジトリ構成での`MODERNIZED_TREES`と`DIAG_SCAN_PATHS`の例

禁止パターンには、誤検知についての注意も書いておく。たとえば`mock`はテストコードでは正当な記述なので、走査対象を実装ソースに限定する必要がある。

### 4. practices.mdの採番

無印の`DP-N`はPlaybookの作者が採番する。プロジェクトは`DP-<project>-N`を使う。
新規のPlaybookでは`DP-1`から始める。1つのプロジェクトに入るPlaybookは1つだけなので、`DP-N`の番号は他のPlaybookと重複してよい。

サマリ表は空のまま始めてよく、作業しながら追記する。
量の上限（サマリ1行300バイト / 本文80行 / エントリ15件）は、`./verify.sh knowledge`が検査する。

### 5. 本体に取り込む場合: i18nに登録して英語版を作る

自分用のPlaybookでは、この手順は不要である。フレームワーク本体に取り込む場合にだけ行う。
翻訳は保守者が担当する（[CONTRIBUTING.md](../../CONTRIBUTING.md)を参照）。

翻訳元の原本は`ja/`で、`en/`は`ja/`から生成する。新規のファイルは必ずマニフェストに登録する。

```bash
# tools/i18n-manifest.tsv に1ファイル1行を追加
# 書式: <ja/からの相対パス> <TAB> <リポジトリルートからのターゲット> <TAB> class <TAB> flags
#   class: translate（全文翻訳）/ translate-comments（コメントのみ）/ copy（そのままコピー）
```

登録したら、次のコマンドを実行する。

```bash
./tools/check-i18n.sh          # 何が未同期か分かる
./tools/build-en.sh            # 翻訳すべきファイルと用語辞書を表示
# → en/ 側を作成（AIエージェントに任せてよい）
./tools/build-en.sh --stamp playbooks/<new-domain>/practices.md
./tools/check-i18n.sh          # PASS を確認
```

`ja/`と`en/`は同時に編集する。`ja/`だけを更新すると、`install.sh --lang en`で設置される内容と手順書が食い違う。
また、共有アンカー（`CP-N` / `DP-N` / `HOLD-N`）が日英で1対1に対応しているかの検査もFAILする。

用語の表記は`tools/glossary.tsv`で統一する。新しい用語を導入したら、このファイルに追加する。

### 6. 使う

```bash
./sample-ai-modernization-flow/install.sh --project myapp --playbook <new-domain>      # 本体の playbooks/ にある場合
./sample-ai-modernization-flow/install.sh --project myapp --playbook /path/to/playbook  # 任意の場所に置いた場合
```

## 観点表の書き方（`analysis-appendix.md`）

観点表は、Playbookの中で最も価値の高い成果物である。移行対応台帳の網羅の基準は観点表から採用される（CP-11）。
`install.sh`は観点表を`00-analysis/analysis-appendix.md`としてプロジェクトに設置する。

### 観点表に載せる2種類の観点

| 種類 | ツールチェーンの反応 | 観点表に載せるか |
|------|-------------------|-----------------|
| ① 強制する | ビルドが失敗し、直すべき場所を列挙する | 載せない（網羅の基準に採用しない。ビルドが数秒で同じ一覧を出す） |
| ② 沈黙する | ビルドは成功し、実行時か本番環境でだけ不具合が起きる | 載せる |
| ③ 誤誘導する | ビルドは失敗するが、素直に修正すると別の箇所で不具合が起きる | 最優先で載せる |

①を網羅の基準に採用すると、該当がゼロの行で台帳の行数だけが増え、網羅できたと誤解しやすくなる。
名前空間の置換、プロジェクトファイル形式の変更、APIのリネームは①に当たる。
分析の参考として①の行を残してもよいが、その場合は`種類`欄に①と書き、網羅の基準から除く。

③は最も価値が高い。修正した本人はビルドの成功を根拠に完了と判断するので、観点表に書かれていなければ誰も問題に気づかない。
③の典型は次の3つである。

- 型を差し替えると`is`/`instanceof`相当のパターンに一致しなくなり、既定値を返す分岐に入る
- 旧フレームワーク専用の型を使う登録処理は、ファイルごと削除すればビルドが通る。ただし削除によって、認可・監査・トランザクション境界などの横断的関心事も失われる
- 旧APIに等価な代替がなく、素直な代替手段が破壊的である（データを消す、スキーマを作り直すなど）

### 表の書式（検出コマンドは必須）

```markdown
| ID | 観点 | 種類 | 検出コマンド | 参照 |
|----|------|------|------------|------|
| MP-1 | <一行で言い切る> | ③ | `<再実行可能な1コマンド>` | DP-3, reference/xxx.md §2 |
```

`ID`列には`MP-N`（Migration Perspective）を書く。移行対応台帳の行はこのIDを参照するので、番号は振り直さない。
`種類`列には①/②/③を書く。網羅の基準に採用するのは②と③である。
`参照`列には、根拠となる`reference/`の節と、対処を書いた`practices.md`の`DP-N`を書く。本文は複製しない。

`検出コマンド`列は、②と③では必須である。説明文だけでは、該当箇所の全量を洗い出せないからである。
たとえば「移行先は大文字小文字を区別する」と知っていても、検出器がなければ参照パスの不一致は常に0件と報告される。
その状態では、作業を進めても不一致は見つからない。

「正しいと言える観測」（CP-4）と否定テスト（CP-13）はコードを含むので、表には入れず`verify-snippets.md`に置く。
観点1件につき、ゲートの実装例と否定テストの手順を1つずつ用意する。
実行時にだけ不具合が起き、テストで検出する観点は`baseline-themes.md`に置く。

### 観点表は案件をまたいで育てる

案件の中で新しく見つかった観点は、その案件の記録だけで終わらせず、必ず観点表へ戻す。
観点は移行経路ごとに固定された資産なので、案件を重ねるほど蓄積される。
走査のヒット数を網羅の基準にする方式では、このような蓄積はできない（CP-11「なぜ走査ヒット数を網羅の基準にしないか」）。

## 既存のPlaybookを更新する

Playbookは、案件を重ねながら育てるものである。
更新のきっかけは2つある。1つは、案件で新しく見つかった観点や知見を戻すとき。もう1つは、移行先の新版への対応などでPlaybook自体を改訂するときである。

### 追加する内容と追加先

| 得たもの | 追加先 |
|---------|-------|
| 新しく見つかった観点（ビルドが沈黙する／誤誘導する箇所） | `analysis-appendix.md`の観点表に`MP-N`を追加 |
| 対処の定型パターン | `practices.md`に`DP-N`を追加 |
| 観点の検出器と否定テスト | `verify-snippets.md` |
| 実行時にだけ不具合が起きる振る舞いのテストパターン | `baseline-themes.md` |
| 差分一覧などの根拠 | `reference/` |

`MP-N`と`DP-N`は振り直さない。台帳やADRから参照されているので、不要になった番号は欠番として残す。
ツールの改善によって観点が①に変わった場合は、行を消さずに`種類`を①に変える。
プロジェクトの`DP-<project>-N`を取り込むときは、無印の番号を新たに振り、出所を本文に書く。
エントリが上限の15件を超えたら、統合を検討する。transform-configを変更したら、4096バイト以内に収まっているかを再確認する。

### 稼働中のプロジェクトへ反映する

```bash
./sample-ai-modernization-flow/install.sh --update-project <記録リポジトリ> --playbook <name|path>
```

`practices.md`・`analysis-appendix.md`・`baseline-themes.md`・`verify-snippets.md`は、プロジェクト側でも追記するので上書きされない。
これらの新版は`.flow-update-<version>/`に置かれるので、手でマージしてから`.flow-update-<version>/`を削除する。
`reference/`・transform-config・gitignoreテンプレートは上書きされる。
`--playbook`を省略すると、Playbookのファイルは更新されない。

## Playbookを作らない判断（重要）

既存のPlaybookで足りる場合は、新しいPlaybookを作らない。判断の目安は次の表のとおりである。

| 状況 | 判断 |
|------|------|
| 同じ言語・同じフレームワーク世代の別プロダクト | 既存Playbookを使う。得た知見は既存の`practices.md`に追記する |
| 同じ言語だが移行の性質が違う（例: 版上げ vs 別FWへの置換） | 既存Playbookに`DP-N`を追加して様子を見る。知見が明確に分かれてきたら分割する |
| 言語・実行基盤が違う | 新規作成する |

Playbookを指定しなくても、フレームワークは動作する。`--playbook`を省略した場合、`playbooks/`にPlaybookが1つしかなければ自動で選択される。
現在は複数のPlaybookがあるので、使う場合は`--playbook`で指定する。
ドメイン知見がなくても、MethodとHarnessだけで移行は進められる。
ただし分析観点と検証の実装例が少なくなるので、得た知見はその都度`practices.md`に追加していく。

## 参照

- 3階層と再利用境界: [for-engineers.md](for-engineers.md)
- 既存Playbook: `../playbooks/clang-solarisx86-to-amznlinux/`, `../playbooks/java-modernization/`, `../playbooks/dotnetfw-to-modern-dotnet/`
