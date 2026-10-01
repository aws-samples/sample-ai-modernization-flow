# Long-Running Server Application Solaris x86 → Amazon Linux Migration Considerations

**Note**: This document targets migration from Solaris x86 (32bit) to Amazon Linux (x86-64 architecture).

---

## Table of Contents

1. [Common Patterns Encountered in Solaris Migration](#1-common-patterns-encountered-in-solaris-migration)
2. [Organizing the Required Conversions](#2-organizing-the-required-conversions)
3. [64bit Conversion Considerations](#3-64bit-conversion-considerations)
4. [Addressing the Year 2038 Problem](#4-addressing-the-year-2038-problem)
5. [Character Encoding and Locale Handling](#5-character-encoding-and-locale-handling)
6. [Dependent Library Update Risks](#6-dependent-library-update-risks)
7. [Compatibility Layer Design](#7-compatibility-layer-design)
8. [Quality Assurance Strategy Without Test Code](#8-quality-assurance-strategy-without-test-code)
- [Appendix A: Proposed Migration Approach](#appendix-a-proposed-migration-approach)
- [Related Documents](#related-documents)
- [Information Sources](#information-sources)
- [Update History](#update-history)

---

## 1. Common Patterns Encountered in Solaris Migration

The following are characteristics commonly encountered in practice when migrating C/C++ Solaris server
applications to Amazon Linux, which tend to cause problems downstream if overlooked. During the
analysis phase, check which of these apply to your own system and focus on the corresponding chapters.

| Characteristic | Consequence if Overlooked | Related Chapter |
|------|---------------------|--------|
| Operating as a 32bit binary | Postponing 64bit conversion means work such as struct changes must be done twice | [Chapter 3](#3-64bit-conversion-considerations) |
| Persisting or transmitting/receiving data that includes time_t | The Year 2038 problem surfaces after going into production | [Chapter 4](#4-addressing-the-year-2038-problem) |
| Maintained over a long operational period (5+ years) | Solaris-specific implicit assumptions accumulate, causing unexpected problems during migration | General |
| Stateful (holds connection state/sessions in memory) | Designing procedures for parallel operation and switchover between the Solaris and Linux versions becomes difficult | [Chapter 8](#8-quality-assurance-strategy-without-test-code) |
| Uses non-UTF-8 character encoding internally (EUC-JP, Shift_JIS, etc.) | Differences in locale-dependent function behavior cause data corruption or display corruption | [Chapter 5](#5-character-encoding-and-locale-handling) |
| Has not upgraded dependent library versions for a long time since introduction | High likelihood that the API/behavior has changed significantly in the latest version | [Chapter 6](#6-dependent-library-update-risks) |
| Automated tests are insufficient or nonexistent | No means to verify migration correctness; regressions end up being discovered in production | [Chapter 8](#8-quality-assurance-strategy-without-test-code) |
| Large-scale codebase (hundreds of thousands of lines or more) | High risk with a big-bang rewrite; a phased migration design is needed | [Appendix A](#appendix-a-proposed-migration-approach) |

Chapters for characteristics that do not apply may be skipped.

---

## 2. Organizing the Required Conversions

### 2.1 System Call / API Differences

| Category | Solaris | Linux |
|---------|---------|-------|
| Thread library | Solaris threads | POSIX threads (pthread) |
| Event-driven I/O | `port_*()` (event ports) | `epoll_*()` |
| Atomic operations | `atomic_*()` (atomic.h) | GCC builtins (`__atomic_*`, `__sync_*`) |
| Time retrieval | `gethrtime()` | `clock_gettime(CLOCK_MONOTONIC)` |
| Inter-process communication | `door_*()` | Unix domain sockets / shared memory |

### 2.2 Library Dependencies

| Solaris | Linux |
|---------|-------|
| libthread/libpthread | glibc pthread (integrated) |
| libnsl, libsocket | glibc (integrated, only linking changes) |
| libkstat | Implementation via `/proc`, `/sys` |
| libdl | glibc dlopen/dlsym |

### 2.3 Compiler / Build Environment

| Solaris | Linux |
|---------|-------|
| Sun Studio/Oracle Solaris Studio | GCC/Clang |
| `-mt` | `-pthread` |
| `-KPIC` | `-fPIC` |
| `CC=cc` | `CC=gcc` |

GCC warning flags for early detection of 64bit conversion issues:
```
-Wpointer-to-int-cast -Wint-to-pointer-cast -Wformat -Wall -Wextra
```

### 2.4 Filesystem / Paths

- `/usr/ucb/*` → standard Linux commands
- `/opt/csw/*` (OpenCSW) → Amazon Linux packages
- `/devices/*` → `/dev/*`, `/sys/*`

---

## 3. 64bit Conversion Considerations

### 3.1 Type Changes from ILP32 to LP64

Perform 64bit conversion at the same time as the Solaris migration (doing them separately means work such as struct size changes must be done twice).

Types that change when migrating from ILP32 (32bit) to LP64 (64bit):

| Type | 32bit | 64bit | Impact |
|---|-------|-------|------|
| `int` | 4 bytes | 4 bytes | No change |
| `long` | 4 bytes | 8 bytes | Requires attention |
| `pointer` | 4 bytes | 8 bytes | Requires attention |
| `time_t` | 4 bytes | 8 bytes | Resolves the Year 2038 problem |
| `size_t` | 4 bytes | 8 bytes | Requires attention |

### 3.2 Code Patterns That Break Under 64bit Conversion

Dangerous code patterns:

- Places that store a pointer in an `int` (pointer truncation under 64bit)
- Processing that depends on `sizeof(long)`
- Changes to struct size/padding (affects network protocols, file formats, shared memory)
- `printf` format specifiers (e.g., outputting a `long` with `%d`)
- Implicit truncation from casts

---

## 4. Addressing the Year 2038 Problem

### 4.1 Overview of the Problem

If the target system operates as a 32bit binary and `time_t` is a 32bit signed integer (`int32_t`), it will overflow at 03:14:07 UTC on January 19, 2038.

Typical areas affected in long-running servers:

- User data timestamps (creation time, last access time, etc.)
- Expiration dates of time-limited resources
- Scheduled processing (periodic maintenance, events, etc.)
- Log timestamps
- Session management (timeout calculations)
- Date/time columns in the DB (on the PL/SQL side)
- Epoch time handling within scripts

### 4.2 Recommended Solution: 64bit Conversion Alongside the Solaris Migration

If built as a 64bit binary on Amazon Linux (x86-64), `time_t` automatically becomes 64bit (`int64_t`), fundamentally resolving the Year 2038 problem. Doing this at the same time as the Solaris→Linux migration is the most efficient approach (doing them separately means work such as struct size changes must be done twice).

### 4.3 Separating the Network Protocol

If a binary protocol is used between the client and server, the internal server types and the wire format must be clearly separated.

```c
// Wire format (fixed size, do not change)
struct wire_packet_header {
    uint16_t type;
    uint32_t timestamp;  // Keep 32bit at the protocol level
    uint32_t entity_id;
} __attribute__((packed));

// Internal representation (64bit)
struct internal_event {
    uint16_t type;
    int64_t  timestamp;  // 64bit internally
    uint64_t entity_id;
};
```

Advance 64bit support on the protocol side in stages, in coordination with client updates.

### 4.4 Verifying Persisted Data

- DB DATE/TIMESTAMP types → no Year 2038 problem
- DB storing epoch as an integer type → check the column type. If it's a 32bit integer, extension is needed
- Binary data saved to files (save data, etc.) → format changes may be required
- String data saved to files (usernames, etc.) → no conversion needed, per the policy of preserving the internal encoding. However, the encoding must still be identified
- Structs in shared memory → watch for size changes

**If data is held on a network filesystem (NFS, etc.)**, additionally check the following two points.

- **Timestamps inside data files**: if the application writes epoch time as binary data within a file (e.g., writing `time_t` directly as 32bit), format changes and data migration will be required. If stored as a string (ISO 8601, etc.), there is no impact
- **Timestamps of the filesystem itself**: under NFSv4 (RFC 7530), second-level data is defined as a signed 64bit value, so the Year 2038 problem within NFS itself is already resolved. However, it must be separately verified whether the OS/glibc on the NFS client side supports 64bit time_t, and whether timestamps obtained via `stat()` etc. are being stored in 32bit variables within the application

### 4.4.1 Impact Investigation Using y2k38-checker

[y2k38-checker](https://github.com/cysec-lab/y2k38-checker), developed by the Cybersecurity Research Laboratory at Ritsumeikan University, is available as a tool that uses static analysis to detect areas affected by the Year 2038 problem. It operates as a Clang Static Analyzer plugin and targets C language source code.

#### Detectable Items

| Check ID | Detection Content |
|-----------|---------|
| `read-fs-timestamp` | Locations reading file timestamps (potentially affected by the 32bit limitation on ext2/3, XFS, etc.) |
| `write-fs-timestamp` | Locations writing file timestamps |
| `timet-to-int-downcast` | Downcast from `time_t` to `int` (risk of 32bit truncation) |
| `timet-to-long-downcast` | Downcast from `time_t` to `long` |

#### Usage Policy

- Run in Phase 1 (static analysis) together with grep-based searches for Solaris-specific APIs
- Focus particularly on checking around read/write processing of NFS data files
- Enables comprehensive identification of `time_t`-related problem areas across a large-scale codebase

#### Setup Method and Constraints

- Requires a Linux x86_64 environment (prepare a Linux x86_64 development environment, or build the toolchain manually)
- Operates as a plugin based on Clang 11.0.0
- Structures output results via a Rust reporter
- Detection results may include false positives, so manual triage is required

#### Recommended Execution Steps

```
Step 1: Set up y2k38-checker (Linux x86_64 development environment or manual toolchain setup)
Step 2: Run a scan against the entire source code
Step 3: Triage the detection results (exclude false positives)
Step 4: Prioritize addressing results found around data I/O
Step 5: Address remaining detected locations based on priority
```

### 4.5 Recommended Migration Order

```
Step 1: Solaris x86 (32bit) → Amazon Linux x86-64 (64bit)
           - Perform OS migration + 64bit conversion simultaneously
           - time_t automatically becomes 64bit

Step 2: Year 2038 support for the network protocol
           - Roll out in stages in coordination with client updates
           - Have the server side support both 32bit/64bit timestamps

Step 3: Year 2038 support for DB/persisted data
           - e.g., migration from integer epoch → TIMESTAMP type
```

Step 1 resolves the Year 2038 problem within the server internally. Steps 2 and 3 can be advanced in stages timed with client updates and maintenance.

### 4.6 Handling It While Keeping 32bit Binaries (Not Recommended)

On Linux (glibc 2.34+), `-D_TIME_BITS=64 -D_FILE_OFFSET_BITS=64` can make `time_t` 64bit even in a 32bit binary, but this is not recommended for the following reasons:

- Amazon Linux 2023 does not provide i686 userspace packages (32bit packages such as glibc.i686, libstdc++.i686, etc. do not exist, making it difficult to build/link 32bit binaries. 32bit execution capability at the kernel level is maintained, but since the provision of 32bit compatibility features may be reduced in future versions, check the AL2023 documentation for the latest status)
- The address space is limited to 4GB (harsh for large-scale server applications)
- It gives up the performance gains obtained from 64bit conversion

---

## 5. Character Encoding and Locale Handling

### 5.1 Decision Framework: How to Handle Internal Encoding

There are broadly three options for character encoding migration. Judge according to the project's circumstances.

| Option | Description | Change Cost | Data Migration | Suitable Situations |
|---|---|---|---|---|
| A. Unify internally to UTF-8 | Convert all internal server processing to UTF-8 and migrate persisted data as well | High (affects all string processing) | Required (bulk conversion of existing data) | When rewriting at a scale close to new development, or when prioritizing long-term maintainability |
| B. Preserve the internal encoding | The OS side is UTF-8, but the application internals keep the existing encoding (EUC-JP/Shift_JIS, etc.) | Low (only address boundary areas) | Not required | When wanting to minimize the risk of the migration itself, or when wanting to limit the scope of change in a large-scale codebase |
| C. Phased UTF-8 conversion | First complete the migration under policy B, then move to UTF-8 in stages later | Medium (split into 2 stages) | Occurs in stages | When wanting to finish the migration quickly while still keeping future unification in view |

**Trade-offs when choosing Option B**:
- Advantages: string processing, buffer sizes, and byte-count-based processing such as `strlen()` can remain unchanged. Existing persisted data (files, DB, configuration) can continue to be used as-is, avoiding the risk of data corruption
- Disadvantages: a mismatch arises between the OS-side locale settings and the internal encoding, requiring individual handling at boundary areas (5.4 below). If UTF-8 unification becomes necessary in the future, conversion work will need to be done again at that point

**Trade-offs when choosing Option A**:
- Advantages: the OS/library defaults align with internal processing, eliminating the need for special handling at boundary areas. Higher future maintainability
- Disadvantages: changes extend across all string processing (buffer size review, fixes to code that assumes byte counts). Creating and running a conversion tool for persisted data is required, carrying a risk of data corruption

### 5.2 Locale Differences

| Solaris | Linux |
|---------|-------|
| `ja_JP.eucJP` / `ja_JP.PCK` (Shift_JIS) | `ja_JP.UTF-8` |
| EUC-JP / Shift_JIS is the default | UTF-8 is the default |
| `iconv_open("PCK", "eucJP")` | `iconv_open("SHIFT_JIS", "EUC-JP")` (encoding names may differ) |

### 5.3 Boundaries Requiring Attention When Choosing Option B (Preserving Internal Encoding)

Because byte-sequence processing in C programs operates independently of locale, it is possible for the application to keep handling byte sequences in the existing encoding internally even if the OS side is UTF-8. However, the following boundaries require attention.

#### 5.3.1 Locale-Dependent libc Functions

If `setlocale(LC_CTYPE, "")` is used to bring in the OS-side UTF-8 locale, the following functions will interpret SJIS/EUC-JP byte sequences as UTF-8 and malfunction.

| Function | Impact |
|------|------|
| `mbstowcs()` / `wcstombs()` | Conversion failure |
| `mblen()` / `mbrlen()` | Character byte-count determination changes |
| `strcoll()` / `strxfrm()` | Sort order changes |
| `isalpha()` / `toupper()`, etc. | Locale-dependent determination results change |
| `strftime()` | Output encoding becomes UTF-8 |

Handling: investigate the usage of these functions during Phase 1 analysis and address it by explicitly specifying the locale setting or replacing the functions.

#### 5.3.2 GCC Source File Handling

GCC interprets source files as UTF-8 by default. For Shift_JIS source files, compile errors or malfunctions can occur with characters whose second byte is `0x5C` (backslash) (e.g., certain kanji characters). This problem does not occur with EUC-JP.

Handling: add `-finput-charset=SHIFT_JIS -fexec-charset=SHIFT_JIS` (for SJIS) to the compile flags.

#### 5.3.3 Log Output / Operational Tools

If the application outputs logs in the existing encoding, OS-side tools (`grep`, `less`, etc.) will display them as corrupted (mojibake). This does not functionally break anything but is an operational issue.

Handling: pipe through `iconv` when viewing logs, or add a UTF-8 conversion wrapper only for the log output portion.

#### 5.3.4 External Libraries

When using libraries that assume internal UTF-8, such as libxml2, encoding conversion is required at the input/output boundary.

### 5.4 Risks

- If there are many locations using locale-dependent functions, the handling effort increases. Reconsider the approach depending on the Phase 1 investigation results
- If the client is UTF-8-ified in the future, a conversion layer will need to be added on the server side

### 5.5 Investigation Items (To Be Performed in Phase 1)

```bash
# Usage of locale-dependent functions
grep -rn "setlocale\|mbstowcs\|wcstombs\|mblen\|mbrlen\|strcoll\|strftime\|iswalpha" src/

# Source file encoding
file --mime-encoding src/**/*.c src/**/*.h

# Character encoding conversion processing such as iconv
grep -rn "iconv\|mb_convert\|nkf" src/ scripts/ tools/
```

---

## 6. Dependent Library Update Risks

### 6.1 Basic Policy

In systems maintained for 20+ years, OSS is likely to be the primary basis rather than commercial libraries. Fundamentally, this can be addressed by "building or installing a Linux version of the same library via a package."

### 6.2 Risks and Countermeasures

#### Risk 1: Dependency on Old Versions

There is a high likelihood that the API has changed in the latest version.

Examples:
- OpenSSL 0.9.x → 3.x (major API changes; 1.0-series APIs have been removed)
- zlib 1.1.x → 1.3.x (largely compatible but with some behavioral differences in details)

Countermeasures:
- Identify the version currently in use (via Makefile, configure, header version macros, etc.)
- Attempt a build with the latest version and identify incompatibilities from compile errors and deprecation warnings
- If incompatibilities are large, there is also the option of using the oldest stable version that runs on Amazon Linux (a trade-off against security risk)

#### Risk 2: Libraries That Are No Longer Maintained With No Successor

There is a possibility that some OSS has ceased maintenance over the 20-year period.

Countermeasures:
- If a successor library exists, migrate to it (e.g., libevent → libev → libuv)
- If there is no successor, keep the source code in-house and build it on Linux
- As a last resort, reimplement the relevant functionality in-house

#### Risk 3: Libraries With Solaris Patches Applied

In long-running systems, it is common for custom patches to have been applied to OSS libraries (bug fixes, performance tuning, adjustments to match Solaris-specific behavior, etc.).

Countermeasures:
- If the library's source tree remains, check the diff against upstream
- After understanding the content of the patches, judge whether an equivalent patch is needed for the latest version

#### Risk 4: Implicit Dependency on Solaris libc

Even if a library itself is cross-platform, it may depend on Solaris-specific behavior.

Examples:
- `strlcpy`/`strlcat` (present in Solaris, but not included in glibc until 2.38. Since Amazon Linux 2023's glibc is in the 2.34 series, this is unavailable, requiring a custom compat function)
- `getpassphrase()` (Solaris-specific)
- `mmap` flag differences (`MAP_ANON` vs `MAP_ANONYMOUS`) — however, on Linux, `MAP_ANON` is defined as an alias for `MAP_ANONYMOUS`, so a fix is usually unnecessary
- Differences in the default thread stack size

Countermeasures:
- Building on Linux will surface these as compile errors, so discovery itself is easy
- Missing functions can often be covered with a small compat function

#### Risk 5: Build System Issues

Old OSS may have build configurations that assume gmake + Sun Studio on Solaris.

Countermeasures:
- Fetching the latest version usually already supports GCC/Linux
- If forced to use an old version, Makefile modifications will be needed

#### Risk 6: License Changes

Some OSS may have changed licenses over the 20-year period.

Countermeasures:
- Check the license before upgrading to the latest version
- If there is an issue, either use the version prior to the license change or consider an alternative library

### 6.3 Migration Outlook for Common Libraries Used in Long-Running Servers

| Category | Common Libraries | Linux Migration | Notes |
|---------|------------------|----------|--------|
| Networking | libevent, libev, ACE | Easy | Already Linux-supported |
| DB connectivity | Oracle OCI (Pro*C), libpq | Possible | If using Oracle, the Linux version of OCI is needed |
| Encryption | OpenSSL | Requires attention | Version differences can be large |
| Compression | zlib, lz4, snappy | Easy | Nearly unchanged |
| Scripting | Lua, Python (C embed) | Possible | Watch for version differences |
| XML/JSON | libxml2, jansson, cJSON | Easy | |
| Logging | syslog, log4cxx | Easy | |
| Memory | libumem, jemalloc, tcmalloc | Possible | libumem does not exist on Linux, so replace with jemalloc, etc. |
| String/regex | PCRE, ICU | Easy | Watch for version differences |
| Character encoding conversion | iconv, ICU, nkf | Possible | Differences in encoding names (e.g., Solaris's `PCK` → Linux's `SHIFT_JIS`) |

### 6.4 Recommended Approach

1. Create a library inventory: extract link options and include paths from Makefiles or configure
2. Sort into 3 categories:
   - A: Provided as an Amazon Linux package → `dnf install` is sufficient
   - B: Requires building from source, but the latest version is fine → fetch source and build
   - C: Has custom patches, or is pinned to an old version → requires individual handling
3. Items in category C account for the bulk of the migration effort, so identify them early

---

## 7. Compatibility Layer Design

### 7.1 Design Pattern (APR-Based)

#### Hierarchical Fallback Strategy

```
Optimized implementation (Solaris atomic.h, Linux epoll)
    ↓ (if unavailable)
Standard implementation (POSIX, GCC builtins)
    ↓ (if unavailable)
Generic implementation (mutex, select)
```

### 7.2 Recommended Directory Structure

```
solaris_compat/
├── include/
│   └── solaris_compat.h        # Unified API definitions
├── atomic/
│   ├── solaris_atomic.c        # Solaris implementation
│   └── linux_atomic.c          # Linux implementation
├── poll/
│   ├── solaris_port.c          # event ports
│   └── linux_epoll.c           # epoll
├── time/
│   ├── solaris_time.c
│   └── linux_time.c
└── CMakeLists.txt              # Build configuration
```

### 7.3 Conditional Compilation Pattern

```c
/* solaris_compat.h */
#ifdef __sun__
  #include <sys/port.h>
  #define USE_EVENT_PORTS
#elif defined(__linux__)
  #include <sys/epoll.h>
  #define USE_EPOLL
#endif

/* Unified API */
int compat_event_init(void);
int compat_event_wait(int timeout);
```

### 7.4 Reference Implementations: Open Source Software

#### 1. Apache Portable Runtime (APR) ⭐ Most Recommended

- **URL**: https://github.com/apache/apr
- **Characteristics**:
  - Supports 20+ platforms, including Solaris and Linux
  - Covers file I/O, networking, threads, processes, shared memory, and more
  - Provides 250+ APIs through a unified interface
- **Reference code**:
  - `apr/include/arch/unix/apr_arch_*.h` - platform detection
  - `apr/atomic/unix/solaris.c` - Solaris atomic implementation
  - `apr/atomic/unix/builtins.c` - Linux/GCC implementation
  - `apr/poll/unix/port.c` - Solaris event ports
  - `apr/poll/unix/epoll.c` - Linux epoll

#### 2. libevent

- **URL**: https://libevent.org/
- **Characteristics**:
  - Asynchronous I/O event-handling library
  - Abstraction from Solaris event ports → Linux epoll
  - Lightweight, simple implementation
- **Reference code**:
  - `evport.c` - Solaris event ports implementation
  - `epoll.c` - Linux epoll implementation

#### 3. PostgreSQL

- **URL**: https://github.com/postgres/postgres
- **Characteristics**:
  - 30+ years of portability track record
  - Platform-specific optimizations and fallback implementations
- **Reference code**:
  - `src/include/port/solaris.h` - Solaris-specific definitions
  - `src/include/port/linux.h` - Linux-specific definitions

#### 4. ACE (ADAPTIVE Communication Environment)

- **URL**: https://www.dre.vanderbilt.edu/~schmidt/ACE.html
- **Characteristics**:
  - Large-scale C++-based communication middleware
  - Supports 50+ platforms
- **Reference code**:
  - `ace/config-sunos5.*.h` - Solaris configuration
  - `ace/config-linux.h` - Linux configuration

### 7.5 Key API Conversion Reference

#### Atomic Operations

| Solaris | Linux/GCC |
|---------|-----------|
| `#include <atomic.h>` | GCC builtins (no include) |
| `atomic_add_32_nv(ptr, val)` | `__atomic_add_fetch(ptr, val, __ATOMIC_SEQ_CST)` ⚠️ |
| `atomic_cas_32(ptr, old, new)` | `__atomic_compare_exchange_n(ptr, &old, new, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)` ⚠️ |

> ⚠️ **Note the difference in return values for the add family**: `atomic_add_32_nv()` returns **the new value after the addition**. In Linux GCC builtins, `__atomic_add_fetch()` returns the new value, while `__atomic_fetch_add()` returns the old value from before the addition. The equivalent of Solaris's `_nv` suffix (new value) is the `__atomic_*_fetch()` family.

> ⚠️ **Note the difference in the CAS return value type**: `atomic_cas_32()` returns the old value (`uint32_t`), whereas `__atomic_compare_exchange_n()` returns success/failure (`bool`), with the old value written back into the second argument (`&old`). The correct equivalent code:
> ```c
> uint32_t expected = cmp;
> __atomic_compare_exchange_n(ptr, &expected, newval, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
> // The old value is stored in expected (corresponds to the return value of atomic_cas_32)
> ```

| Solaris | Linux/GCC |
|---------|-----------|
| `atomic_inc_32_nv(ptr)` | `__atomic_add_fetch(ptr, 1, __ATOMIC_SEQ_CST)` |
| `atomic_dec_32_nv(ptr)` | `__atomic_sub_fetch(ptr, 1, __ATOMIC_SEQ_CST)` |
| `atomic_swap_32(ptr, val)` | `__atomic_exchange_n(ptr, val, __ATOMIC_SEQ_CST)` |

#### Event-Driven I/O

| Solaris | Linux |
|---------|-------|
| `port_create()` | `epoll_create1(EPOLL_CLOEXEC)` |
| `port_associate(port, PORT_SOURCE_FD, fd, events, user)` | `epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev)` |
| `port_dissociate(port, PORT_SOURCE_FD, fd)` | `epoll_ctl(epfd, EPOLL_CTL_DEL, fd, NULL)` |
| `port_get(port, &event, timeout)` | `epoll_wait(epfd, events, 1, timeout)` |
| `port_getn(port, events, max, &nget, timeout)` | `epoll_wait(epfd, events, max, timeout)` |

#### Time Retrieval

| Solaris | Linux |
|---------|-------|
| `gethrtime()` | `clock_gettime(CLOCK_MONOTONIC, &ts)` |
| `gethrvtime()` | `clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)` |

#### Threads

| Solaris | Linux |
|---------|-------|
| `thr_create()` | `pthread_create()` |
| `thr_join()` | `pthread_join()` |
| `thr_self()` | `pthread_self()` |
| `mutex_init()` | `pthread_mutex_init()` |

---

## 8. Quality Assurance Strategy Without Test Code

### 8.1 Layer 1: Recording Current Behavior

Since there is no test code, record the behavior of the current system itself as "reference data."

- Structured collection of server logs (connect/disconnect, transactions, state changes, DB updates, etc.)
- Network packet capture (communication records between client and server)
- Recording of DB operations (PL/SQL execution results, table update patterns)
- Performance baselines (CPU usage, memory usage, response time, TPS)

### 8.2 Layer 2: Differential Testing

Run the Solaris version and the Linux version in parallel, and detect differences in output for the same input.

```
[Test client bot]
        │
        ├──→ [Solaris server] → logs/packets/DB results ─┐
        │                                              ├→ Differential comparison
        └──→ [Linux server]   → logs/packets/DB results ─┘
```

- Automatically run a fixed operation sequence (connect → operate → state change → disconnect, etc.) from a test client
- Compare the output of both servers and investigate any differences
- If a random seed can be fixed, an exact match of processing results can also be verified

### 8.3 Layer 3: Phased Introduction of Automated Tests

Write tests starting from the highest-risk areas, in parallel with the migration. Priority order:

1. Unit tests for locations using Solaris-specific APIs (tests of the compatibility layer)
2. The data persistence layer (integrity of user data)
3. Logic involving money, such as billing and transactions
4. The network layer (connection management, packet processing)

### 8.4 Layer 4: Phased Verification in Production

- Canary release: switch only one node to Linux and monitor for problems
- Shadow testing: send a copy of production traffic to the Linux server and compare results
- Metrics monitoring: anomaly detection for error rate, response time, memory usage

### 8.5 Layer 5: Leveraging the Existing QA Team

Manual QA is not "the absence of tests" — it is simply "not automated."

- Document the QA team's existing test procedures
- Carry out the QA cycle in the Linux environment
- Focus verification on edge cases (under high load, long-running operation, large numbers of concurrent connections, etc.)

### 8.6 Migration Risk for Surrounding Languages/Scripts (Examples)

Operational scripts and DB-layer languages are often attached around the C core. The following are examples of
representative combinations; evaluate by substituting according to the actual technology stack.

| Language Category | Examples | Migration Risk | Notes |
|------|-----------|------|------|
| Core implementation language | C/C++ | High | Solaris-specific APIs, build system changes, handling of locale-dependent functions |
| DB stored procedures | PL/SQL, T-SQL | Medium | Low risk if not accompanied by a DB migration |
| Operational scripts | Perl, Python | Low-to-medium | Check path/module dependencies. Check encoding specification when using character encoding conversion modules |
| Shell scripts | bash, ksh | Low | Replacement of Solaris-specific commands (truss, pfiles, etc.) |
| Admin screens/peripheral tools | PHP, Ruby, Perl CGI | Medium-to-high | When major version differences are large, there can be many incompatibilities at the language specification level requiring rewrites. Check multibyte string settings |

---

## Appendix A: Proposed Migration Approach

### A.1 Recommended Migration Method: Compatibility Layer + Parallel Operation

For large-scale, long-running codebases, a big-bang rewrite is often high-risk, so the basic approach
combines phased migration with verification via parallel operation. Below is an example of investigation
items to carry out during the analysis phase (to be increased or decreased according to the target
system's characteristics):

```
Phase 1: Static analysis / dynamic profiling
├─ Identify locations using Solaris-specific APIs (grep + static analysis)
├─ Detect locations affected by the Year 2038 problem using y2k38-checker
├─ Trace system calls at runtime (truss/dtrace)
│   → identify the code paths actually being used
├─ Investigate the format of persisted data (identify the timestamp storage format; also check the NFS version if NFS etc. is used)
├─ Investigate character encoding (identify the encoding of source files/data, usage of locale-dependent functions)
└─ Investigate dependencies of surrounding languages (DB layer, operational scripts, etc.)

Phase 2: Create compatibility layer + get the build passing
├─ Implement the solaris_compat layer
├─ Get to a state where the build passes on Amazon Linux
└─ Migrate the Makefile/build system

Phase 3: Build a parallel operation environment
├─ Launch a test server instance on Linux
├─ Keep production running on Solaris
└─ Have QA staff verify behavior in the Linux environment

Phase 4: Phased switchover
├─ Start with low-load nodes moving to Linux
├─ Expand progressively if no problems occur
└─ Always maintain a rollback procedure to Solaris
```

### A.2 Plan A: Phased Migration (Recommended) ⭐

**Approach**: Create a compatibility layer and replace things in stages. Follow the content of A.1 for the analysis/preparation phases.

```
Phase 1: Create the compatibility layer
├─ Create solaris_compat.h/c
├─ Linux implementations of frequently used APIs (door, kstat, etc.)
└─ Conditional compilation (#ifdef __sun__)

Phase 2: Build environment setup
├─ Set up the build environment on Amazon Linux
├─ Migrate Makefile/CMake
├─ Install dependent packages
└─ Enable GCC warning flags for early detection of 64bit conversion issues:
    -Wpointer-to-int-cast -Wint-to-pointer-cast -Wformat -Wall -Wextra

Phase 3: Phased rewrite
├─ Switch to going through the compatibility layer on a per-module basis
├─ Run unit tests
└─ Integration testing

Phase 4: Optimization
├─ Replace the compatibility layer directly with Linux APIs
└─ Performance tuning
```

**Advantages**: Low risk, parallel operation possible, easy rollback
**Disadvantages**: Takes time

> **Note**: this covers only application code rewriting; infrastructure migration (DTrace→eBPF, ZFS→ext4, etc.) is not included. For the overall effort including infrastructure, see the migration checklist in `solaris_linux_differences.md`.

### A.3 Plan B: Big-Bang Rewrite (Aggressive)

**Approach**: Remove and replace Solaris dependencies all at once

```
Phase 1: Overall analysis
├─ Extract all locations using Solaris APIs with an AI agent
└─ Create a conversion mapping table

Phase 2: Automated conversion
├─ Run a bulk replacement script with an AI agent
├─ Convert the build system
└─ Change all files at once

Phase 3: Fixes and testing
├─ Fix compile errors
├─ Handle runtime errors
└─ Functional testing
```

**Advantages**: Short timeframe, no technical debt
**Disadvantages**: High risk, parallel operation difficult

### A.4 Plan C: Hybrid (Balanced)

**Approach**: Compatibility layer for the core, direct rewrite for the periphery

```
Phase 1: Classification
├─ Analyze code with an AI agent
├─ Classify into "core functionality" and "peripheral functionality"
└─ Periphery: direct rewrite / Core: compatibility layer

Phase 2: Migrate peripheral functionality
├─ Directly Linux-ify logging, configuration loading, etc.
└─ Unit testing

Phase 3: Make core functionality compatible
├─ Use a compatibility layer for the business logic portion
└─ Integration testing

Phase 4: Phased optimization
├─ Gradually reduce the compatibility layer
└─ Performance verification
```

**Advantages**: Balance of risk and speed
**Disadvantages**: Requires judgment

---

## Related Documents

- [solaris_linux_differences.md](./solaris_linux_differences.md) - Comprehensive list of differences between Solaris x86 and Amazon Linux
  - Low-level API differences (19 items)
  - System-level feature differences (9 items)
  - Prioritized migration checklist (with estimated effort)
- Apache Portable Runtime official site: https://apr.apache.org/
- libevent official site: https://libevent.org/

---

## Information Sources

### Year 2038 Problem
- [Year 2038 problem - Wikipedia](https://en.wikipedia.org/wiki/Year_2038_problem)
- [glibc Y2038 Proofness Design](https://sourceware.org/glibc/wiki/Y2038ProofnessDesign) - `_TIME_BITS=64` support in glibc 2.34+
- [64-bit time_t for Linux/glibc (LWN.net)](https://lwn.net/Articles/643234/)
- [y2k38-checker](https://github.com/cysec-lab/y2k38-checker) - A Year 2038 problem detection tool for C, developed by the Cybersecurity Research Laboratory at Ritsumeikan University (Clang Static Analyzer plugin)
- [What is the Year 2038 Problem? (SQAT.jp)](https://www.sqat.jp/kawaraban/33142/) - Explanation of the Year 2038 problem, OS/library support status, examples of handling in embedded devices
- [NFSv4 (RFC 7530)](https://www.rfc-editor.org/rfc/rfc7530) - NFSv4's nfstime4 is defined as signed 64bit (see section 2.2.1)

### 32bit→64bit Migration (ILP32→LP64)
- [64-Bit Transition Guide for Cocoa Touch (Apple)](https://developer.apple.com/library/archive/documentation/General/Conceptual/CocoaTouch64BitGuide/ConvertingYourAppto64-Bit/ConvertingYourAppto64-Bit.html) - Explanation of type changes from ILP32→LP64 (the concept is common to C/C++)
- [Converting 32-bit Applications Into 64-bit Applications (Oracle)](https://docs.oracle.com/cd/E19205-01/819-5267/bkafh/index.html) - Guide to 32bit→64bit migration in the Solaris environment

### Quality Assurance / Testing Strategy
- [Differential Testing for Software (Microsoft Research)](https://www.microsoft.com/en-us/research/publication/differential-testing-for-software/) - Academic background on differential testing
- [Shadow Testing / Dark Launching (Martin Fowler)](https://martinfowler.com/bliki/DarkLaunching.html) - Concepts of shadow testing and canary releases

### Solaris→Linux Migration in General
- [Solaris to Linux Migration 2017 (Brendan Gregg)](https://www.brendangregg.com/blog/2017-09-05/solaris-to-linux-2017.html)
- [Comparison of Solaris OS and Linux for Application Developers (Oracle)](https://www.oracle.com/solaris/technologies/linux-app.html)

### Amazon Linux
- [Amazon Linux 2023 FAQs](https://aws.amazon.com/linux/amazon-linux-2023/faqs/)
- [Amazon Linux 2023 Package List](https://docs.aws.amazon.com/linux/al2023/release-notes/all-packages-AL2023.6.html)

### Migration of Surrounding Languages (e.g., PHP)
- [Migrating from PHP 5.6.x to PHP 7.0.x](https://www.php.net/manual/en/migration70.php)
- [Migrating from PHP 7.4.x to PHP 8.0.x](https://www.php.net/manual/en/migration80.php)

### OSS Library Compatibility
- [OpenSSL Migration Guide (1.1.1 to 3.0)](https://docs.openssl.org/3.0/man7/migration_guide/)
- [strlcpy added to glibc 2.38 (LWN.net)](https://lwn.net/Articles/934898/)
