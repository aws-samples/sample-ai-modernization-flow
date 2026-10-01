# Solaris x86 vs Amazon Linux Differences List

This document comprehensively summarizes the incompatible areas that need to be addressed when migrating from Solaris x86 to Amazon Linux.

---

## Table of Contents

1. [Low-Level API Differences](#1-low-level-api-differences)
2. [System-Level Feature Differences](#2-system-level-feature-differences)
3. [Prioritized Migration Checklist](#prioritized-migration-checklist)
4. [Information Sources](#information-sources)

---

## 1. Low-Level API Differences

### 1.1 Atomic Operations

**Purpose**: Indivisible variable operations in multi-threaded environments

**Conversion target**
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

**Pitfalls**
- Explicit memory order specification is required (Solaris does this implicitly)
- Return value difference: `atomic_add_32_nv()` returns the new value, `__atomic_fetch_add()` returns the old value
- Number of CAS operation arguments: Solaris takes 3 arguments, Linux takes 6 arguments
- CAS return value type: `atomic_cas_32()` returns the old value (`uint32_t`), whereas `__atomic_compare_exchange_n()` returns success/failure (`bool`). The old value is written back into the second argument

**Priority**: 🔴 High

---

### 1.2 Event-Driven I/O (Asynchronous I/O Multiplexing)

**Purpose**: Efficient monitoring of large numbers of sockets/file descriptors

**Conversion target**
```c
// Solaris: Event Ports
#include <port.h>
int port = port_create();
port_associate(port, PORT_SOURCE_FD, fd, POLLIN, NULL);
port_event_t events[MAX];
uint_t nget = 1;  // minimum number of events to wait for; on return holds the number retrieved
port_getn(port, events, MAX, &nget, &timeout);

// Linux: epoll
#include <sys/epoll.h>
int epfd = epoll_create1(EPOLL_CLOEXEC);
struct epoll_event ev = {.events = EPOLLIN, .data.fd = fd};
epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev);
struct epoll_event events[MAX];
int n = epoll_wait(epfd, events, MAX, timeout_ms);
```

**Pitfalls**
- Re-registration requirement: Solaris automatically deregisters (re-registration is mandatory), whereas epoll is persistent
- Timeout unit: Solaris uses `timespec` (seconds + nanoseconds), epoll uses an integer number of milliseconds
- Edge-triggered mode: must be explicitly specified in epoll via `EPOLLET`
- The data structure member names differ
- Specifying `EPOLL_CLOEXEC` is recommended (to prevent fd leakage in multi-process environments)

**Priority**: 🔴 High

---

### 1.3 High-Precision Time Retrieval

**Purpose**: High-precision timers for performance measurement and timeout calculations

**Conversion target**
```c
// Solaris
#include <sys/time.h>
hrtime_t start = gethrtime();  // In nanoseconds, uint64_t
hrtime_t elapsed = gethrtime() - start;

// Linux
#include <time.h>
struct timespec ts;
clock_gettime(CLOCK_MONOTONIC, &ts);
uint64_t ns = ts.tv_sec * 1000000000ULL + ts.tv_nsec;
```

**Pitfalls**
- Return value type: `gethrtime()` returns a direct nanosecond value, `clock_gettime()` returns a struct
- Overflow calculation: without using `1000000000ULL`, overflow occurs on 32-bit environments
- Clock ID: do not confuse `CLOCK_MONOTONIC` (monotonically increasing) with `CLOCK_REALTIME` (wall-clock time)

**Priority**: 🔴 High

---

### 1.4 Thread Operations

**Purpose**: Fundamentals of multi-threaded programming

**Conversion target**
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

**Pitfalls**
- Function signature: `thr_create()` takes 6 arguments, `pthread_create()` takes 4 arguments
- Stack size: Solaris specifies it directly via the second argument, pthread specifies it via `pthread_attr_t`
- Return value: `thr_join()` takes 3 arguments, `pthread_join()` takes 2 arguments

**Priority**: 🟡 Medium

---

### 1.5 Shared Memory / Semaphores

**Purpose**: Sharing memory regions between processes, mutual exclusion control

**Conversion target**
```c
// Solaris/Linux (basically the same POSIX API)
#include <sys/shm.h>
int shmid = shmget(key, size, IPC_CREAT | 0666);
void *ptr = shmat(shmid, NULL, 0);
```

**Pitfalls**
- Default size limit: Linux limits this via `/proc/sys/kernel/shmmax` (may be smaller than on Solaris)
- Segment deletion timing: the behavior of `shmctl(IPC_RMID)` differs subtly
- Named semaphore path: Solaris `/tmp/.SEMD*`, Linux `/dev/shm/sem.*`

**Priority**: 🟡 Medium

---

### 1.6 Signal Handling

**Purpose**: Asynchronous notification to processes

**Conversion target**
```c
// Solaris/Linux (nearly identical POSIX API)
#include <signal.h>
sigset_t set;
sigemptyset(&set);
sigaddset(&set, SIGTERM);
sigwait(&set, &sig);
```

**Pitfalls**
- Real-time signal range: the number of `SIGRTMIN` to `SIGRTMAX` differs
- `SA_RESTART`: the `sigaction()` flag behavior differs subtly

**Priority**: 🟡 Medium

---

### 1.7 Filesystem Operations

**Purpose**: Directory traversal, retrieving file attributes

**Conversion target**
```c
// Solaris
#include <sys/stat.h>
struct stat64 st;
stat64(path, &st);

// Linux
struct stat st;  // 64-bit by default (_FILE_OFFSET_BITS=64)
stat(path, &st);
```

**Pitfalls**
- 64-bit file support: Solaris requires the explicit `stat64()`, Linux requires the `-D_FILE_OFFSET_BITS=64` compile flag
- Extended attributes: Solaris's `attropen()` becomes `getxattr()`/`setxattr()` on Linux
- ACLs: the API structure differs between Solaris's `acl_get()` and Linux's `acl_get_file()`

**Priority**: 🟡 Medium

---

### 1.8 Networking (Sockets)

**Purpose**: TCP/UDP communication

**Conversion target**
- The basic socket API is common (POSIX-compliant)

**Pitfalls**
- Solaris-specific options: options such as `SO_EXCLBIND` are not available
- IPv6 support: the `sockaddr_in6` struct member names may differ subtly
- TCP_CORK vs TCP_NOPUSH: Linux uses `TCP_CORK`, Solaris uses `TCP_NOPUSH` (equivalent functionality)
- Error codes: how `EWOULDBLOCK` and `EAGAIN` are handled (they are the same value on Linux)

**Priority**: 🟢 Low

---

### 1.9 Process Management

**Purpose**: Process creation, termination waiting, resource limits

**Conversion target**
```c
// Solaris
#include <sys/procfs.h>
// Read /proc/<pid>/psinfo (struct format)

// Linux
#include <sys/resource.h>
// Read /proc/<pid>/stat (text format)
```

**Pitfalls**
- /proc filesystem: the format is completely different (Solaris uses structs, Linux uses text)
- `getrlimit()`: fundamentally the same, but Solaris's `RLIMIT_VMEM` is `RLIMIT_AS` on Linux

**Priority**: 🟡 Medium

---

### 1.10 Compiler / Build Environment

**Purpose**: Compilation, linking

**Conversion target**
```bash
# Solaris
cc -xO3 -m64 -mt -lpthread -lsocket -lnsl

# Linux
gcc -O3 -m64 -pthread -D_REENTRANT
```

**Pitfalls**
- Library splitting: Solaris's `-lsocket -lnsl` are unnecessary on Linux (integrated into libc)
- Thread flag: `-mt` (Solaris) vs `-pthread` (Linux)
- Inline assembly: Sun Studio syntax and GCC syntax differ
- Preprocessor macros: branch on `__sun` (Solaris) vs `__linux__` (Linux)

**Priority**: 🔴 High

---

### 1.11 Character Encoding / Locale

**Purpose**: Handling Japanese-language strings, locale configuration

**Conversion target**
```c
// Solaris: EUC-JP or Shift_JIS locale
setlocale(LC_ALL, "ja_JP.eucJP");   // or "ja_JP.PCK"

// Linux: UTF-8 by default
setlocale(LC_ALL, "ja_JP.UTF-8");
```

**Choosing a policy**: First decide whether to retain the application's internal character encoding or to unify on UTF-8 (including a staged unification) — for the options and trade-offs, see §5.1 of `longrun_server_migration_considerations.md`. The following are cautionary notes mainly for the case where you retain the internal character encoding (option B in the same §5.1).

**Pitfalls**
- Locale-dependent functions: if `setlocale(LC_CTYPE, "")` pulls in the OS's UTF-8 setting, functions such as `mbstowcs()`, `mblen()`, and `strcoll()` will misinterpret byte sequences in the existing encoding as UTF-8
- GCC's source interpretation: UTF-8 is assumed by default. Shift_JIS source files can trigger the second-byte `0x5C` problem (address this with `-finput-charset`)
- Locale name differences: Solaris's `ja_JP.PCK` becomes something like `ja_JP.sjis` on Linux (may not exist by default on Amazon Linux)
- `iconv` encoding names: Solaris's `PCK` → Linux's `SHIFT_JIS`
- Logging/operational tools: log output in the existing encoding may appear garbled in OS-side tools

**Priority**: 🔴 High (investigate usage of locale-dependent functions early in the migration and finalize the scope of remediation)

---

## 2. System-Level Feature Differences

### 2.1 Doors IPC (Inter-Process Communication)

**Purpose**: Solaris's proprietary high-speed inter-process communication mechanism

**Conversion target**
```c
// Solaris: Doors
#include <door.h>
int door_fd = door_create(server_proc, NULL, 0);
door_call(door_fd, &params);

// Linux: Unix Domain Sockets (closest alternative)
#include <sys/socket.h>
#include <sys/un.h>
int sock = socket(AF_UNIX, SOCK_STREAM, 0);
// bind, listen, accept, connect...
```

**Pitfalls**
- No direct alternative: Doors is a completely proprietary implementation
- Call semantics: Doors is function-call style (`door_call()` passes arguments and receives results as a synchronous call), while sockets send and receive data, so you must design the request/response format on the application side
- An architecture change is required

**Priority**: 🔴 High

**Reference**:
- [door_call(3C) - illumos](https://illumos.org/man/3C/door_call)
- [unix(7) - Linux manual page](https://man7.org/linux/man-pages/man7/unix.7.html)

---

### 2.2 Contract Filesystem (ctfs) - Process Contract Management

**Purpose**: Managing the lifecycle of process groups and event notification

**Conversion target**
```c
// Solaris: Process Contracts
#include <sys/contract.h>
#include <sys/ctfs.h>
int ctfd = open("/system/contract/process/template", O_RDWR);
ct_tmpl_set_critical(ctfd, CT_PR_EV_EXIT);

// Linux: cgroups v2
// Process group management via /sys/fs/cgroup/
```

**Pitfalls**
- Conceptual difference: Contracts are "contract"-based, cgroups are "resource limit"-based
- API structure: Solaris is filesystem-based, Linux uses cgroupfs + system calls
- Event notification: Contracts deliver the termination, core dump, etc. of member processes as individual events (you `poll(2)` the event endpoint and read with `ct_event_read()`). What cgroups v2 notifies is a state change such as `populated` in `cgroup.events` (poll/inotify); the termination of individual processes is not notified

**Priority**: 🟡 Medium

**Reference**:
- [contract(5) - illumos](https://illumos.org/man/5/contract)
- [Control Group v2 (Linux kernel documentation)](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)

---

### 2.3 kstat (Kernel Statistics)

**Purpose**: Retrieving internal kernel statistics from user space

**Conversion target**
```c
// Solaris: kstat
#include <kstat.h>
kstat_ctl_t *kc = kstat_open();
kstat_t *ksp = kstat_lookup(kc, "cpu", 0, "sys");
kstat_read(kc, ksp, NULL);

// Linux: /proc, /sys, sysfs
// /proc/stat, /proc/meminfo, /sys/class/net/*/statistics/
```

**Pitfalls**
- Structured data vs. text: kstat provides structs, Linux requires text parsing
- Statistical item differences: even for the same metric, the name and unit may differ
- Real-time consistency: kstat guarantees consistency, /proc is a snapshot at read time

**Priority**: 🟡 Medium

**Reference**: [Looking for kstat equivalents in Linux](https://stackoverflow.com/questions/5341549/looking-for-kstat-equivalents-in-linux)

---

### 2.4 DTrace (Dynamic Tracing)

**Purpose**: Tracing a running production system without downtime

**Conversion target**
```bash
# Solaris: DTrace
dtrace -n 'syscall::read:entry { @[execname] = count(); }'

# Linux: eBPF + bpftrace (closest alternative)
bpftrace -e 'tracepoint:syscalls:sys_enter_read { @[comm] = count(); }'

# Or SystemTap (older alternative)
stap -e 'probe syscall.read { stats[execname()] <<< 1 }'
```

**Pitfalls**
- Language syntax: the DTrace language and bpftrace are similar but not fully compatible
- Probe points: the namespaces differ (`syscall::read:entry` vs `tracepoint:syscalls:sys_enter_read`)
- Safety: DTrace is designed for production use; eBPF is also safe but depends on the kernel version
- Operational monitoring scripts require a full rewrite

**Priority**: 🔴 High

**References**: 
- [DTrace - Wikipedia](https://en.wikipedia.org/wiki/DTrace)
- [bpftrace (GitHub)](https://github.com/bpftrace/bpftrace)

---

### 2.5 RBAC (Role-Based Access Control)

**Purpose**: Splitting root privileges to delegate only specific administrative permissions

**Conversion target**
```bash
# Solaris: RBAC
usermod -P "Network Management" alice

# Linux: multiple alternative mechanisms
# 1. Capabilities (per-process privileges)
setcap cap_net_admin+ep /usr/bin/myapp

# 2. SELinux (Type Enforcement)
# 3. sudo + policy configuration
```

**Pitfalls**
- Granularity difference: Solaris's RBAC operates at the "role" level, Linux at the "capability" level
- Configuration method: Solaris uses a dedicated file, Linux uses a combination of capabilities/SELinux/sudo
- Auditing: Solaris has integrated auditing, Linux requires separate configuration via auditd

**Priority**: 🟢 Low

**Reference**: [Solaris RBAC Documentation](https://docs.oracle.com/cd/E19683-01/806-4078/6jd6cjs4o/index.html)

---

### 2.6 FMA (Fault Management Architecture)

**Purpose**: Automatic detection, diagnosis, and isolation of hardware faults

**Conversion target**
```bash
# Solaris: FMA
fmadm faulty
fmadm repair <UUID>

# Linux: rasdaemon + mcelog (partial alternative)
ras-mc-ctl --errors
mcelog --client
```

**Pitfalls**
- Automatic repair: FMA automatically takes components offline, Linux fundamentally requires manual intervention
- Diagnostic engine: FMA has sophisticated diagnostic logic, Linux performs simple logging
- Integration: FMA provides a unified interface, Linux is a combination of multiple tools

**Priority**: 🟡 Medium

**Reference**: [Oracle Solaris Fault Management Architecture](https://docs.oracle.com/cd/E26502_01/html/E29003/gliqg.html)

---

### 2.7 ZFS (Filesystem)

**Purpose**: Integrated volume management and filesystem

**Conversion target**
```bash
# Solaris: ZFS (native)
zpool create mypool /dev/sda
zfs create mypool/data

# Linux: alternatives
# 1. OpenZFS (licensing concerns)
# 2. Btrfs (similar functionality but less mature)
# 3. LVM + ext4/xfs (traditional, fewer features)
```

**Pitfalls**
- Licensing concerns: ZFS is CDDL-licensed, the Linux kernel is GPL-licensed (a legal gray area)
- Performance: OpenZFS on Linux can be slower than native
- Feature gaps: some Btrfs features are not implemented (e.g., deduplication)
- A data migration plan is essential

**Priority**: 🔴 High

**Reference**: [ZFS - Wikipedia](https://en.wikipedia.org/wiki/ZFS)

---

### 2.8 libumem (Memory Allocator)

**Purpose**: High-performance memory allocation library

**Conversion target**
```c
// Solaris: libumem
#include <umem.h>
void *ptr = umem_alloc(size, UMEM_DEFAULT);
umem_free(ptr, size);

// Linux: jemalloc (recommended)
#include <jemalloc/jemalloc.h>
void *ptr = malloc(size);  // overridden by jemalloc
```

**Pitfalls**
- Debugging features: libumem has them built in, jemalloc requires separate configuration
- Performance characteristics: the optimal allocator differs by workload
- Linking method: replacement requires `LD_PRELOAD`
- Performance testing is essential

**Priority**: 🟡 Medium

**Reference**: [Libumem - Wikipedia](https://en.wikipedia.org/wiki/Libumem)

---

### 2.9 Service Management (SMF → systemd)

**Purpose**: Daemonizing server applications; starting, stopping, and automatic restart

**Conversion target**
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

**SMF manifest → systemd unit file conversion example**

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

**Concept mapping table**

| SMF (Solaris) | systemd (Linux) | Notes |
|---|---|---|
| `svcadm enable` | `systemctl enable --now` | Persist + start immediately |
| `svcadm disable` | `systemctl disable --now` | |
| `svcs -a` | `systemctl list-units` | |
| `svcs -xv` (fault diagnosis) | `systemctl status` + `journalctl -u` | |
| SMF dependency | `After=` / `Requires=` / `Wants=` | |
| SMF restarter (automatic restart) | `Restart=on-failure` | |
| Process group tracking via Contracts | systemd's cgroup tracking | Automatic |
| `/var/svc/log/` | `journalctl -u <service>` | |

**Pitfalls**
- SMF manifests are XML, systemd unit files are INI format (completely different structure)
- SMF dependencies can be finely controlled via `require_all`/`optional_all`, etc., but systemd can express roughly the same via `Requires`/`Wants`/`After`
- Because systemd tracks processes via cgroups, it also serves as a Linux replacement for Solaris Contracts
- Log output: stdout/stderr are automatically captured by journald, so no application-side changes are required

**Priority**: 🔴 High (required for server startup)

---

### 2.10 libc ABI Differences (Binary Compatibility)

**Purpose**: Internal implementation of the C standard library

**Pitfalls**
- Binaries cannot be reused as-is: Solaris binaries will not run directly (recompilation is mandatory)
- Error codes: the same error name may have a different numeric value (compare by name such as `EAGAIN`, not by numeric value)

**Priority**: 🔴 High

**Reference**:
- [Comparison of Solaris OS and Linux for Application Developers (Oracle)](https://www.oracle.com/solaris/technologies/linux-app.html)
- [errno(3) - Linux manual page](https://man7.org/linux/man-pages/man3/errno.3.html)

---

## Prioritized Migration Checklist

### 🔴 High Priority (functional replacement mandatory)

| # | Category | Work Required | Estimated Effort |
|---|---------|---------|---------|
| 1 | Atomic operations | Rewrite to `__atomic_*`, specify memory order | 2-3 weeks |
| 2 | Event I/O | `port_*` → `epoll_*`, add re-registration logic | 3-4 weeks |
| 3 | Time retrieval | `gethrtime()` → `clock_gettime()`, struct conversion | 1 week |
| 4 | Doors IPC | Design change to Unix Domain Sockets | 4-6 weeks |
| 5 | ZFS | Migration to ext4/xfs, data migration plan | 6-8 weeks |
| 6 | DTrace | eBPF/bpftrace, rewrite monitoring scripts | 4-5 weeks |
| 7 | Build environment | Modify Makefile/CMake, resolve library dependencies | 2 weeks |
| 8 | libc ABI | Full recompilation, verify struct sizes | 1-2 weeks |
| 9 | Character encoding | Investigate/address locale-dependent functions, adjust build flags | 2-3 weeks |
| 10 | Service management | Convert SMF manifest → systemd unit file | 1 week |

**Subtotal**: 26-35 weeks

---

### 🟡 Medium Priority (affects performance/operations)

| # | Category | Work Required | Estimated Effort |
|---|---------|---------|---------|
| 11 | kstat | /proc, /sys parsing, rewrite monitoring scripts | 2-3 weeks |
| 12 | FMA | Introduce rasdaemon, change fault response procedures | 2 weeks |
| 13 | libumem | Introduce jemalloc, performance testing | 2 weeks |
| 14 | Contracts | cgroups design, change process management logic | 3 weeks |
| 15 | Threads | `thr_*` → `pthread_*`, argument adjustment | 1 week |
| 16 | Shared memory | Check size limits, adjust kernel parameters | 1 week |
| 17 | Signals | Check real-time signal range | 1 week |
| 18 | Filesystem | `stat64` → `stat`, change extended attribute API | 1 week |
| 19 | Process management | Change /proc format, rewrite parsing logic | 1 week |

**Subtotal**: 14-15 weeks

---

### 🟢 Low Priority (limited scope of impact)

| # | Category | Work Required | Estimated Effort |
|---|---------|---------|---------|
| 20 | RBAC | Design capabilities/SELinux, redesign policy | 2 weeks |
| 21 | Networking | Check socket options, unify error codes | 1 week |

**Subtotal**: 3 weeks

---

**Total**: 43-53 weeks (approximately 10-12 months)

---

## Recommended Migration Approach

### Plan A: Phased Migration (Recommended)

1. **Phase 1: Create Compatibility Layer** (4-6 weeks)
   - Create `compat_solaris.h`
   - Implement wrappers for high-priority APIs (Atomic, epoll, time)
   - Create unit tests

2. **Phase 2: Migrate Core Functionality** (8-12 weeks)
   - Design change from Doors to Unix Domain Sockets
   - Migrate DTrace to eBPF
   - Set up the build system

3. **Phase 3: Migrate System Functionality** (6-8 weeks)
   - Migrate ZFS data
   - Implement kstat/FMA alternatives
   - Rewrite monitoring scripts

4. **Phase 4: Integration Testing / Optimization** (4-6 weeks)
   - Performance testing (libumem → jemalloc)
   - Load testing
   - Security audit (RBAC → capabilities)

**Total**: 22-32 weeks (approximately 5-7 months) + buffer

> **Scope note**: This 22-32 week estimate is the effort for the recommended approach covering the application plus core infrastructure (Doors, DTrace, ZFS, build system). The theoretical total of all checklist items above is 43-53 weeks, but the effective duration is shorter because some items can be worked on in parallel.

---

## Information Sources

### Oracle Official Documentation
- [Comparison of Solaris OS and Linux for Application Developers](https://www.oracle.com/solaris/technologies/linux-app.html)
- [Solaris RBAC Documentation](https://docs.oracle.com/cd/E19683-01/806-4078/6jd6cjs4o/index.html)
- [Oracle Solaris Fault Management Architecture](https://docs.oracle.com/cd/E26502_01/html/E29003/gliqg.html)
- [Solaris kstat Facility](https://docs.oracle.com/cd/E19253-01/816-4854/6mb1o3bau/index.html)
- [DTrace by Example](https://www.oracle.com/solaris/technologies/dtrace-tutorial.html)

### AWS Official Documentation
- [Amazon Linux 2023 FAQs](https://aws.amazon.com/linux/amazon-linux-2023/faqs/)

### Technical Articles / Community
- [Solaris to Linux Migration 2017 (Brendan Gregg)](https://www.brendangregg.com/blog/2017-09-05/solaris-to-linux-2017.html)
- [Looking for kstat equivalents in Linux](https://stackoverflow.com/questions/5341549/looking-for-kstat-equivalents-in-linux)

### Manual Pages / Official Repositories
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

## Next Steps

1. Set up the actual codebase
2. Identify usage locations for each category (`grep`, static analysis tools)
3. Detail the migration plan based on priority
4. Begin designing/implementing the compatibility layer
5. Build a continuous integration testing environment
