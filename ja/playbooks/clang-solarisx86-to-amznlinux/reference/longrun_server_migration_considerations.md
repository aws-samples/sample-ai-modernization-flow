# 長期運用サーバーアプリケーションのSolaris x86→Amazon Linux移行考慮事項

**注**: 本ドキュメントはSolaris x86 (32bit) から Amazon Linux (x86-64アーキテクチャ)を対象とする。

---

## 目次

1. [Solaris移行でよく遭遇するパターン](#1-solaris移行でよく遭遇するパターン)
2. [必要な変換の整理](#2-必要な変換の整理)
3. [64bit化の考慮事項](#3-64bit化の考慮事項)
4. [2038年問題の対応](#4-2038年問題の対応)
5. [文字コード・ロケールの対応](#5-文字コードロケールの対応)
6. [依存ライブラリの更新リスク](#6-依存ライブラリの更新リスク)
7. [互換レイヤー設計](#7-互換レイヤー設計)
8. [テストコードがない状態での品質保証戦略](#8-テストコードがない状態での品質保証戦略)
- [Appendix A: 移行の進め方（案）](#appendix-a-移行の進め方案)
- [関連ドキュメント](#関連ドキュメント)
- [情報ソース](#情報ソース)
- [更新履歴](#更新履歴)

---

## 1. Solaris移行でよく遭遇するパターン

以下は、C/C++で書かれたSolarisサーバーアプリケーションをAmazon Linuxへ移行する際に
実務上よく遭遇し、見落とすと後工程で問題化しやすい特徴である。分析フェーズで
自分のシステムに当てはまるものを確認し、該当する章を重点的に確認する。

| 特徴 | 見落とすとどうなるか | 関連章 |
|------|---------------------|--------|
| 32bitバイナリで動作している | 64bit化を後回しにすると構造体変更等の作業を二度行うことになる | [3章](#3-64bit化の考慮事項) |
| time_tを含むデータを永続化・送受信している | 2038年問題が本番稼働後に発覚する | [4章](#4-2038年問題の対応) |
| 長期運用（5年以上）でメンテナンスされてきた | Solaris固有の暗黙の前提が積み重なり、移行時に想定外の箇所で問題が出る | 全般 |
| ステートフル（接続状態・セッションをメモリ上に保持する） | Solaris版とLinux版の並行稼働・切り替え手順の設計が難しくなる | [8章](#8-テストコードがない状態での品質保証戦略) |
| 非UTF-8の文字コード（EUC-JP, Shift_JIS等）を内部で使用している | ロケール依存関数の挙動差でデータ破損・表示崩れが起きる | [5章](#5-文字コードロケールの対応) |
| 依存ライブラリの導入から長期間バージョンを上げていない | 最新版でAPI・挙動が大きく変わっている可能性が高い | [6章](#6-依存ライブラリの更新リスク) |
| 自動テストが不十分、または存在しない | 移行の正しさを検証する手段がなく、リグレッションを本番で発見することになる | [8章](#8-テストコードがない状態での品質保証戦略) |
| 大規模コードベース（数十万行以上） | 一括書き換えのリスクが高く、段階的移行の設計が必要になる | [Appendix A](#appendix-a-移行の進め方案) |

当てはまらない特徴の章は読み飛ばしてよい。

---

## 2. 必要な変換の整理

### 2.1 システムコール・API差異

| カテゴリ | Solaris | Linux |
|---------|---------|-------|
| スレッドライブラリ | Solaris threads | POSIX threads (pthread) |
| イベント駆動I/O | `port_*()` (event ports) | `epoll_*()` |
| Atomic操作 | `atomic_*()` (atomic.h) | GCC builtins (`__atomic_*`, `__sync_*`) |
| 時刻取得 | `gethrtime()` | `clock_gettime(CLOCK_MONOTONIC)` |
| プロセス間通信 | `door_*()` | Unix domain sockets / shared memory |

### 2.2 ライブラリ依存

| Solaris | Linux |
|---------|-------|
| libthread/libpthread | glibc pthread (統合済み) |
| libnsl, libsocket | glibc (統合済み、リンク変更のみ) |
| libkstat | `/proc`, `/sys` 経由の実装 |
| libdl | glibc dlopen/dlsym |

### 2.3 コンパイラ・ビルド環境

| Solaris | Linux |
|---------|-------|
| Sun Studio/Oracle Solaris Studio | GCC/Clang |
| `-mt` | `-pthread` |
| `-KPIC` | `-fPIC` |
| `CC=cc` | `CC=gcc` |

64bit化問題の早期検出用GCC警告フラグ:
```
-Wpointer-to-int-cast -Wint-to-pointer-cast -Wformat -Wall -Wextra
```

### 2.4 ファイルシステム・パス

- `/usr/ucb/*` → 標準Linuxコマンド
- `/opt/csw/*` (OpenCSW) → Amazon Linuxパッケージ
- `/devices/*` → `/dev/*`, `/sys/*`

---

## 3. 64bit化の考慮事項

### 3.1 ILP32からLP64への型変化

Solaris移行と同時に64bit化を行う（別々にやると構造体サイズの変更等を二度やることになる）。

ILP32（32bit）からLP64（64bit）への移行で変化する型:

| 型 | 32bit | 64bit | 影響 |
|---|-------|-------|------|
| `int` | 4バイト | 4バイト | 変化なし |
| `long` | 4バイト | 8バイト | 要注意 |
| `pointer` | 4バイト | 8バイト | 要注意 |
| `time_t` | 4バイト | 8バイト | 2038年問題解決 |
| `size_t` | 4バイト | 8バイト | 要注意 |

### 3.2 64bit化で壊れるコードのパターン

危険なコードパターン:

- `int`にポインタを格納している箇所（64bitでポインタ切り詰め）
- `sizeof(long)`に依存した処理
- 構造体のサイズ・パディング変化（ネットワークプロトコル、ファイルフォーマット、共有メモリに影響）
- `printf`のフォーマット指定子（`%d`で`long`を出力等）
- キャストの暗黙的な切り詰め

---

## 4. 2038年問題の対応

### 4.1 問題の概要

対象システムが32bitバイナリで動作している場合、`time_t`が32bit符号付き整数（`int32_t`）であれば、2038年1月19日 03:14:07 UTCでオーバーフローする。

長期運用サーバーで影響を受ける典型的な箇所:

- ユーザーデータのタイムスタンプ（作成日時、最終アクセス日時等）
- 期限付きリソースの有効期限
- スケジュール処理（定期メンテナンス、イベント等）
- ログのタイムスタンプ
- セッション管理（タイムアウト計算）
- DB内の日時カラム（PL/SQL側）
- スクリプト内のepoch時刻処理

### 4.2 推奨解決策: Solaris移行と同時に64bit化

Amazon Linux (x86-64) で64bitバイナリとしてビルドすれば、`time_t`は自動的に64bit（`int64_t`）になり、2038年問題は根本解決する。Solaris→Linux移行と同時にやるのが最も効率的（別々にやると構造体サイズの変更等を二度やることになる）。

### 4.3 ネットワークプロトコルの分離

クライアント⇔サーバー間でバイナリプロトコルを使用している場合、サーバー内部の型とワイヤーフォーマットを明確に分離する必要がある。

```c
// ワイヤーフォーマット（固定サイズ、変更しない）
struct wire_packet_header {
    uint16_t type;
    uint32_t timestamp;  // プロトコル上は32bit維持
    uint32_t entity_id;
} __attribute__((packed));

// 内部表現（64bit）
struct internal_event {
    uint16_t type;
    int64_t  timestamp;  // 内部は64bit
    uint64_t entity_id;
};
```

クライアント更新と合わせて段階的にプロトコル側も64bit対応を進める。

### 4.4 永続化データの確認

- DB のDATE/TIMESTAMP型 → 2038年問題なし
- DB にinteger型でepoch格納 → カラムの型を確認。32bit integerなら拡張が必要
- ファイルに保存されたバイナリデータ（永続化データ等） → フォーマット変更が必要な場合あり
- ファイルに保存された文字列データ（ユーザー名等） → 内部エンコーディング維持方針のため変換不要。ただしエンコーディングの特定は必要
- 共有メモリ上の構造体 → サイズ変化に注意

**ネットワークファイルシステム（NFS等）上にデータを保持している場合**は、以下の2点を追加で確認する。

- **データファイル内部のタイムスタンプ**: アプリケーションがファイル内にepoch時刻をバイナリ書き出ししている場合（`time_t`を32bitでそのまま書き込む等）、フォーマット変更とデータマイグレーションが必要になる。文字列（ISO 8601等）で格納している場合は影響なし
- **ファイルシステム自体のタイムスタンプ**: NFSv4（RFC 7530）では秒単位のデータは符号付64bitで定義されており、NFS自体の2038年問題は解決済み。ただしNFSクライアント側のOS・glibcが64bit time_tに対応しているか、`stat()`等で取得したタイムスタンプをアプリケーション内で32bit変数に格納していないかは別途確認が必要

### 4.4.1 y2k38-checker による影響調査

2038年問題の影響箇所を静的解析で検出するツールとして、立命館大学サイバーセキュリティ研究室が開発した [y2k38-checker](https://github.com/cysec-lab/y2k38-checker) が利用可能。Clang Static Analyzerのプラグインとして動作し、C言語ソースコードを対象とする。

#### 検出可能な項目

| チェックID | 検出内容 |
|-----------|---------|
| `read-fs-timestamp` | ファイルタイムスタンプの読み取り箇所（ext2/3, XFS等で32bit制限の影響を受ける可能性） |
| `write-fs-timestamp` | ファイルタイムスタンプの書き込み箇所 |
| `timet-to-int-downcast` | `time_t`から`int`へのダウンキャスト（32bit切り詰めの危険） |
| `timet-to-long-downcast` | `time_t`から`long`へのダウンキャスト |

#### 活用方針

- フェーズ1（静的解析）で、grepベースのSolaris固有API検索と併用して実行する
- 特にNFSデータファイルの読み書き処理周辺を重点的にチェックする
- 大規模コードベースに対して、`time_t`関連の問題箇所を網羅的に洗い出せる

#### 導入方法と制約

- Linux x86_64環境が必要（Linux x86_64 の開発環境を用意するか、手動でツールチェーンを構築する）
- Clang 11.0.0ベースのプラグインとして動作
- Rustレポーターで結果を構造化出力
- 検出結果は誤検知を含む可能性があるため、人手でのトリアージが必要

#### 推奨する実行手順

```
ステップ1: y2k38-checkerのセットアップ（Linux x86_64 の開発環境 or 手動ツールチェーン構築）
ステップ2: ソースコード全体に対してスキャン実行
ステップ3: 検出結果のトリアージ（誤検知の除外）
ステップ4: データI/O周辺の検出結果を優先的に対応
ステップ5: 残りの検出箇所を優先度に基づいて対応
```

### 4.5 推奨移行順序

```
ステップ1: Solaris x86 (32bit) → Amazon Linux x86-64 (64bit)
           ・OS移行 + 64bit化を同時実施
           ・time_tは自動的に64bitになる

ステップ2: ネットワークプロトコルの2038年対応
           ・クライアント更新と合わせて段階的に
           ・サーバー側は32bit/64bitタイムスタンプ両対応にしておく

ステップ3: DB/永続化データの2038年対応
           ・integer epoch → TIMESTAMP型への移行等
```

ステップ1でサーバー内部の2038年問題は解決する。ステップ2・3はクライアント更新やメンテナンスのタイミングで段階的に進められる。

### 4.6 32bitバイナリのまま対応する方式（非推奨）

Linux（glibc 2.34+）では`-D_TIME_BITS=64 -D_FILE_OFFSET_BITS=64`で32bitバイナリでも`time_t`を64bitにできるが、以下の理由で非推奨:

- Amazon Linux 2023はi686ユーザ空間パッケージを提供しない（glibc.i686、libstdc++.i686等の32bit版パッケージが存在せず、32bitバイナリのビルド・リンクが困難。カーネルレベルでの32bit実行能力は維持されているが、将来のバージョンでは32bit互換機能の提供が縮小される可能性があるため、AL2023のドキュメントで最新の状況を確認する）
- アドレス空間が4GBに制限される（大規模サーバーアプリケーションには厳しい）
- 64bit化で得られるパフォーマンス向上を捨てることになる

---

## 5. 文字コード・ロケールの対応

### 5.1 意思決定フレームワーク: 内部エンコーディングをどう扱うか

文字コード移行には大きく3つの選択肢がある。プロジェクトの状況に応じて判断する。

| 選択肢 | 内容 | 変更コスト | データマイグレーション | 適する状況 |
|---|---|---|---|---|
| A. 内部をUTF-8に統一 | サーバー内部処理を全てUTF-8化し、永続化データもマイグレーション | 高（文字列処理全般に影響） | 必要（既存データの一括変換） | 新規開発に近い規模で書き換える場合、長期的な保守性を優先する場合 |
| B. 内部エンコーディングを維持 | OS側はUTF-8だが、アプリケーション内部は既存エンコーディング（EUC-JP/Shift_JIS等）を維持 | 低（境界部分のみ対処） | 不要 | 移行そのもののリスクを最小化したい場合、大規模コードベースで変更範囲を絞りたい場合 |
| C. 段階的UTF-8化 | まずBの方針で移行を完了し、後から段階的にUTF-8化 | 中（2段階に分割） | 段階的に発生 | 移行を早く終えたいが将来的な統一も見据えたい場合 |

**選択肢Bを取る場合のトレードオフ**:
- 利点: 文字列処理・バッファサイズ・`strlen()`等バイト数前提の処理を変更せずに済む。既存の永続化データ（ファイル・DB・設定）をそのまま使い続けられ、データ破損リスクを避けられる
- 欠点: OS側のロケール設定と内部エンコーディングの不一致が生まれるため、境界部分（下記5.4）で個別の対処が必要になる。将来的にUTF-8統一が必要になった場合、その時点で改めて変換作業が発生する

**選択肢Aを取る場合のトレードオフ**:
- 利点: OS・ライブラリのデフォルトと内部処理が一致し、境界部分の特別対処が不要になる。将来の保守性が高い
- 欠点: 文字列処理全般（バッファサイズ見直し、バイト数前提コードの修正）に変更が及ぶ。永続化データの変換ツール作成・実行が必要で、データ破損リスクを伴う

### 5.2 ロケール差異

| Solaris | Linux |
|---------|-------|
| `ja_JP.eucJP` / `ja_JP.PCK` (Shift_JIS) | `ja_JP.UTF-8` |
| EUC-JP / Shift_JIS がデフォルト | UTF-8 がデフォルト |
| `iconv_open("PCK", "eucJP")` | `iconv_open("SHIFT_JIS", "EUC-JP")`（エンコーディング名が異なる場合あり） |

### 5.3 選択肢Bを取る場合に対処が必要な境界（内部エンコーディング維持）

Cプログラムのバイト列処理はロケール非依存で動作するため、OS側がUTF-8であってもアプリケーション内部で既存エンコーディングのバイト列をそのまま扱い続けることは可能。ただし以下の境界で対処が必要。

#### 5.3.1 ロケール依存のlibc関数

`setlocale(LC_CTYPE, "")` でOS側のUTF-8ロケールを取り込むと、以下の関数がSJIS/EUC-JPバイト列をUTF-8として解釈し、誤動作する。

| 関数 | 影響 |
|------|------|
| `mbstowcs()` / `wcstombs()` | 変換失敗 |
| `mblen()` / `mbrlen()` | 文字バイト数の判定が変わる |
| `strcoll()` / `strxfrm()` | ソート順が変わる |
| `isalpha()` / `toupper()` 等 | ロケール依存の判定結果が変わる |
| `strftime()` | 出力エンコーディングがUTF-8になる |

対処: フェーズ1の分析でこれらの関数の使用状況を調査し、ロケール設定の明示指定または関数の置き換えで対応する。

#### 5.3.2 GCCのソースファイル処理

GCCはデフォルトでソースファイルをUTF-8として解釈する。Shift_JISのソースファイルでは、2バイト目に`0x5C`（バックスラッシュ）を含む文字（「表」「能」「ソ」等）でコンパイルエラーや誤動作が起きる可能性がある。EUC-JPの場合はこの問題は発生しない。

対処: `-finput-charset=SHIFT_JIS -fexec-charset=SHIFT_JIS`（SJIS時）をコンパイルフラグに追加。

#### 5.3.3 ログ出力・運用ツール

アプリケーションが既存エンコーディングでログを出力する場合、OS側のツール（`grep`, `less`等）で文字化けする。機能的には壊れないが運用上の問題。

対処: ログ閲覧時に`iconv`でパイプする運用、またはログ出力部分のみUTF-8変換ラッパーを設ける。

#### 5.3.4 外部ライブラリ

libxml2等、内部UTF-8前提のライブラリを使用している場合は、入出力の境界でエンコーディング変換が必要。

### 5.4 リスク

- ロケール依存関数の使用箇所が多い場合、対処工数が増加する。フェーズ1の調査結果次第で方針を再検討する
- 将来的にクライアントがUTF-8化された場合、サーバー側に変換レイヤーの追加が必要になる

### 5.5 調査項目（フェーズ1で実施）

```bash
# ロケール依存関数の使用状況
grep -rn "setlocale\|mbstowcs\|wcstombs\|mblen\|mbrlen\|strcoll\|strftime\|iswalpha" src/

# ソースファイルのエンコーディング
file --mime-encoding src/**/*.c src/**/*.h

# iconv等の文字コード変換処理
grep -rn "iconv\|mb_convert\|nkf" src/ scripts/ tools/
```

---

## 6. 依存ライブラリの更新リスク

### 6.1 基本方針

20年以上メンテナンスされたシステムでは、商用ライブラリよりOSSが主体である可能性が高い。基本的には「同じライブラリのLinux版をビルドまたはパッケージで導入する」で対応できる。

### 6.2 リスクと対応方法

#### リスク1: 古いバージョンへの依存

最新版でAPIが変わっている可能性が高い。

例:
- OpenSSL 0.9.x → 3.x（API大幅変更、1.0系のAPIが削除済み）
- zlib 1.1.x → 1.3.x（概ね互換だが細部の挙動差あり）

対応:
- 現行で使っているバージョンを特定する（Makefile、configure、ヘッダのバージョンマクロ等）
- 最新版でビルドを試み、コンパイルエラーや非推奨警告から非互換箇所を洗い出す
- 非互換が大きい場合は、Amazon Linuxで動く範囲で最も古い安定版を使う選択肢もある（セキュリティリスクとのトレードオフ）

#### リスク2: 開発終了・後継なしのライブラリ

20年の間にメンテナンスが終了しているOSSがある可能性がある。

対応:
- 後継ライブラリがあればそちらに移行（例: libevent → libev → libuv）
- 後継がなければ、ソースコードを自前で保持してLinux上でビルドする
- 最悪の場合、該当機能を自前で再実装する

#### リスク3: Solarisパッチが当たったライブラリ

長期運用のシステムでは、OSSライブラリに独自パッチを当てていることがよくある（バグ修正、パフォーマンスチューニング、Solaris固有の挙動に合わせた調整等）。

対応:
- ライブラリのソースツリーが残っていれば、diffで本家との差分を確認する
- パッチの内容を理解した上で、最新版に同等のパッチが必要か判断する

#### リスク4: 暗黙的なSolaris libc依存

ライブラリ自体はクロスプラットフォーム対応でも、Solaris固有の挙動に依存している場合がある。

例:
- `strlcpy`/`strlcat`（Solarisにはあるが、glibcには2.38まで未搭載。Amazon Linux 2023のglibcは2.34系のため利用不可。自前のcompat関数を提供する必要がある）
- `getpassphrase()`（Solaris固有）
- `mmap`のフラグ差異（`MAP_ANON` vs `MAP_ANONYMOUS`）— ただしLinuxでは`MAP_ANON`が`MAP_ANONYMOUS`のエイリアスとして定義されており、通常は修正不要
- スレッドのデフォルトスタックサイズの違い

対応:
- Linux上でビルドすればコンパイルエラーとして検出できるので、発見自体は容易
- 足りない関数は小さなcompat関数で補える場合が多い

#### リスク5: ビルドシステムの問題

古いOSSはSolaris上でgmake + Sun Studio前提のビルド設定になっていることがある。

対応:
- 最新版を取得すれば、通常はGCC/Linux対応済み
- 古いバージョンを使わざるを得ない場合は、Makefileの修正が必要

#### リスク6: ライセンス変更

20年の間にライセンスが変更されたOSSがある。

対応:
- 最新版に上げる前にライセンスを確認する
- 問題があれば、ライセンス変更前のバージョンを使うか、代替ライブラリを検討

### 6.3 長期運用サーバーで使われる一般的なライブラリの移行見通し

| カテゴリ | よくあるライブラリ | Linux移行 | 注意点 |
|---------|------------------|----------|--------|
| ネットワーク | libevent, libev, ACE | 容易 | Linux対応済み |
| DB接続 | Oracle OCI (Pro*C), libpq | 可能 | Oracle使用ならOCIのLinux版が必要 |
| 暗号化 | OpenSSL | 要注意 | バージョン差が大きい可能性 |
| 圧縮 | zlib, lz4, snappy | 容易 | ほぼそのまま |
| スクリプト | Lua, Python (C embed) | 可能 | バージョン差に注意 |
| XML/JSON | libxml2, jansson, cJSON | 容易 | |
| ログ | syslog, log4cxx | 容易 | |
| メモリ | libumem, jemalloc, tcmalloc | 可能 | libumemはLinuxにないのでjemalloc等に置換 |
| 文字列/正規表現 | PCRE, ICU | 容易 | バージョン差に注意 |
| 文字コード変換 | iconv, ICU, nkf | 可能 | エンコーディング名の差異（Solarisの`PCK`→Linuxの`SHIFT_JIS`等） |

### 6.4 推奨する進め方

1. ライブラリ一覧の作成: Makefileやconfigureからリンクオプションやincludeパスを抽出
2. 3分類に仕分け:
   - A: Amazon Linuxのパッケージで提供されている → `dnf install`で済む
   - B: ソースからビルドが必要だが最新版でOK → ソース取得してビルド
   - C: 独自パッチあり、または古いバージョン固定 → 個別対応が必要
3. Cに該当するものが移行工数の大部分を占めるので、早期に特定する

---

## 7. 互換レイヤー設計

### 7.1 設計パターン（APRベース）

#### 階層的フォールバック戦略

```
最適化実装 (Solaris atomic.h, Linux epoll)
    ↓ (利用不可の場合)
標準実装 (POSIX, GCC builtins)
    ↓ (利用不可の場合)
汎用実装 (mutex, select)
```

### 7.2 推奨ディレクトリ構造

```
solaris_compat/
├── include/
│   └── solaris_compat.h        # 統一API定義
├── atomic/
│   ├── solaris_atomic.c        # Solaris実装
│   └── linux_atomic.c          # Linux実装
├── poll/
│   ├── solaris_port.c          # event ports
│   └── linux_epoll.c           # epoll
├── time/
│   ├── solaris_time.c
│   └── linux_time.c
└── CMakeLists.txt              # ビルド設定
```

### 7.3 条件付きコンパイルパターン

```c
/* solaris_compat.h */
#ifdef __sun__
  #include <sys/port.h>
  #define USE_EVENT_PORTS
#elif defined(__linux__)
  #include <sys/epoll.h>
  #define USE_EPOLL
#endif

/* 統一API */
int compat_event_init(void);
int compat_event_wait(int timeout);
```

### 7.4 参考実装: オープンソースソフトウェア

#### 1. Apache Portable Runtime (APR) ⭐最推奨

- **URL**: https://github.com/apache/apr
- **特徴**: 
  - Solaris、Linux含め20以上のプラットフォーム対応
  - ファイルI/O、ネットワーク、スレッド、プロセス、共有メモリなど網羅
  - 250以上のAPIを統一インターフェースで提供
- **参考コード**:
  - `apr/include/arch/unix/apr_arch_*.h` - プラットフォーム検出
  - `apr/atomic/unix/solaris.c` - Solaris atomic実装
  - `apr/atomic/unix/builtins.c` - Linux/GCC実装
  - `apr/poll/unix/port.c` - Solaris event ports
  - `apr/poll/unix/epoll.c` - Linux epoll

#### 2. libevent

- **URL**: https://libevent.org/
- **特徴**:
  - 非同期I/Oイベント処理ライブラリ
  - Solaris event ports → Linux epoll の抽象化
  - 軽量で実装がシンプル
- **参考コード**:
  - `evport.c` - Solaris event ports実装
  - `epoll.c` - Linux epoll実装

#### 3. PostgreSQL

- **URL**: https://github.com/postgres/postgres
- **特徴**:
  - 30年以上の移植性実績
  - プラットフォーム固有の最適化とフォールバック実装
- **参考コード**:
  - `src/include/port/solaris.h` - Solaris固有定義
  - `src/include/port/linux.h` - Linux固有定義

#### 4. ACE (ADAPTIVE Communication Environment)

- **URL**: https://www.dre.vanderbilt.edu/~schmidt/ACE.html
- **特徴**:
  - C++ベースの大規模通信ミドルウェア
  - 50以上のプラットフォーム対応
- **参考コード**:
  - `ace/config-sunos5.*.h` - Solaris設定
  - `ace/config-linux.h` - Linux設定

### 7.5 主要API変換リファレンス

#### Atomic操作

| Solaris | Linux/GCC |
|---------|-----------|
| `#include <atomic.h>` | GCC builtins (no include) |
| `atomic_add_32_nv(ptr, val)` | `__atomic_add_fetch(ptr, val, __ATOMIC_SEQ_CST)` ⚠️ |
| `atomic_cas_32(ptr, old, new)` | `__atomic_compare_exchange_n(ptr, &old, new, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)` ⚠️ |

> ⚠️ **add系戻り値の差異に注意**: `atomic_add_32_nv()` は**加算後の新しい値**を返す。Linux GCC builtinsでは `__atomic_add_fetch()` が新値を返し、`__atomic_fetch_add()` は加算前の旧値を返す。Solarisの `_nv` サフィックス（new value）と等価なのは `__atomic_*_fetch()` 系である。

> ⚠️ **CAS戻り値の型差異に注意**: `atomic_cas_32()` は旧値(`uint32_t`)を返すが、`__atomic_compare_exchange_n()` は成否(`bool`)を返し、旧値は第2引数(`&old`)に書き戻される。正しい等価コード:
> ```c
> uint32_t expected = cmp;
> __atomic_compare_exchange_n(ptr, &expected, newval, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
> // expected に旧値が格納される（atomic_cas_32 の戻り値に相当）
> ```

| Solaris | Linux/GCC |
|---------|-----------|
| `atomic_inc_32_nv(ptr)` | `__atomic_add_fetch(ptr, 1, __ATOMIC_SEQ_CST)` |
| `atomic_dec_32_nv(ptr)` | `__atomic_sub_fetch(ptr, 1, __ATOMIC_SEQ_CST)` |
| `atomic_swap_32(ptr, val)` | `__atomic_exchange_n(ptr, val, __ATOMIC_SEQ_CST)` |

#### イベント駆動I/O

| Solaris | Linux |
|---------|-------|
| `port_create()` | `epoll_create1(EPOLL_CLOEXEC)` |
| `port_associate(port, PORT_SOURCE_FD, fd, events, user)` | `epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev)` |
| `port_dissociate(port, PORT_SOURCE_FD, fd)` | `epoll_ctl(epfd, EPOLL_CTL_DEL, fd, NULL)` |
| `port_get(port, &event, timeout)` | `epoll_wait(epfd, events, 1, timeout)` |
| `port_getn(port, events, max, &nget, timeout)` | `epoll_wait(epfd, events, max, timeout)` |

#### 時刻取得

| Solaris | Linux |
|---------|-------|
| `gethrtime()` | `clock_gettime(CLOCK_MONOTONIC, &ts)` |
| `gethrvtime()` | `clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)` |

#### スレッド

| Solaris | Linux |
|---------|-------|
| `thr_create()` | `pthread_create()` |
| `thr_join()` | `pthread_join()` |
| `thr_self()` | `pthread_self()` |
| `mutex_init()` | `pthread_mutex_init()` |

---

## 8. テストコードがない状態での品質保証戦略

### 8.1 レイヤー1: 現行動作の記録

テストコードがないため、現行システムの振る舞い自体を「正解データ」として記録する。

- サーバーログの構造化収集（接続/切断、トランザクション、状態変更、DB更新等）
- ネットワークパケットキャプチャ（クライアント⇔サーバー間の通信記録）
- DB操作の記録（PL/SQLの実行結果、テーブル更新パターン）
- パフォーマンスベースライン（CPU使用率、メモリ使用量、レスポンスタイム、TPS）

### 8.2 レイヤー2: 差分比較テスト（Differential Testing）

Solaris版とLinux版を並行稼働させ、同じ入力に対する出力の差分を検出する。

```
[テスト用クライアント（自動操作）]
        │
        ├──→ [Solarisサーバー] → ログ/パケット/DB結果 ─┐
        │                                              ├→ 差分比較
        └──→ [Linuxサーバー]   → ログ/パケット/DB結果 ─┘
```

- テスト用クライアントで定型操作シーケンス（接続→操作→状態変更→切断等）を自動実行
- 両サーバーの出力を比較し、差異があれば調査
- 乱数シードを固定できれば、処理結果の完全一致も検証可能

### 8.3 レイヤー3: 段階的な自動テストの導入

移行と同時に、最もリスクの高い部分からテストを書く。優先順位:

1. Solaris固有APIを使っている箇所のユニットテスト（互換レイヤーのテスト）
2. データ永続化層（ユーザーデータの整合性）
3. 決済処理・取引等の金銭に関わるロジック
4. ネットワーク層（接続管理、パケット処理）

### 8.4 レイヤー4: 本番環境での段階的検証

- カナリアリリース: 1ノードだけLinuxに切り替え、問題がないか監視
- シャドウテスト: 本番トラフィックのコピーをLinuxサーバーに流し、結果を比較
- メトリクス監視: エラー率、レスポンスタイム、メモリ使用量の異常検知

### 8.5 レイヤー5: 既存QAチームの活用

人力QAは「テストがない」のではなく「自動化されていない」だけである。

- QAチームの既存テスト手順をドキュメント化
- Linux環境でのQAサイクルを実施
- エッジケース（高負荷時、長時間稼働、大量同時接続等）を重点的に確認

### 8.6 周辺言語・スクリプトの移行リスク（例）

Cコアの周辺には運用スクリプトやDB層言語が付随することが多い。以下は代表的な組み合わせの
例であり、実際の技術スタックに応じて置き換えて評価する。

| 言語カテゴリ | 例 | 移行リスク | 備考 |
|------|-----------|------|------|
| コア実装言語 | C/C++ | 高 | Solaris固有API、ビルドシステム変更、ロケール依存関数の対処 |
| DBストアドプロシージャ | PL/SQL, T-SQL | 中 | DB移行を伴わなければ低リスク |
| 運用スクリプト | Perl, Python | 低〜中 | パス・モジュール依存を確認。文字コード変換モジュール使用時はエンコーディング指定を確認 |
| シェルスクリプト | bash, ksh | 低 | Solaris固有コマンド（truss, pfiles等）の置き換え |
| 管理画面・周辺ツール | PHP, Ruby, Perl CGI | 中〜高 | メジャーバージョン差が大きい場合、言語仕様レベルで非互換が多く書き換えが必要になることがある。マルチバイト文字列設定の確認 |

---

## Appendix A: 移行の進め方（案）

### A.1 推奨移行方式: 互換レイヤー＋並行稼働

大規模・長期運用のコードベースでは一括書き換え方式はリスクが高いことが多く、段階的な
移行と並行稼働による検証を組み合わせるアプローチが基本になる。以下は分析フェーズで
実施する調査項目の例（対象システムの特徴に応じて増減する）:

```
フェーズ1: 静的解析・動的プロファイリング
├─ Solaris固有API使用箇所の特定（grep + 静的解析）
├─ y2k38-checkerによる2038年問題影響箇所の検出
├─ 実行時のシステムコールトレース（truss/dtrace）
│   → 実際に使われているコードパスの特定
├─ 永続化データのフォーマット調査（タイムスタンプ格納形式の特定。NFS等を使う場合はNFSバージョンも確認）
├─ 文字コード調査（ソースファイル・データのエンコーディング特定、ロケール依存関数の使用状況）
└─ 周辺言語（DB層・運用スクリプト等）の依存調査

フェーズ2: 互換レイヤー作成＋ビルド通し
├─ solaris_compat層の実装
├─ Amazon Linux上でビルドが通る状態にする
└─ Makefile/ビルドシステムの移行

フェーズ3: 並行稼働環境構築
├─ テスト用サーバーインスタンスをLinux上で起動
├─ 本番はSolarisのまま継続
└─ QA担当者がLinux環境で動作確認

フェーズ4: 段階的切り替え
├─ 負荷の低いノードからLinuxへ
├─ 問題なければ順次拡大
└─ Solarisへのロールバック手順を常に維持
```

### A.2 プランA: 段階的移行（推奨）⭐

**アプローチ**: 互換レイヤーを作成し、段階的に置き換え。分析・準備フェーズはA.1の内容に従う。

```
フェーズ1: 互換レイヤー作成
├─ solaris_compat.h/c を作成
├─ 頻出API（door, kstat等）のLinux実装
└─ 条件付きコンパイル (#ifdef __sun__)

フェーズ2: ビルド環境構築
├─ Amazon Linux上でビルド環境整備
├─ Makefile/CMake移行
├─ 依存パッケージインストール
└─ 64bit化問題の早期検出用GCC警告フラグ有効化:
    -Wpointer-to-int-cast -Wint-to-pointer-cast -Wformat -Wall -Wextra

フェーズ3: 段階的書き換え
├─ モジュール単位で互換レイヤー経由に変更
├─ 単体テスト実施
└─ 統合テスト

フェーズ4: 最適化
├─ 互換レイヤーを直接Linux APIに置き換え
└─ パフォーマンスチューニング
```

**メリット**: リスク低、並行稼働可能、ロールバック容易  
**デメリット**: 時間がかかる

> **注**: アプリケーションコードの書き換えのみを対象とし、インフラ移行（DTrace→eBPF、ZFS→ext4等）は含まない。インフラ含む全体工数は `solaris_linux_differences.md` の移行チェックリストを参照。

### A.3 プランB: 一括書き換え（アグレッシブ）

**アプローチ**: Solaris依存を一気に削除・置き換え

```
フェーズ1: 全体分析
├─ AIエージェントで全Solaris API使用箇所抽出
└─ 変換マッピング表作成

フェーズ2: 自動変換
├─ AIエージェントで一括置き換えスクリプト実行
├─ ビルドシステム変換
└─ 全ファイル一括変更

フェーズ3: 修正・テスト
├─ コンパイルエラー修正
├─ 実行時エラー対応
└─ 機能テスト
```

**メリット**: 短期間、技術的負債なし  
**デメリット**: 高リスク、並行稼働困難

### A.4 プランC: ハイブリッド（バランス型）

**アプローチ**: コア部分は互換レイヤー、周辺は直接書き換え

```
フェーズ1: 分類
├─ AIエージェントでコード分析
├─ 「コア機能」と「周辺機能」に分類
└─ 周辺: 直接書き換え / コア: 互換レイヤー

フェーズ2: 周辺機能移行
├─ ログ、設定読み込み等を直接Linux化
└─ 単体テスト

フェーズ3: コア機能互換化
├─ ビジネスロジック部分は互換レイヤー
└─ 統合テスト

フェーズ4: 段階的最適化
├─ 互換レイヤーを徐々に削減
└─ パフォーマンス検証
```

**メリット**: リスクと速度のバランス  
**デメリット**: 判断が必要

---

## 関連ドキュメント

- [solaris_linux_differences.md](./solaris_linux_differences.md) - Solaris x86とAmazon Linuxの包括的な差異リスト
  - 低レベルAPI差異（11項目）
  - システムレベル機能差異（10項目）
  - 優先度付き移行チェックリスト（推定工数付き）
- Apache Portable Runtime公式: https://apr.apache.org/
- libevent公式: https://libevent.org/

---

## 情報ソース

### 2038年問題
- [Year 2038 problem - Wikipedia](https://en.wikipedia.org/wiki/Year_2038_problem)
- [glibc Y2038 Proofness Design](https://sourceware.org/glibc/wiki/Y2038ProofnessDesign) - glibc 2.34+での`_TIME_BITS=64`対応
- [64-bit time_t for Linux/glibc (LWN.net)](https://lwn.net/Articles/643234/)
- [y2k38-checker](https://github.com/cysec-lab/y2k38-checker) - 立命館大学サイバーセキュリティ研究室によるC言語向け2038年問題検出ツール（Clang Static Analyzerプラグイン）
- [2038年問題とは？（SQAT.jp）](https://www.sqat.jp/kawaraban/33142/) - 2038年問題の解説、OS/ライブラリ対応状況、組み込み機器での対応事例
- [NFSv4 (RFC 7530)](https://www.rfc-editor.org/rfc/rfc7530) - NFSv4のnfstime4は符号付64bitで定義（2.2.1項参照）

### 32bit→64bit移行（ILP32→LP64）
- [64-Bit Transition Guide for Cocoa Touch (Apple)](https://developer.apple.com/library/archive/documentation/General/Conceptual/CocoaTouch64BitGuide/ConvertingYourAppto64-Bit/ConvertingYourAppto64-Bit.html) - ILP32→LP64の型変化の解説（概念はC/C++共通）
- [Converting 32-bit Applications Into 64-bit Applications (Oracle)](https://docs.oracle.com/cd/E19205-01/819-5267/bkafh/index.html) - Solaris環境での32bit→64bit移行ガイド

### 品質保証・テスト戦略
- [Differential Testing for Software (Microsoft Research)](https://www.microsoft.com/en-us/research/publication/differential-testing-for-software/) - 差分比較テストの学術的背景
- [Shadow Testing / Dark Launching (Martin Fowler)](https://martinfowler.com/bliki/DarkLaunching.html) - シャドウテスト・カナリアリリースの概念

### Solaris→Linux移行全般
- [Solaris to Linux Migration 2017 (Brendan Gregg)](https://www.brendangregg.com/blog/2017-09-05/solaris-to-linux-2017.html)
- [Comparison of Solaris OS and Linux for Application Developers (Oracle)](https://www.oracle.com/solaris/technologies/linux-app.html)

### Amazon Linux
- [Amazon Linux 2023 FAQs](https://aws.amazon.com/linux/amazon-linux-2023/faqs/)
- [Amazon Linux 2023 Package List](https://docs.aws.amazon.com/linux/al2023/release-notes/all-packages-AL2023.6.html)

### 周辺言語の移行（例: PHP）
- [Migrating from PHP 5.6.x to PHP 7.0.x](https://www.php.net/manual/en/migration70.php)
- [Migrating from PHP 7.4.x to PHP 8.0.x](https://www.php.net/manual/en/migration80.php)

### OSSライブラリ互換性
- [OpenSSL Migration Guide (1.1.1 to 3.0)](https://docs.openssl.org/3.0/man7/migration_guide/)
- [strlcpy added to glibc 2.38 (LWN.net)](https://lwn.net/Articles/934898/)
