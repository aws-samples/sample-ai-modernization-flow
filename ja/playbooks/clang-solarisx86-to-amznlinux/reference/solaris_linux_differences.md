# Solaris x86 と Amazon Linux の差異一覧

このドキュメントは、Solaris x86からAmazon Linuxへの移行時に対応が必要な非互換部分を包括的にまとめたものです。

---

## 目次

1. [低レベルAPI差異](#1-低レベルapi差異)
2. [システムレベル機能差異](#2-システムレベル機能差異)
3. [優先度付き移行チェックリスト](#優先度付き移行チェックリスト)
4. [情報ソース](#情報ソース)

---

## 1. 低レベルAPI差異

### 1.1 Atomic操作（アトミック演算）

**目的**: マルチスレッド環境での分割不可能な変数操作

**変換対象**
```c
// Solaris
#include <atomic.h>
uint32_t old = atomic_add_32_nv(&counter, 1);
atomic_cas_32(&flag, 0, 1);

// Linux
#include <stdatomic.h>
uint32_t old = __atomic_fetch_add(&counter, 1, __ATOMIC_SEQ_CST);
__atomic_compare_exchange_n(&flag, &expected, 1, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
```

**落とし穴**
- メモリオーダーの明示的指定が必要（Solarisは暗黙的）
- 戻り値の違い: `atomic_add_32_nv()`は新値、`__atomic_fetch_add()`は旧値
- CAS操作の引数数: Solaris 3引数、Linux 6引数
- CAS戻り値の型: `atomic_cas_32()`は旧値(`uint32_t`)を返すが、`__atomic_compare_exchange_n()`は成否(`bool`)を返す。旧値は第2引数に書き戻される

**優先度**: 🔴 高

---

### 1.2 イベント駆動I/O（非同期I/O多重化）

**目的**: 多数のソケット/ファイルディスクリプタの効率的監視

**変換対象**
```c
// Solaris: Event Ports
#include <port.h>
int port = port_create();
port_associate(port, PORT_SOURCE_FD, fd, POLLIN, NULL);
port_event_t events[MAX];
uint_t nget = 1;  // 最低限待つイベント数。戻り時に取得件数が入る
port_getn(port, events, MAX, &nget, &timeout);

// Linux: epoll
#include <sys/epoll.h>
int epfd = epoll_create1(EPOLL_CLOEXEC);
struct epoll_event ev = {.events = EPOLLIN, .data.fd = fd};
epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev);
struct epoll_event events[MAX];
int n = epoll_wait(epfd, events, MAX, timeout_ms);
```

**落とし穴**
- 再登録の必要性: Solarisは自動解除（再登録必須）、epollは永続的
- タイムアウト単位: Solaris `timespec`（秒+ナノ秒）、epoll ミリ秒整数
- エッジトリガー: epollは`EPOLLET`で明示指定
- データ構造のメンバー名が異なる
- `EPOLL_CLOEXEC`の指定を推奨（マルチプロセス環境でのfd漏洩防止）

**優先度**: 🔴 高

---

### 1.3 高精度時刻取得

**目的**: パフォーマンス測定、タイムアウト計算用の高精度タイマー

**変換対象**
```c
// Solaris
#include <sys/time.h>
hrtime_t start = gethrtime();  // ナノ秒単位、uint64_t
hrtime_t elapsed = gethrtime() - start;

// Linux
#include <time.h>
struct timespec ts;
clock_gettime(CLOCK_MONOTONIC, &ts);
uint64_t ns = ts.tv_sec * 1000000000ULL + ts.tv_nsec;
```

**落とし穴**
- 戻り値の型: `gethrtime()`は直接ナノ秒値、`clock_gettime()`は構造体
- オーバーフロー計算: `1000000000ULL`を使わないと32bit環境で桁あふれ
- クロックID: `CLOCK_MONOTONIC`（単調増加）と`CLOCK_REALTIME`（実時刻）を混同しない

**優先度**: 🔴 高

---

### 1.4 スレッド操作

**目的**: マルチスレッドプログラミングの基本

**変換対象**
```c
// Solaris
#include <thread.h>
thread_t tid;
thr_create(NULL, 0, func, arg, 0, &tid);
thr_join(tid, NULL, NULL);

// Linux
#include <pthread.h>
pthread_t tid;
pthread_create(&tid, NULL, func, arg);
pthread_join(tid, NULL);
```

**落とし穴**
- 関数シグネチャ: `thr_create()` 6引数、`pthread_create()` 4引数
- スタックサイズ: Solarisは第2引数で直接指定、pthreadは`pthread_attr_t`経由
- 戻り値: `thr_join()` 3引数、`pthread_join()` 2引数

**優先度**: 🟡 中

---

### 1.5 共有メモリ・セマフォ

**目的**: プロセス間でメモリ領域を共有、排他制御

**変換対象**
```c
// Solaris/Linux（基本的に同じPOSIX API）
#include <sys/shm.h>
int shmid = shmget(key, size, IPC_CREAT | 0666);
void *ptr = shmat(shmid, NULL, 0);
```

**落とし穴**
- デフォルトサイズ制限: Linuxは`/proc/sys/kernel/shmmax`で制限（Solarisより小さい場合あり）
- セグメント削除タイミング: `shmctl(IPC_RMID)`の挙動が微妙に異なる
- 名前付きセマフォパス: Solaris `/tmp/.SEMD*`、Linux `/dev/shm/sem.*`

**優先度**: 🟡 中

---

### 1.6 シグナル処理

**目的**: プロセスへの非同期通知

**変換対象**
```c
// Solaris/Linux（ほぼ同じPOSIX API）
#include <signal.h>
sigset_t set;
sigemptyset(&set);
sigaddset(&set, SIGTERM);
sigwait(&set, &sig);
```

**落とし穴**
- リアルタイムシグナル範囲: `SIGRTMIN`～`SIGRTMAX`の数が異なる
- `SA_RESTART`: `sigaction()`フラグ挙動が微妙に違う

**優先度**: 🟡 中

---

### 1.7 ファイルシステム操作

**目的**: ディレクトリ走査、ファイル属性取得

**変換対象**
```c
// Solaris
#include <sys/stat.h>
struct stat64 st;
stat64(path, &st);

// Linux
struct stat st;  // デフォルトで64bit（_FILE_OFFSET_BITS=64）
stat(path, &st);
```

**落とし穴**
- 64bitファイル対応: Solarisは`stat64()`明示、Linuxは`-D_FILE_OFFSET_BITS=64`コンパイルフラグ
- 拡張属性: Solarisの`attropen()`はLinuxでは`getxattr()`/`setxattr()`
- ACL: Solarisの`acl_get()`とLinuxの`acl_get_file()`でAPI体系が異なる

**優先度**: 🟡 中

---

### 1.8 ネットワーク（ソケット）

**目的**: TCP/UDP通信

**変換対象**
- 基本的なソケットAPIは共通（POSIX準拠）

**落とし穴**
- Solaris独自オプション: `SO_EXCLBIND`などは使えない
- IPv6対応: `sockaddr_in6`の構造体メンバー名が微妙に違う場合あり
- TCP_CORK vs TCP_NOPUSH: Linuxは`TCP_CORK`、Solarisは`TCP_NOPUSH`（同等機能）
- エラーコード: `EWOULDBLOCK`と`EAGAIN`の扱い（Linuxでは同値）

**優先度**: 🟢 低

---

### 1.9 プロセス管理

**目的**: プロセス生成、終了待機、リソース制限

**変換対象**
```c
// Solaris
#include <sys/procfs.h>
// /proc/<pid>/psinfo を読む（構造体形式）

// Linux
#include <sys/resource.h>
// /proc/<pid>/stat を読む（テキスト形式）
```

**落とし穴**
- /procファイルシステム: フォーマットが全く異なる（Solarisは構造体、Linuxはテキスト）
- `getrlimit()`: 基本は同じだが`RLIMIT_VMEM`（Solaris）は`RLIMIT_AS`（Linux）

**優先度**: 🟡 中

---

### 1.10 コンパイラ・ビルド環境

**目的**: コンパイル、リンク

**変換対象**
```bash
# Solaris
cc -xO3 -m64 -mt -lpthread -lsocket -lnsl

# Linux
gcc -O3 -m64 -pthread -D_REENTRANT
```

**落とし穴**
- ライブラリ分割: Solarisの`-lsocket -lnsl`はLinuxでは不要（libcに統合）
- スレッドフラグ: `-mt`（Solaris）vs `-pthread`（Linux）
- インラインアセンブリ: Sun Studio構文とGCC構文が異なる
- プリプロセッサマクロ: `__sun`（Solaris）、`__linux__`（Linux）で条件分岐

**優先度**: 🔴 高

---

### 1.11 文字コード・ロケール

**目的**: 日本語文字列の処理、ロケール設定

**変換対象**
```c
// Solaris: EUC-JPまたはShift_JISロケール
setlocale(LC_ALL, "ja_JP.eucJP");   // または "ja_JP.PCK"

// Linux: UTF-8がデフォルト
setlocale(LC_ALL, "ja_JP.UTF-8");
```

**方針の選択**: アプリケーション内部の文字コードを維持するか、UTF-8へ統一するか（段階的な統一を含む）を先に決める（選択肢とトレードオフは `longrun_server_migration_considerations.md` §5.1 を参照）。以下は主に内部の文字コードを維持する場合（同 §5.1 の選択肢B）の注意点。

**落とし穴**
- ロケール依存関数: `setlocale(LC_CTYPE, "")` でOS側のUTF-8を取り込むと、`mbstowcs()`, `mblen()`, `strcoll()`等が既存エンコーディングのバイト列をUTF-8として誤解釈する
- GCCのソース解釈: デフォルトUTF-8前提。Shift_JISソースでは2バイト目`0x5C`問題あり（`-finput-charset`で対処）
- ロケール名の違い: Solarisの`ja_JP.PCK`はLinuxでは`ja_JP.sjis`等（Amazon Linuxにデフォルトで存在しない場合あり）
- `iconv`のエンコーディング名: Solarisの`PCK` → Linuxの`SHIFT_JIS`
- ログ・運用ツール: 既存エンコーディングのログ出力はOS側ツールで文字化け

**優先度**: 🔴 高（移行の初期段階でロケール依存関数の使用状況を調査し、対処範囲を確定する）

---

## 2. システムレベル機能差異

### 2.1 Doors IPC（プロセス間通信）

**目的**: Solaris独自の高速プロセス間通信メカニズム

**変換対象**
```c
// Solaris: Doors
#include <door.h>
int door_fd = door_create(server_proc, NULL, 0);
door_call(door_fd, &params);

// Linux: Unix Domain Sockets（最も近い代替）
#include <sys/socket.h>
#include <sys/un.h>
int sock = socket(AF_UNIX, SOCK_STREAM, 0);
// bind, listen, accept, connect...
```

**落とし穴**
- 直接の代替なし: Doorsは完全に独自実装
- 呼び出しセマンティクス: Doorsは関数呼び出し型（`door_call()` で引数を渡し、結果を受け取る同期呼び出し）、ソケットはデータの送受信のため、要求・応答の形式をアプリケーション側で設計する必要がある
- アーキテクチャ変更必須

**優先度**: 🔴 高

**参考**:
- [door_call(3C) - illumos](https://illumos.org/man/3C/door_call)
- [unix(7) - Linux manual page](https://man7.org/linux/man-pages/man7/unix.7.html)

---

### 2.2 Contract Filesystem (ctfs) - プロセス契約管理

**目的**: プロセスグループの生存管理とイベント通知

**変換対象**
```c
// Solaris: Process Contracts
#include <sys/contract.h>
#include <sys/ctfs.h>
int ctfd = open("/system/contract/process/template", O_RDWR);
ct_tmpl_set_critical(ctfd, CT_PR_EV_EXIT);

// Linux: cgroups v2
// /sys/fs/cgroup/ 経由でプロセスグループ管理
```

**落とし穴**
- 概念の違い: Contractsは「契約」ベース、cgroupsは「リソース制限」ベース
- API体系: Solarisはファイルシステム経由、Linuxはcgroupfs + システムコール
- イベント通知: Contractsはメンバープロセスの終了・コアダンプ等を個別のイベントとして配送する（イベントエンドポイントを `poll(2)` し `ct_event_read()` で読む）。cgroups v2 が通知するのは `cgroup.events` の `populated` 等の状態変化（poll/inotify）であり、個々のプロセス終了は通知されない

**優先度**: 🟡 中

**参考**:
- [contract(5) - illumos](https://illumos.org/man/5/contract)
- [Control Group v2 (Linux kernel documentation)](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)

---

### 2.3 kstat（カーネル統計情報）

**目的**: カーネル内部の統計情報をユーザー空間から取得

**変換対象**
```c
// Solaris: kstat
#include <kstat.h>
kstat_ctl_t *kc = kstat_open();
kstat_t *ksp = kstat_lookup(kc, "cpu", 0, "sys");
kstat_read(kc, ksp, NULL);

// Linux: /proc, /sys, sysfs
// /proc/stat, /proc/meminfo, /sys/class/net/*/statistics/
```

**落とし穴**
- 構造化データ vs テキスト: kstatは構造体、Linuxはテキストパース必要
- 統計項目の違い: 同じメトリクスでも名前・単位が異なる
- リアルタイム性: kstatは一貫性保証、/procは読み取り時点のスナップショット

**優先度**: 🟡 中

**参考**: [Looking for kstat equivalents in Linux](https://stackoverflow.com/questions/5341549/looking-for-kstat-equivalents-in-linux)

---

### 2.4 DTrace（動的トレーシング）

**目的**: 本番環境で動作中のシステムを無停止でトレース

**変換対象**
```bash
# Solaris: DTrace
dtrace -n 'syscall::read:entry { @[execname] = count(); }'

# Linux: eBPF + bpftrace（最も近い代替）
bpftrace -e 'tracepoint:syscalls:sys_enter_read { @[comm] = count(); }'

# または SystemTap（古い代替）
stap -e 'probe syscall.read { stats[execname()] <<< 1 }'
```

**落とし穴**
- 言語構文: DTrace言語とbpftraceは似ているが完全互換ではない
- プローブポイント: 名前空間が異なる（`syscall::read:entry` vs `tracepoint:syscalls:sys_enter_read`）
- 安全性: DTraceは本番環境前提、eBPFも安全だがカーネルバージョン依存
- 運用監視スクリプトの全面書き換えが必要

**優先度**: 🔴 高

**参考**: 
- [DTrace - Wikipedia](https://en.wikipedia.org/wiki/DTrace)
- [bpftrace (GitHub)](https://github.com/bpftrace/bpftrace)

---

### 2.5 RBAC（Role-Based Access Control）

**目的**: rootを分割して、特定の管理権限だけを委譲

**変換対象**
```bash
# Solaris: RBAC
usermod -P "Network Management" alice

# Linux: 複数の代替手段
# 1. Capabilities（プロセス単位の権限）
setcap cap_net_admin+ep /usr/bin/myapp

# 2. SELinux（Type Enforcement）
# 3. sudo + ポリシー設定
```

**落とし穴**
- 粒度の違い: SolarisのRBACは「役割」単位、Linuxは「能力」単位
- 設定方法: Solarisは専用ファイル、Linuxはcapabilities/SELinux/sudoの組み合わせ
- 監査: Solarisは統合監査、Linuxはauditdで別途設定

**優先度**: 🟢 低

**参考**: [Solaris RBAC Documentation](https://docs.oracle.com/cd/E19683-01/806-4078/6jd6cjs4o/index.html)

---

### 2.6 FMA（Fault Management Architecture）

**目的**: ハードウェア障害の自動検出・診断・隔離

**変換対象**
```bash
# Solaris: FMA
fmadm faulty
fmadm repair <UUID>

# Linux: rasdaemon + mcelog（部分的代替）
ras-mc-ctl --errors
mcelog --client
```

**落とし穴**
- 自動修復: FMAは自動でコンポーネントをオフライン化、Linuxは手動対応が基本
- 診断エンジン: FMAは高度な診断ロジック、Linuxは単純なログ記録
- 統合性: FMAは統一インターフェース、Linuxは複数ツールの組み合わせ

**優先度**: 🟡 中

**参考**: [Oracle Solaris Fault Management Architecture](https://docs.oracle.com/cd/E26502_01/html/E29003/gliqg.html)

---

### 2.7 ZFS（ファイルシステム）

**目的**: 統合ボリューム管理・ファイルシステム

**変換対象**
```bash
# Solaris: ZFS（ネイティブ）
zpool create mypool /dev/sda
zfs create mypool/data

# Linux: 代替手段
# 1. OpenZFS（ライセンス問題あり）
# 2. Btrfs（機能は近いが成熟度低い）
# 3. LVM + ext4/xfs（従来型、機能劣る）
```

**落とし穴**
- ライセンス問題: ZFSはCDDL、LinuxカーネルはGPL（法的グレーゾーン）
- パフォーマンス: OpenZFS on Linuxはネイティブより遅い場合あり
- 機能差: Btrfsは一部機能未実装（重複排除など）
- データ移行計画が必須

**優先度**: 🔴 高

**参考**: [ZFS - Wikipedia](https://en.wikipedia.org/wiki/ZFS)

---

### 2.8 libumem（メモリアロケータ）

**目的**: 高性能なメモリ割り当てライブラリ

**変換対象**
```c
// Solaris: libumem
#include <umem.h>
void *ptr = umem_alloc(size, UMEM_DEFAULT);
umem_free(ptr, size);

// Linux: jemalloc（推奨）
#include <jemalloc/jemalloc.h>
void *ptr = malloc(size);  // jemallocでオーバーライド
```

**落とし穴**
- デバッグ機能: libumemは組み込み、jemallocは別途設定必要
- パフォーマンス特性: アロケータごとに最適なワークロードが異なる
- リンク方法: `LD_PRELOAD`での置き換えが必要
- 性能テストが必須

**優先度**: 🟡 中

**参考**: [Libumem - Wikipedia](https://en.wikipedia.org/wiki/Libumem)

---

### 2.9 サービス管理（SMF → systemd）

**目的**: サーバーアプリケーションのデーモン化、起動・停止・自動再起動

**変換対象**
```bash
# Solaris: SMF (Service Management Facility)
svcadm enable svc:/application/myapp:default
svcadm disable svc:/application/myapp:default
svcadm restart svc:/application/myapp:default
svcs -xv svc:/application/myapp:default

# Linux: systemd
systemctl enable --now myapp-server
systemctl disable --now myapp-server
systemctl restart myapp-server
systemctl status myapp-server && journalctl -u myapp-server
```

**SMF manifest → systemd unit file 変換例**

```ini
# /etc/systemd/system/myapp-server.service
[Unit]
Description=Application Server
After=network.target nfs-client.target
Wants=nfs-client.target

[Service]
Type=simple
User=myapp
Group=myapp
WorkingDirectory=/opt/myapp
ExecStart=/opt/myapp/bin/server -c /opt/myapp/etc/server.conf
ExecStop=/bin/kill -TERM $MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=65536
LimitCORE=infinity
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target
```

**概念対応表**

| SMF (Solaris) | systemd (Linux) | 備考 |
|---|---|---|
| `svcadm enable` | `systemctl enable --now` | 永続化＋即時起動 |
| `svcadm disable` | `systemctl disable --now` | |
| `svcs -a` | `systemctl list-units` | |
| `svcs -xv`（障害診断） | `systemctl status` + `journalctl -u` | |
| SMF dependency | `After=` / `Requires=` / `Wants=` | |
| SMF restarter（自動再起動） | `Restart=on-failure` | |
| Contract によるプロセスグループ追跡 | systemd の cgroup 追跡 | 自動 |
| `/var/svc/log/` | `journalctl -u <service>` | |

**落とし穴**
- SMF manifest はXML、systemd unit file はINI形式（構造が全く異なる）
- SMFの依存関係は `require_all`/`optional_all` 等で細かく制御できるが、systemdは `Requires`/`Wants`/`After` で概ね表現可能
- systemdはプロセスをcgroupで追跡するため、Solaris ContractのLinux代替としても機能する
- ログ出力: stdout/stderrは自動でjournaldに取り込まれるため、アプリケーション側の変更は不要

**優先度**: 🔴 高（サーバー起動に必須）

---

### 2.10 libc ABI差異（バイナリ互換性）

**目的**: C標準ライブラリの内部実装

**落とし穴**
- バイナリ再利用不可: Solarisバイナリはそのまま動かない（再コンパイル必須）
- エラーコード: 同じエラー名でも数値が異なる場合あり（数値ではなく `EAGAIN` 等の名前で比較する）

**優先度**: 🔴 高

**参考**:
- [Comparison of Solaris OS and Linux for Application Developers (Oracle)](https://www.oracle.com/solaris/technologies/linux-app.html)
- [errno(3) - Linux manual page](https://man7.org/linux/man-pages/man3/errno.3.html)

---

## 優先度付き移行チェックリスト

### 🔴 高優先度（機能的に代替必須）

| # | カテゴリ | 対応内容 | 推定工数 |
|---|---------|---------|---------|
| 1 | Atomic操作 | `__atomic_*`への書き換え、メモリオーダー指定 | 2-3週 |
| 2 | イベントI/O | `port_*` → `epoll_*`、再登録ロジック追加 | 3-4週 |
| 3 | 時刻取得 | `gethrtime()` → `clock_gettime()`、構造体変換 | 1週 |
| 4 | Doors IPC | Unix Domain Socketsへの設計変更 | 4-6週 |
| 5 | ZFS | ext4/xfs移行、データ移行計画 | 6-8週 |
| 6 | DTrace | eBPF/bpftrace、監視スクリプト書き換え | 4-5週 |
| 7 | ビルド環境 | Makefile/CMake修正、ライブラリ依存解決 | 2週 |
| 8 | libc ABI | 全面再コンパイル、構造体サイズ検証 | 1-2週 |
| 9 | 文字コード | ロケール依存関数の調査・対処、ビルドフラグ調整 | 2-3週 |
| 10 | サービス管理 | SMF manifest → systemd unit file変換 | 1週 |

**小計**: 26-35週

---

### 🟡 中優先度（性能・運用に影響）

| # | カテゴリ | 対応内容 | 推定工数 |
|---|---------|---------|---------|
| 11 | kstat | /proc, /sysパース、監視スクリプト書き換え | 2-3週 |
| 12 | FMA | rasdaemon導入、障害対応手順変更 | 2週 |
| 13 | libumem | jemalloc導入、性能テスト | 2週 |
| 14 | Contracts | cgroups設計、プロセス管理ロジック変更 | 3週 |
| 15 | スレッド | `thr_*` → `pthread_*`、引数調整 | 1週 |
| 16 | 共有メモリ | サイズ制限確認、カーネルパラメータ調整 | 1週 |
| 17 | シグナル | リアルタイムシグナル範囲確認 | 1週 |
| 18 | ファイルシステム | `stat64` → `stat`、拡張属性API変更 | 1週 |
| 19 | プロセス管理 | /proc形式変更、パースロジック書き換え | 1週 |

**小計**: 14-15週

---

### 🟢 低優先度（影響範囲限定的）

| # | カテゴリ | 対応内容 | 推定工数 |
|---|---------|---------|---------|
| 20 | RBAC | capabilities/SELinux設計、ポリシー再設計 | 2週 |
| 21 | ネットワーク | ソケットオプション確認、エラーコード統一 | 1週 |

**小計**: 3週

---

**総計**: 43-53週（約10-12ヶ月）

---

## 推奨移行アプローチ

### プランA: 段階的移行（推奨）

1. **フェーズ1: 互換レイヤー作成**（4-6週）
   - `compat_solaris.h`作成
   - 高優先度API（Atomic、epoll、時刻）のラッパー実装
   - 単体テスト作成

2. **フェーズ2: コア機能移行**（8-12週）
   - Doors → Unix Domain Sockets設計変更
   - DTrace → eBPF移行
   - ビルドシステム整備

3. **フェーズ3: システム機能移行**（6-8週）
   - ZFSデータ移行
   - kstat/FMA代替実装
   - 監視スクリプト書き換え

4. **フェーズ4: 統合テスト・最適化**（4-6週）
   - 性能テスト（libumem → jemalloc）
   - 負荷テスト
   - セキュリティ監査（RBAC → capabilities）

**合計**: 22-32週（約5-7ヶ月）+ バッファ

> **スコープ注記**: この22-32週はアプリケーション＋コアインフラ（Doors、DTrace、ZFS、ビルドシステム）を対象とした推奨アプローチの工数。上記チェックリスト全項目の理論的合計は43-53週だが、一部項目は並行実施可能なため実効期間は短縮される。

---

## 情報ソース

### Oracle公式ドキュメント
- [Comparison of Solaris OS and Linux for Application Developers](https://www.oracle.com/solaris/technologies/linux-app.html)
- [Solaris RBAC Documentation](https://docs.oracle.com/cd/E19683-01/806-4078/6jd6cjs4o/index.html)
- [Oracle Solaris Fault Management Architecture](https://docs.oracle.com/cd/E26502_01/html/E29003/gliqg.html)
- [Solaris kstat Facility](https://docs.oracle.com/cd/E19253-01/816-4854/6mb1o3bau/index.html)
- [DTrace by Example](https://www.oracle.com/solaris/technologies/dtrace-tutorial.html)

### AWS公式ドキュメント
- [Amazon Linux 2023 FAQs](https://aws.amazon.com/linux/amazon-linux-2023/faqs/)

### 技術記事・コミュニティ
- [Solaris to Linux Migration 2017 (Brendan Gregg)](https://www.brendangregg.com/blog/2017-09-05/solaris-to-linux-2017.html)
- [Looking for kstat equivalents in Linux](https://stackoverflow.com/questions/5341549/looking-for-kstat-equivalents-in-linux)

### マニュアルページ・公式リポジトリ
- [door_call(3C) - illumos](https://illumos.org/man/3C/door_call)
- [contract(5) - illumos](https://illumos.org/man/5/contract)
- [unix(7) - Linux manual page](https://man7.org/linux/man-pages/man7/unix.7.html)
- [errno(3) - Linux manual page](https://man7.org/linux/man-pages/man3/errno.3.html)
- [Control Group v2 (Linux kernel documentation)](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)
- [bpftrace (GitHub)](https://github.com/bpftrace/bpftrace)

### Wikipedia
- [DTrace - Wikipedia](https://en.wikipedia.org/wiki/DTrace)
- [ZFS - Wikipedia](https://en.wikipedia.org/wiki/ZFS)
- [Libumem - Wikipedia](https://en.wikipedia.org/wiki/Libumem)

---

## 次のステップ

1. 実際のコードベースを配置
2. 各カテゴリの使用箇所を特定（`grep`、静的解析ツール）
3. 優先度に基づいて移行計画を詳細化
4. 互換レイヤーの設計・実装開始
5. 継続的な統合テスト環境構築
