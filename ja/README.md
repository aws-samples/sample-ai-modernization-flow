# AI Modernization Flow

**Version 0.11.0**（[CHANGELOG](../CHANGELOG.md)）

AI Modernization Flowは、レガシーシステムの移行とモダナイゼーションを、AIエージェントに規律を守らせて進めるためのワークフローである。
移行の型（Method）を、ドメイン知見（Playbook）とAI実行規律（Harness）によって実行できる形にしている。

このリポジトリでは日本語版を原本とする。英語版（`en/`とルートの`README.md`）は日本語版から生成する。

---

## ドキュメント

| 読みたいこと | ドキュメント |
|------------|------------|
| まず何ができるのか（IT部門・非エンジニア向け） | [docs/overview-for-business.md](docs/overview-for-business.md) |
| なぜこの形なのか（考え方・設計思想） | [docs/concepts.md](docs/concepts.md) |
| どのように使うのか（実際に起きること・困ったときの読み替え） | [docs/how-to-use.md](docs/how-to-use.md) |
| 内部設計（3階層・知見体系・ゲートの実装） | [docs/for-engineers.md](docs/for-engineers.md) |
| 新しい移行ドメインを追加したい | [docs/authoring-playbook.md](docs/authoring-playbook.md) |
| フローの正式定義（Phase 0-4・3つの終了点・利用者が判断する項目） | [method/flow.md](method/flow.md) |
| ハーネスの構成・設置内容・ツール対応 | [harness/README.md](harness/README.md) |
| ドメイン固有の知見・観点 | `playbooks/<domain>/README.md` |

## クイックスタート

ワークスペースルート（対象ソースを置く親ディレクトリ）で、次のコマンドを実行する。

```bash
cd /path/to/workspace
git clone https://github.com/aws-samples/sample-ai-modernization-flow.git
./sample-ai-modernization-flow/install.sh --project myapp-1.0 \
    --playbook java-modernization
```

| オプション | 内容 |
|-----------|------|
| `--project <name>` | `<name>-migration-<YYYYMMDD>/`を雛形から生成し、`git init`する |
| `--lang ja\|en` | 設置するルールと雛形の言語（既定は`ja`） |
| `--tool kiro\|claude-code\|both` | ルールの設置先（既定は`both`） |
| `--playbook <name\|path>` | Playbook層をコピーする。`playbooks/`配下の名前かパスで指定する。Playbookが1つしかなければ省略できる |
| `--skip-project` | 記録リポジトリを作らず、ルールだけを設置または更新する（ハーネスの更新時に使う） |
| `--update-project <dir>` | 稼働中の記録リポジトリに、新しい版の雛形とPlaybookを反映する |
| `--no-turn-log` / `--no-work-guard` | ターン時刻の記録と、着手時の宣言の強制を無効にする（どちらも既定で有効） |

設置が終わったら、ワークスペースルートでAIエージェントを起動する。対象ソースのパスを渡し、「アセスメントを開始します。Phase 0aから始めてください」と指示する。

Kiroは次のコマンドで起動する。`--agent migration`を付けずに起動すると、ターン時刻が記録されない。

```bash
cd /path/to/workspace && kiro-cli chat --agent migration
```

`<PLACEHOLDER>`を手で埋める必要はない。エージェントは起動インタビューで対象ソースを走査して値を埋め、埋められなかった項目だけをまとめて質問する。
移行先スタックは未定でよく、Phase 0bで分析結果を見てから決める。指示文の全パターンは[harness/README.md](harness/README.md)を参照。

アセスメントだけで終えることもできる。Phase 0aの完了時点（分析結果）か、Phase 0bの完了時点（移行判断の材料）で止められる。
詳細は[docs/how-to-use.md](docs/how-to-use.md)を参照。

## 構成（3階層）

| 階層 | 呼称 | 場所 | 再利用範囲 |
|------|------|------|-----------|
| 上位（汎用） | Method（移行方法論） | `method/` | 型そのもの。ドメイン・ツール非依存 |
| 中位（実務文書） | Playbook | `playbooks/<domain>/` | 移行ドメイン固有 |
| 下位（AI実行規律） | Harness | `harness/` | 全ドメイン共通 |

新しい移行ドメインに適用するときは、MethodとHarnessをそのまま使い、Playbookだけを追加する（[docs/authoring-playbook.md](docs/authoring-playbook.md)）。

```
sample-ai-modernization-flow/
├── README.md       # 英語（ja/README.md からの生成物。GitHubでの入口）
├── VERSION         # 版の原本
├── CHANGELOG.md
├── install.sh      # ワークスペースへの設置スクリプト
├── ja/             # 日本語（原本。編集はこちらだけ）
│   ├── docs/       #   利用者向け解説
│   ├── method/     #   Method（フロー・分析手順・共通プラクティス CP-N）
│   ├── harness/    #   Harness（コア規律・skills・雛形・検証ゲート雛形）
│   └── playbooks/  #   Playbook（ドメイン固有。practices.md は DP-N）
├── en/             # 英語（生成物。直接編集しない。ja/ と同一構造）
└── tools/          # 翻訳同期ツール（i18n-manifest.tsv / glossary.tsv / i18n.lock / build-en.sh / check-i18n.sh）
```

## 設計原則

1. 実行規律のラダー: 常時ロードする規律は最小限にする。詳細はオンデマンドで読むskillsに移し、強制が必要な規則はツールに依存しない`verify.sh`とgitで検査する
2. Constraints > Prompts: 散文で書いたルールは、エージェントの自己申告だけで通過してしまう。守らせたいことは実行スクリプトで検査する
3. 完了基準は証拠: 各工程の完了は、テストと観測結果の蓄積で判定する。文書の承認だけでは完了としない
4. コピー方式の配布: エージェントはワークスペースルートで起動する。ルールは`.kiro/`などへコピーして設置する
5. No duplication: ツール別のファイル（`CLAUDE.md`など）と英語版は、ソースから生成する

背景と根拠は[docs/concepts.md](docs/concepts.md)を参照。

## 言語構成

| ツリー | 位置づけ | 編集 |
|--------|---------|------|
| `ja/` | 原本（source of truth） | ここだけを編集する |
| `en/`とルートの`README.md` | 生成物 | 直接編集しない（直接編集すると`tools/check-i18n.sh`が検出する） |
| `install.sh` | 言語に依存しない1ファイル | ソース（コメント・コード）と実行時の出力は英語である。設置後の案内（next steps）だけが`--lang`に従う。例外は、利用者に操作を促す2つのエラーメッセージである |
| `VERSION`, `CHANGELOG.md`, `LICENSE`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` | 言語に依存しない | 英語のまま維持する |

`CP-N` / `DP-N` / `HOLD-N` / `Tier` / `Phase` / `Mode A-C`は翻訳しない。これらは両言語で共通のアンカーとして使う。
訳語は`tools/glossary.tsv`で統一する。

```bash
# 1. 日本語（原本）と英語を同時に編集する
vi ja/method/flow.md en/method/flow.md
# 2. 同期状態を記録して検証
./tools/build-en.sh --stamp method/flow.md
./tools/check-i18n.sh          # → PASS
```

`ja/`だけを更新したままにしてはならない。`tools/i18n.lock`には生成時の`ja/`と`en/`のハッシュが記録されている。
片側だけを変更すると、`check-i18n.sh`がハッシュの不一致としてFAILを返す。

`en/`は生成物だが、lockfileと同じようにコミットする。外部の利用者がclone直後に`install.sh --lang en`を実行できるようにするためである。

### 外部からのコントリビューション

`en/`は生成物なので、`en/`への変更をそのままマージすることはできない。
変更の提案は、Issueか`en/`へのPRで受け付ける。PRは内容の提案として扱い、メンテナが`ja/`に反映してから`en/`を再生成する。
翻訳の追随はメンテナが担当するので、PRに翻訳の更新は求めない。詳細は`CONTRIBUTING.md`を参照。

## セキュリティ

詳細は[CONTRIBUTING](../CONTRIBUTING.md#security-issue-notifications)を参照。

## ライセンス

このリポジトリはMIT-0ライセンスで提供する。[LICENSE](../LICENSE)を参照。
