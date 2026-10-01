# Playbook: C / Solaris x86 → Amazon Linux (clang/gcc)

C言語プロダクトを Solaris (SPARC/x86, ILP32) から Amazon Linux (x86_64, LP64) へ移植するための
**Playbook（中位・実務文書層）**。移行ドメイン固有の知見・観点・実装例を提供する。

> フロー（Phase 0-4）・3つの終了点・利用者判断項目は `../../method/flow.md`、
> AI実行規律は `../../harness/` を参照。セットアップはリポジトリルートの `install.sh`。

## 構成

| ファイル | 内容 | プロジェクトへのコピー先 |
|---------|------|------------------------|
| `practices.md` | 移行プラクティス集（DP-N形式。作業中に追記され育つ） | `docs/knowledge/practices.md` |
| `analysis-appendix.md` | ドメイン固有の分析観点（マクロ値man裏取り、libc ABI、LP64、Y2038等） | `00-analysis/analysis-appendix.md` |
| `baseline-themes.md` | このドメインで壊れやすい振る舞いのテストパターン（境界年スキャン、構造体レイアウト等） | `02-test/baseline-themes.md` |
| `verify-snippets.md` | verify.sh 各ゲートのC/Unix向け実装例（ldd、デーモン生存、valgrind等） | `02-test/verify-snippets.md` |
| `modernized-gitignore.template` | ビルド成果物のignore（*.o/*.a/*.so等） | プロジェクト直下（setup-modernized.shが使用） |
| `transform-config-cca-template.yaml` | AWS Transform custom (ATX) の構造分析（CCA）の設定テンプレート | `00-analysis/transform-config-cca-template.yaml`（Phase 0a-4 で `00-analysis/<repo-id>/transform-config-cca.yaml` に実体化） |
| `reference/solaris_linux_differences.md` | OS間差異の知見（ATXインポート用にも使用） | `docs/reference/` |
| `reference/longrun_server_migration_considerations.md` | 64bit化・2038年問題・テスト戦略等 | `docs/reference/` |
| `reference/ilp32-to-lp64-struct-layout.md` | ILP32→LP64 の構造体レイアウト変化（DP-7 の詳細） | `docs/reference/` |

## クイックスタート

ワークスペースルート（対象ソースを置く親ディレクトリ）で:

```bash
cd /path/to/workspace
/path/to/sample-ai-modernization-flow/install.sh --project <product-version> \
    --playbook clang-solarisx86-to-amznlinux
```

その後、ワークスペースルートでAIエージェントを起動し、対象ソースのパスを渡して
「アセスメントを開始します。Phase 0a から始めてください」と指示する。
`<PLACEHOLDER>` は起動インタビューでエージェントが埋める（手で埋めなくてよい）。
`transform-config` は Phase 0a-4 でリポジトリごとに実体化される。

## このドメインの特徴的な論点

- **ILP32 → LP64**: ポインタ↔intキャスト（intptr_t化）、構造体レイアウト変化（DP-3, DP-7）
- **Y2038**: time_t 32bit前提のハードコード、表示層・範囲計算層のレイヤー別検証（DP-5, DP-6）
- **RPCワイヤー互換**: 外部32bitクライアントとの互換維持（xdr_time_t_compat パターン）
- **ビルドシステム**: imake等の旧世代ビルドの再現性はテンプレート層で担保（生成物直接編集を避ける）
- **実行環境の罠**: LD_LIBRARY_PATH・前提デーモン（rpcbind等）起因の「偽SEGFAULT」に注意（CP-8）

詳細は `practices.md`（DP-1〜DP-9）と `reference/` 配下を参照。

## 指示に含めるべき情報

| 項目 | 例 |
|------|---|
| ソースコードのパス | `/path/to/<product>/` |
| ターゲット環境 | Amazon Linux 2023 x86-64 (SSH: `ssh <host>`) |
| 依存ライブラリとバージョン | OpenSSL 3.x, PCRE 8.44, zlib等 |
| 移植元の環境情報 | Solaris x86 32bit, OpenSSL 1.x, Sun Studio等 |
| configure/ビルドコマンド | `./configure ...` / `make` |
| 制約（あれば） | 「過去のgitコミットは参照しない」等 |

## 過去のプロジェクト実施例

- デスクトップ環境ソフトウェア（C言語、Solaris/SPARC・x86 32bit → Amazon Linux 64bit）:
  全13 Step完了、verify 37/37 PASS。practices.md の DP-N は複数の移植事例から得た知見であり、DP-1 は nginx 系サーバーの事例に由来する（DP-3〜DP-7 は主にこのプロジェクトで追加された）
