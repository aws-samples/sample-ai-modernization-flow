# Harness（エージェントハーネス）

Harnessは、移行・モダナイゼーションプロジェクトでAIエージェントに規律ある作業をさせるための仕組みである。
特定のドメインやツールに依存せず、Tierゲート・仮説ログ・ADR・検証ゲート・セッション管理などの実行規律を提供する。

本文中の`CP-N`と`DP-N`は知見の番号、Tierと`HOLD-N`は停止して利用者の判断を仰ぐトリガーを指す。
詳しくは[使い方](../docs/how-to-use.md)の第4節（記録と知見の置き場所）、第7節（Tier と HOLD）、第11節（用語）を参照。

## 文書体系における位置づけ（3階層）

| 階層 | 呼称 | 実体 |
|------|------|------|
| 上位（汎用） | Method（移行方法論） | `../method/`（flow.md = Phase 0-4 + 3つの終了点 + 利用者判断項目、共通分析手順） |
| 中位（実務文書） | Playbook | `../playbooks/<domain>/`（例: clang-solarisx86-to-amznlinux）。practices.md（DP-N）、分析観点appendix、verify-snippets、reference |
| 下位（AI実行規律） | Harness = 本ディレクトリ | コア行動規律、skills、テンプレート、検証ゲート雛形 |

Javaなど新しい移行ドメインに適用する場合も、本ディレクトリは変更せずにそのまま使う。
新規に作成するのは`../playbooks/`配下のPlaybookだけである。

## 構成

```
harness/
├── core/
│   └── migration-core.md        # 常時ロードされる薄いコア規律（Tierゲート・品質ルール）
├── skills/                      # オンデマンドロードされる詳細手順（SKILL.md形式）
│   ├── migration-recording/     #   記録フォーマット（worklog・コミット・知見追記）
│   ├── migration-subtask/       #   サブタスク手順
│   ├── migration-troubleshooting/ # 仮説ログと根本原因確定（CP-8）
│   ├── migration-adr/           #   ADRドラフト・除外フロー・Phaseゲート定型確認
│   ├── migration-adversarial-review/ # 独立検証（コンテキスト隔離。完了宣言と HOLD-1 の機能除外に限る）
│   ├── migration-verification/  #   検証ゲート運用・テスト記録
│   ├── migration-session/       #   セッション開始/終了手順
│   └── migration-tree-setup/    #   実装ツリー作成・2リポジトリ運用
├── templates/                   # プロジェクト雛形（install.shがコピー）
│   ├── migration-project.md.template  # プロジェクト固有情報（steering/CLAUDE.md用）
│   ├── session-context.md.template
│   ├── baseline-behavior.md.template  # Characterization Test 2モードガイド
│   ├── subtask-plan.md.template
│   ├── lessons-learned.md.template
│   ├── decisions.md.template
│   └── project-seed/            # 棚卸し・実行台帳・移行対応台帳・worklog・work-plan等の初期ファイル
├── tools/                       # hook から呼ばれるツール（下記「ターン時刻の記録と着手時の宣言」）
├── verify.sh.template           # 検証ゲート雛形（全8ゲート。work-plan 確定で適用が切り替わる4段＋常時適用の4段）
└── setup-modernized.sh              # 実装ツリー作成（clone+branch / copy+init）
```

設置スクリプト`install.sh`はリポジトリルートにある。

## 設計原則

1. **コンテキスト負荷の最小化（実行規律のラダー）**: 常時ロードするのは`core/`の薄いコアだけにする。
   詳細手順はオンデマンドでロードするskillsに置く。強制が必要な規律は、verify.shやgitといった
   ツールに依存しない仕組みで検査する。プロンプトに書いただけの制約は守られる前提にしない
2. **コピー方式の配布**: エージェントはワークスペースルートで起動する。ルールは`.kiro/steering/`などへ
   コピーするので、利用者がサブフォルダで起動する必要はない
3. **ツール非依存**: skillsのSKILL.mdのfrontmatterはKiroとClaude Codeで機能する。
   それ以外のツールでも、通常のMarkdown文書として参照できる
4. **No duplication**: CLAUDE.mdなどツール別のファイルは、ソース（core/templates）から生成する
5. **利用者の操作が必要な機能は、その操作と確認手段を添えて配布する**: hookを使う機能は、
   エージェントの起動方法によっては動作しない。そのためinstall.shは必要な操作を出力に表示し、
   機能が動作しているかを確認する手段も同梱する。Kiroでは`--agent migration`を付けて起動する必要がある

## 使い方

### インストール

対象ソース・実装ツリー・記録リポジトリを並べる親ディレクトリ（ワークスペースルート）で、次のコマンドを実行する。

```bash
cd /path/to/workspace
git clone https://github.com/aws-samples/sample-ai-modernization-flow.git   # または任意の場所に取得済みのパスを使う
./sample-ai-modernization-flow/install.sh --project myapp-1.0 \
    --playbook java-modernization
```

| オプション | 内容 |
|-----------|------|
| `--project <name>` | `<name>-migration-<YYYYMMDD>/`を雛形から生成し、git initする |
| `--lang ja\|en` | 設置するルールと雛形の言語（デフォルトはja）。`ja/`が原本で、`en/`は生成物 |
| `--tool kiro\|claude-code\|both` | ルールの設置先（デフォルトはboth） |
| `--playbook <name\|path>` | Playbook層をプロジェクトにコピーする。`playbooks/`配下の名前かパスを指定する。Playbookが1つしかなければ省略できる |
| `--skip-project` | ルール（coreとskills）の再設置・更新だけを行う。記録リポジトリの中身は一切変更しない |
| `--update-project [<dir>]` | 既存の記録リポジトリを本バージョンへ更新する（下記「ハーネスの更新」） |
| `--no-turn-log` / `--no-work-guard` | ターン時刻の記録と着手時の宣言を無効化する。どちらも既定でオンになっている。下記の節を参照 |

### Windowsで使う場合

`install.sh`はGit Bash（MSYS2またはCygwin）から実行する。cmd.exeやPowerShellからは実行できない。
`install.sh`はWindowsを自動で検出し、下表の差異に対処したうえで、そのホストで必要な対応をインストール時に表示する。
表示はすべて警告であり、インストール自体は完了する。

下表の事象はいずれもエラーを出さずに失敗するので、事前に把握しておく。

| 事象 | 内容 |
|------|------|
| hookの`command` | ツールのhookランナーはネイティブWindowsのプロセスAPIでコマンドを起動するので、シェバンが解釈されない。`.sh`を直接指定したhookは起動されず、毎ターンエラーを出さずに失敗する。そのため`install.sh`はWindowsでは`bash "<path>"`の形でコマンドを書き出す。この形式は`bash`がネイティブのPATHから見えることを前提とする。`install.sh`は`where bash`で確認し、見つからなければ警告する |
| `python3`が見つかるのに実行できない | Windowsの`python3`は通常、WindowsAppsのApp Execution Aliasスタブである。`command -v`では見つかるが、実行するとMicrosoft Storeへの誘導を表示して終了する。実体は`python`という名前で入っているのが普通である。`install.sh`は候補を実際に実行して検証し、実行できたものを設置スクリプトに書き込む |
| `$HOME`と`%USERPROFILE%`が一致しない | Git Bashの`$HOME`は、Windowsのユーザープロファイルと別のドライブになることがある（実測では`/h/`と`D:\Users\<user>`）。ネイティブプロセスとして動くツール（外部エージェントなど）からは`~/`配下のファイルを参照できない。JDKやMavenなどのツールチェーンは`%USERPROFILE%`配下に置く。ある案件では`~/tools/`に置いたJDKが見つからず、課金される30エージェント分を探索だけで使い切った |

### 設置後のワークスペース

```
<workspace>/                      ← ここでAIエージェントを起動
├── .kiro/
│   ├── steering/
│   │   ├── migration-core.md     ← コア規律（ハーネス更新で上書き）
│   │   └── migration-project.md  ← プロジェクト固有（PLACEHOLDER を編集）
│   └── skills/migration-*/       ← 詳細手順（オンデマンドロード）
├── CLAUDE.md                     ← Claude Code用（プロジェクト固有+コア規律）
├── .claude/skills/migration-*/
├── <product>/                    ← 対象ソース（Off-limits。内容は変更しない）
├── <product>-modernized/         ← 実装ツリー（Phase 3 Step 1で作成）
└── <project>-migration-<date>/   ← 記録リポジトリ（記録・計画・検証。gitリポジトリ）
```

1つのシステムが複数のリポジトリで構成される場合は、対象ソースと実装ツリーをリポジトリごとに並べる。

```
├── api/            ├── api-modernized/
├── web/            ├── web-modernized/
└── <project>-migration-<date>/   ← 記録リポジトリは1つ
```

対象リポジトリの棚卸しは`00-analysis/repository-inventory.md`に記録する。
実装ツリーの一覧は`verify.sh`の`MODERNIZED_TREES`で管理する。

### エージェントへの最初の指示

利用者が`<PLACEHOLDER>`を手で埋める必要はない。エージェントが起動時のインタビューで埋め、
埋められなかった項目だけをまとめて質問する。開始時に必要な情報は、対象ソースのパスとoff-limitsの範囲だけである。
移行先スタックは未定のままでよく、Phase 0bで分析結果を見てから決める。

用途に応じて、次の4パターンのいずれかを指示する。

**A. アセスメントから始める（AWS Transform（ATX）の分析を実行する）**

```
<対象ソースのパス> のアセスメントを開始します。
00-analysis/analysis-procedure.md の Phase 0a に従い、リポジトリ棚卸しから始めてください。
移行先スタックは未定です。分析結果を見てから決めます。
```

**B. 既存のATX分析結果を使う（実行をスキップする）**

```
<対象ソースのパス> のアセスメントを開始します。
ATX の分析結果が <結果フォルダのパス> にすでにあります。
Phase 0a は実行ではなく取り込み（ingest）として進めてください。
リポジトリ棚卸しは実施し、結果と各リポジトリの対応付け・分析時点とのコード差（分析時点のSHAと現在のHEADの差）を
確認してください。不足しているリポジトリ・分析種別があれば、その分だけ実行してください。
```

**C. アセスメント後に移行へ進む**

```
アセスメント結果をもとに移行に進みます。Phase 0b から続けてください。
```

**D. セッションをまたいで再開する**

```
作業を再開します。03-worklog/session-context.md を読んで前回の状態を確認し、続きから進めてください。
```

アセスメントだけで終える場合は、Phase 0aの完了時点（分析結果そのもの）か、Phase 0bの完了時点（移行判断の材料）で作業を止められる。
このときも`install.sh`の実行内容は移行まで進む場合と変わらない。
work-planが未確定のあいだ、verify.shのbuild・smoke・integrationの各ゲートは「未適用」として扱われる。

### ハーネスの更新

ハーネスの更新は2段階に分かれている。`--skip-project`で更新されるのはルールだけである。

```bash
cd /path/to/workspace
./sample-ai-modernization-flow/install.sh --skip-project        # core と skills だけ
./sample-ai-modernization-flow/install.sh --update-project --playbook <name>   # 記録リポジトリの中身
# --update-project のディレクトリは <名前>-migration-<日付>/ が1つだけなら省略できる
# 複数あるときは --update-project <dir> か --project <名前> で指定する
```

`--skip-project`は`migration-project.md`と`CLAUDE.md`を保持する。CLAUDE.md内のコア規律の更新は、利用者が手動でマージする。
`verify.sh`を含む記録リポジトリの中身は、`--skip-project`では更新されない。
ある案件では、`--skip-project`で更新したつもりでいたが`verify.sh`は旧版のままだった。
そのためリリースの主目的だった変更が反映されず、7ファイルを手作業で同期してようやく期待どおりに動作した。

#### 上書きされるファイルと保持されるファイル

上書きするかどうかは、利用者がそのファイルに書き込むかどうかだけで決まる。

| 扱い | 対象 |
|------|------|
| 再生成（上書き） | `00-analysis/analysis-procedure.md`, `00-analysis/*.sh`（Method の tools）, `setup-modernized.sh`, `03-worklog/templates/subtask-plan.md.template`, `docs/reference/`・`00-analysis/transform-config-cca-template.yaml`・`modernized-gitignore.template`（Playbook） |
| 保持（変更しない） | `verify.sh`, `docs/decisions/decisions.md`, `docs/knowledge/*.md`, `01-plan/*.md`, `00-analysis/repository-inventory.md`, `analysis-runs.md`, `analysis-appendix.md`, `02-test/*.md`, `03-worklog/session-context.md`, `worklog.md`, `.gitignore` |

保持するファイルのうち現行テンプレートと差異があるものは、新しいテンプレートが`.flow-update-<version>/`配下に同じ相対パスで置かれる。
差異がなければ何も置かれず、そのファイルの刻印だけが現行版に更新される。マージを終えたら`.flow-update-<version>/`をディレクトリごと削除する。

この一覧は`install.sh`の`PROJECT_FILE_MAP`の1箇所だけで定義している。インストールと更新が同じ表を読むので、
テンプレートを追加したときに片方だけが更新される事故は起きない。以前は一覧を2つに分けて実装しており、
書いた当日にPlaybookの2ファイルを更新対象から漏らしていた。`--playbook`を付けずに更新するとPlaybook側のファイルは
更新対象から外れるので、install.shはその旨を警告として出力する。

`verify.sh`は必ず保持される。期待リスト・`BUILD_CMD`・smokeとintegrationの実装はプロジェクト側のコピーにしか存在しない。
そのためマージでは、これらをプロジェクト側から`.flow-update-<version>/verify.sh`へ移す。
逆向きにマージすると、次の更新でも同じ作業が必要になる。
install.shはファイルを削除しない。フレームワークから消えたファイルは報告するだけで、プロジェクトには残す。

#### プロジェクトのゲートの版の確認

`verify.sh`の2行目には生成元の版が刻まれている。版を照合する手段はこの行だけである。

```bash
grep '^# ai-modernization-flow ' <records>/verify.sh   # → # ai-modernization-flow 0.11.0
```

`--update-project`はこの行を読んで更新元の版を表示する。刻印がない場合（この行を削除した場合など）は`unstamped`と表示される。
保持されたファイルの刻印は更新しない。マージが済むまでは、そのゲートの中身は実際に旧版のままだからである。

## ターン時刻の記録と着手時の宣言（既定オン。`--no-turn-log` / `--no-work-guard`で無効化）

エージェントの自己申告に頼る記録は、書き忘れても検出できない。そこでhookで採取できる情報はhookで採取する。
この仕組みは既定で設置される。無効化するには、`install.sh`に`--no-work-guard`（宣言を求めない）か`--no-turn-log`（記録もしない）を付ける。

| 設置されるもの | 役割 |
|--------------|------|
| `03-worklog/turn-log.sh` | hookから毎ターン呼ばれ、同じディレクトリの`turn-log.tsv`に時刻・イベント・session_idを追記する。プロンプト本文は保存しない |
| `03-worklog/turn-report.sh` | `--worklog`でworklogに貼る表を、`--list`で記録の一覧を、`--declare`で宣言行を出力する |
| `03-worklog/work-declaration-guard.sh` | `--no-work-guard`を指定した場合は設置されない。宣言がなければ変更系ツールの実行を止める（`Bash`は対象外） |

pythonのパスは設置時に解決し、3つのスクリプトに直接書き込む。hookは毎ターン実行されるので、実行時にはpythonを探索しない。
pythonを入れ替えたり、削除したり、別の場所に移したりすると、書き込んだパスが無効になり、エラーを出さずに記録が止まる。
hookはfail-openで動作し、記録に失敗してもツールの操作は止めない。この事象はOSを問わず起きる。
`turn-report.sh --list`を実行して記録が増えていなければ、`install.sh --update-project`でパスを書き込み直す。

Kiroでは、起動時にエージェントを明示する必要がある。明示しないと、設定を置いても何も記録されない。
既定の起動方法では組み込みエージェントが使われ、組み込みエージェントにはhookを設定できないからである。
また、ワークスペースのルート以外から起動すると、Kiroは警告を出さずに同名のグローバル設定を使う。

```bash
cd <ワークスペースのルート> && kiro-cli chat --agent migration
./<project>-migration-<date>/03-worklog/turn-report.sh --list   # 記録されているかの確認
```

恒久的に残る記録は、worklogに貼った表と宣言だけである。生ログはgitの管理対象から外している。
表の列は、指示（受領）、返答（返却）、所要（AI）、待機（人）、備考である。表の後に、所要と待機それぞれの件数、中央値、最小、最大、合計が続く。
1時間（`TURN_LOG_IDLE_LIMIT`）を超える待機は離席とみなし、待機の統計から除く。
worklogへ転記するタイミングはskills/migration-recordingに、宣言の運用方法はskills/migration-troubleshootingに記載している。
仕組みの詳細、注意点、セキュリティ方針は各スクリプトの冒頭コメントに記載している。

## ツール対応状況

| ツール | コア規律 | skills | 状態 |
|--------|---------|--------|------|
| Kiro (CLI/IDE) | `.kiro/steering/` | `.kiro/skills/`（skill://で自動認識） | 対応 |
| Claude Code | `CLAUDE.md` | `.claude/skills/`（Agent Skills） | 対応 |
| その他（Cursor等） | 各ツールのルールファイルに core をコピー | skills/ を参照ドキュメントとして指示 | 手動設置 |

## 利用者が明示的に判断すべき項目

ハーネスは次の項目を自動では決めない。利用者はプロジェクトの開始時にPlaybook層のREADMEの「利用者が明示的に判断すべき項目」を確認し、各項目を暗黙のままにせず決めておく。

- baselineモードの選択（実測、コード読解、既存テストの流用）
- 非機能スコープ（ADR化が必須）
- 長時間試験の実施計画
- Tier 2（HOLD・停止確認ゾーン）のトリガーの調整
- ナレッジの棚卸し
- クラウド操作のガードレール（本ハーネスでは提供しない）
- 本番相当データの利用可否
