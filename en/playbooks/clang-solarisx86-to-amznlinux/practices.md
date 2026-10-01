# Migration Practices Catalog — C / Solaris x86 → Amazon Linux

Accumulates practices specific to the C / Solaris → Linux porting domain in `DP-N` format.
For domain-agnostic common practices, see `practices-common.md` (Method layer, `CP-N` format).

---

## About This Document

### Purpose
- Accumulate practices specific to this Playbook (C / Solaris x86 → Amazon Linux).

### Numbering Rules
1. Use the **`DP-N` format, a sequential numbering managed centrally in this file** (use the next available number).
2. `DP-N` is unrelated to the `DP-N` of other Playbooks (e.g. java-modernization). Duplicate numbers are not a problem.
3. **Only the framework itself may assign an unprefixed `DP-N`.** Additions made in a project's
   copied `docs/knowledge/practices.md` use the `DP-<project>-N` namespace and are fed back into
   the framework on completion (for the details and the incident behind it, see
   "Numbering Authority" in `practices-common.md`).
4. **Gaps are preserved and never reused.**

### How to Read This, and the Quantitative Discipline

**By default an AI agent reads only the "Summary" table.** Open the body only when you hit the
relevant theme. The limits (300 bytes per summary row / 80 body lines / 15 entries) and
what to do when they are exceeded follow "Quantitative Discipline" in `practices-common.md`, and
are mechanically checked by `./verify.sh knowledge`.
Knowledge whose body exceeds the limit is split into `docs/reference/`, leaving the essentials plus
a pointer in the body (example: the details of DP-7 were split into
`docs/reference/ilp32-to-lp64-struct-layout.md`).

### Append Rules
1. Insert new entries **immediately before** the `ENTRIES END` marker (a single HTML comment line at the end of this file; this marker must not be moved).
2. Each entry MUST follow the `## DP-N: <Title>` format, with the following section structure:
   - `### Purpose` / `### Rule` / `### How to Check` / `### Anti-patterns` / optionally `### Real-world Example (project name)`
3. Add a row for the new entry to the "Summary" table.

---

## Summary

| ID | Title | One-liner |
|----|---------|------|
| DP-1 | Design constraints for event-driven I/O modules | Do not break the application code's assumptions (edge/level) |
| DP-2 | Default changes across GCC versions | -fno-common, -Werror=implicit-function-declaration, etc. Address old code incrementally with -fcommon etc. |
| DP-3 | Standard patterns for fixing LP64 pointer casts | XtPointer→int becomes intptr_t; NULL→int assignment becomes 0; NULL→char assignment becomes '\0' |
| DP-4 | glibc compatibility of POSIX TZ strings | `TZ=UTC0UTC` applies USA Eastern DST rules under glibc (via posixrules), and outside the range of the transition table yields EST/EDT offsets. If daylight==0, do not include a DST name |
| DP-5 | Return value type of functions handling time_t | An `int` return value gets truncated to 32 bits, causing Y2038 issues. Align it with `time_t` |
| DP-6 | Cover Y2038 verification across all layers | Verify not just the API but also the display layer and range-calculation layer. Do not forget 2039 and beyond |
| DP-7 | Verify struct layout changes when migrating ILP32→LP64 | sizeof/offset changes; prevent breakage in file I/O, RPC, and shared memory |
| DP-8 | Rules for creating a platform config.h | Verify macro values against man pages. Do not just copy and reuse |
| DP-9 | Suspect the initialization sequence for bugs undetectable by unit tests | If unit tests pass but the real binary fails, suspect init in main |

---

## DP-1: Design Constraints for Event-Driven I/O Modules

### Purpose
When building an event module for a new OS, do not break the assumptions on the application code side.

### Rule
1. Before implementing, confirm which event model the application code assumes:
   - A loop that "reads until EAGAIN" → assumes edge-triggered
   - A design where "a single read/write returns" → assumes level-triggered
   - A loop that "re-registers after receiving an event" → Event Ports/kqueue style
2. Event model mapping table (e.g., Solaris → Linux):

   | Source (Event Ports) | Target (epoll edge-triggered) |
   |---------------------|--------------------------|
   | Re-registration required | Not required |
   | event_flags | `USE_CLEAR_EVENT` |
   | add_connection | `EPOLLIN\|EPOLLOUT\|EPOLLET` |

3. If level-triggered is chosen, `handle_read_event` / `handle_write_event` may issue `EPOLL_CTL_DEL`, which can cause responses to stop returning in SSL communication, etc.

### How to Check
```bash
# Determine whether edge-triggered is assumed
grep -n 'EAGAIN\|EWOULDBLOCK' src/  # If used within a loop, edge-triggered is assumed
grep -n 'ngx_handle_read_event\|ngx_handle_write_event' src/
```

### Anti-patterns
- ❌ Implementing with "level-triggered for now" without confirming the event model
- ❌ Declaring completion based only on non-SSL communication tests (SSL communication is more susceptible to the effects of event re-registration)

---

## DP-2: Incremental Handling of Build Compatibility Across GCC Version Differences

### Purpose
Efficiently resolve "it used to compile but doesn't anymore" issues that arise when building old C code with modern GCC (10+).

### Rule
1. Understand in advance the defaults that changed across GCC major version updates:

   | GCC version | Change | Impact | Temporary workaround flag |
   |-------|------|------|--------------|
   | 10+ | `-fno-common` becomes default | Multiple-definition errors from global variable definitions in headers | `-fcommon` |
   | 14+ | `-Werror=implicit-function-declaration` | Calling a function without a declaration becomes an error | `-Wno-error=implicit-function-declaration` |
   | 14+ | `-Werror=incompatible-pointer-types` | Pointer assignment with mismatched types becomes an error | `-Wno-error=incompatible-pointer-types` |

2. **Incremental approach strategy**: First make the whole codebase buildable with workaround flags, then apply correct fixes individually afterward.
3. Consolidate workaround flags into the platform configuration, and plan to remove them eventually.

### Anti-patterns
- ❌ Adding `-fcommon` on a per-file basis (scatters the configuration)
- ❌ Attempting to fix 1000+ locations individually before adding workaround flags (extends the period during which the build is broken)

---

## DP-3: Standard Patterns for Fixing LP64 Pointer Casts

### Purpose
Efficiently and safely fix "pointer ↔ integer" cast warnings that occur during ILP32→LP64 migration.

### Rule
1. Typical patterns and their fixes:

   | Pattern | Original code | Fix |
   |---------|---------|------|
   | XtPointer→int (callback client_data) | `(int) client_data` | `(intptr_t) client_data` |
   | int→pointer (callback registration) | `(XtPointer) 42` | `(XtPointer)(intptr_t) 42` |
   | NULL→int-typed variable | `xrm_name[2] = NULL` | `xrm_name[2] = 0` |
   | NULL→char-typed variable | `*ptr = NULL` | `*ptr = '\0'` |
   | Window/Atom→int (X11) | `(int) window` | Leave as-is (X11's Window/Atom are 32-bit) |

2. Add `#include <stdint.h>` and use `intptr_t` / `uintptr_t`.
3. X11's `Window`, `Atom`, `Colormap`, etc. are internally 32-bit IDs even in 64-bit environments, so a cast may not be necessary in some cases. However, be careful with X APIs (e.g. XGetWindowProperty) that receive them as `long`.
4. Bulk replacement via `sed` is possible, but be careful not to mis-convert cases where an `(int) client_data` instance is "genuinely passing an int value" (e.g. an enum value).

### How to Check
```bash
# Detect LP64 warnings
gcc -Wpointer-to-int-cast -Wint-to-pointer-cast -c file.c
# Verify after the fix
gcc -Wpointer-to-int-cast -Wint-to-pointer-cast -Werror -c file.c
```

### Anti-patterns
- ❌ Casting everything to `(long)` (works on LP64 but breaks on Windows's LLP64)
- ❌ Suppressing warnings with `-w` and calling it "resolved"
- ❌ Changing X11's 32-bit ID types (e.g. Window) to intptr_t as well (an unnecessary change)

---

## DP-4: Constructing POSIX TZ Strings in a glibc-Compatible Way

### Purpose
Prevent legacy Unix-derived TZ construction code such as `sprintf("TZ=%s%d%s", tzname[0], tz_off, tzname[1])` from unintentionally applying USA Eastern DST rules under glibc (EST/EDT offsets outside the range) and shifting date calculations around the year 2038.

### Rule
1. In POSIX TZ format, specifying a **DST name while omitting the rule** (e.g. `TZ=UTC0UTC`) causes glibc to use the DST switchover dates from the default rule file `posixrules` (usually America/New_York). Within the range of the transition table it switches at the specified offset (UTC, UTC+1 in summer), but **for times after the last entry of the transition table, the offset of the trailing TZ string (equivalent to EST5EDT) is used as-is, while only the zone name stays UTC**. If `posixrules` is absent, the US default rule (M3.2.0,M11.1.0) applies and shifts by one hour during the DST period. The safe forms are as follows:

   | TZ value | Interpretation |
   |-------|------|
   | (unset) | Uses `/etc/localtime` (recommended) |
   | `UTC` | Fixed UTC ✅ |
   | `UTC0` | UTC, no DST ✅ |
   | **`UTC0UTC`** | DST name specified, rule omitted → **USA Eastern DST rules applied** ❌ |
   | `EST5EDT,M3.2.0,M11.1.0` | EST/EDT, explicit rule ✅ |

2. When `daylight == 0`, do not include the DST name (`tzname[1]`) in the output TZ.
3. Where possible, avoid `putenv("TZ=...")` and just call `tzset()`, leaving it to the system default (`/etc/localtime`).
4. If keeping the existing `sprintf` pattern, branch on the condition:
   ```c
   if (daylight) {
       sprintf(tzptr, "TZ=%s%ld%s", tzname[0], (long)offset_hr, tzname[1]);
   } else {
       sprintf(tzptr, "TZ=%s%ld", tzname[0], (long)offset_hr);
   }
   ```

### How to Check
```c
unsetenv("TZ"); tzset();
printf("tzname=%s/%s daylight=%d\n", tzname[0], tzname[1], daylight);
/* Verify that when daylight==0, the DST name is not included in the output TZ */

/* Observe the discrepancy at the 2038 boundary */
setenv("TZ", "UTC0UTC", 1); tzset();
time_t t = 2147126400;          /* 2038/01/15 00:00:00 UTC */
struct tm *tm = localtime(&t);
/* Check whether local time stays UTC or shifts to EST/EDT offsets */
```

### Anti-patterns
- ❌ Unconditionally concatenating `tzname[0]`, `tzname[1]`, and `timezone` into a TZ string
- ❌ Carrying over TZ construction code that worked on Solaris into a glibc environment as-is
- ❌ Putenv-ing a TZ that includes a DST name in a UTC environment with no DST

### Real-world Example
In the initialization routine of a time-display utility, `TZ=UTC0UTC` was put into the environment, which caused the date-lookup feature to display dates one day earlier for dates from 2038 onward. This was resolved by branching on `daylight`.

---

## DP-5: Align the Return Value Type of Functions Handling time_t with `time_t`

### Purpose
Detect and fix code where, despite `time_t = long` (64-bit) under LP64, a function's return type is declared as `int` (32-bit), and prevent implicit truncation around the year 2038.

### Rule
1. For functions that take a `time_t` (or a typedef of `time_t`, such as `Tick`) and return a time value, align the return type with `time_t` as well.
2. If the return type remains `int`, returning a `time_t` value (which falls outside the 32-bit signed range from 2039 onward) causes it to become negative due to implicit truncation. There are code paths where the compiler does not emit a warning (an assignment from `int` to `time_t` is not warned about).
3. When fixing this, change **both the declaration (.h) and the implementation (.c)**.

### How to Check
```bash
# Detect functions that take time_t / Tick as an argument but return int
grep -rn '^extern int .*\(Tick\|time_t\)\|^int .*\(Tick\|time_t\)' .

# Check behavior across the value range (observe behavioral differences at boundary years)
# Call the function for 2037 / 2038 / 2039 / 2040 / 2050 and compare the return values
```

### Anti-patterns
- ❌ Leaving a time function whose return type is `int` unaddressed because "it's probably fine even on LP64"
- ❌ Assuming the issue is resolved by adding a `(time_t)` cast on the caller side (truncation has already occurred at the return stage)
- ❌ Concluding that no fix is needed on the grounds that no warning is emitted

### Real-world Example
A utility function performing DST (daylight saving time) correction had a return type of `int`. When a 2039 timestamp (> 2,147,483,647) was passed into an internal day-count calculation function, it was truncated to a negative number, breaking the subsequent range-search process. This was resolved by changing the return type to `time_t` (or its equivalent typedef) in both the implementation and the declaration.

## DP-6: Cover Y2038 Verification Across All Layers

### Purpose
Detect issues where the 64-bit conversion fix for time_t propagates beyond the API layer into the application's client display layer and range-calculation layer as well.

### Rule
1. After the Y2038 fix, perform verification across all of the following layers:
   - (a) API: function interfaces that pass time_t
   - (b) Serialization: time_t representation in XDR / RPC / file I/O
   - (c) File persistence: time storage format in DB / calendar files
   - (d) Client display: conversion processing when the UI / CLI displays times
   - (e) Range calculation: utility functions that add, subtract, or compare times

2. Scan for behavioral differences at boundary years:
   - Years to test: 2026 / 2030 / 2037 / **2038** / **2039** / 2040 / 2050
   - 2038-01-19 03:14:07 UTC is the upper limit of signed 32-bit
   - From 2038-01-19 03:14:08 UTC onward, time_t exceeds 2,147,483,647

3. Verify **both display and retrieval**:
   - Even if display is correct, retrieval (search/filtering) may fail
   - Include round-trip tests of insert → lookup

### How to Check
```bash
# Boundary-year test: verify consistency of create → retrieve → display for each year
for year in 2026 2030 2037 2038 2039 2040 2050; do
    # insert test data for $year
    # lookup and verify display matches
done
```

### Anti-patterns
- ❌ Declaring "Y2038 support complete" based solely on the time_t fix in the API layer
- ❌ Testing only the year 2038 and not checking 2039 onward (even in 2038 the limit is only exceeded from January 19 03:14:08 UTC onward, so for dates such as early in the year the truncation does not surface)
- ❌ Testing only display and not checking search/range calculation

### Real-world Example
The time_t in a calendar-related API was converted to 64 bits, but two additional bugs remained in the client-side time-processing utilities:
- TZ construction logic: `TZ=UTC0UTC` applied USA Eastern DST rules under glibc → date shift around 2038 (→ DP-4)
- DST-correction function's `int` return type: values from 2039 onward were truncated to negative numbers → range search broke (→ DP-5)
Both were only detected through end-to-end tests covering data registration → search.

## DP-7: Verify Struct Layout Changes When Migrating ILP32→LP64

### Purpose
When migrating from 32-bit (ILP32) to 64-bit (LP64), the sizes of `time_t`, `long`, and pointers change, which in turn changes a struct's memory layout (size, alignment, padding). This prevents breakage in code that manipulates byte sequences directly.

### Essentials
- Under ILP32 `time_t`/`long`/pointers are 4 bytes; under LP64 they are 8 bytes, so a
  struct's sizeof, its field offsets and an array's stride all change
- **As long as you access fields by name it is safe** (the compiler computes the right offset)
- The dangerous paths are the ones that treat a struct as a byte sequence: bulk read/write
  of a struct in file I/O, pointer arithmetic with hard-coded offsets, serializing a whole
  struct over XDR/RPC, shared memory between mixed 32-bit/64-bit processes, and
  `memcpy` with `n * sizeof`
- "It is fine because we recompiled" **does not hold for persisted data or network traffic**

For the concrete layout example, the full table of dangerous patterns, and the XDR
compatibility implementation (`xdr_time_t_compat()`), see
**`docs/reference/ilp32-to-lp64-struct-layout.md`**.

### How to Check

```bash
# Detect places reading/writing structs as byte sequences
grep -rn 'fread.*sizeof.*struct\|fwrite.*sizeof.*struct' .
grep -rn 'read(.*sizeof\|write(.*sizeof' . | grep struct

# Detect pointer arithmetic using hardcoded offsets
grep -rn '(char\s*\*)\s*.*+\s*[0-9]' . | grep -v '/\*'

# Detect code assuming a fixed size for structs containing time_t/long
grep -rn 'sizeof.*time_t\|sizeof.*long' . | grep -v 'malloc\|alloc'
```

### Anti-patterns
- ❌ Judging "it's fine since we recompiled" and not checking file persistence or network communication
- ❌ Not being conscious of changes in `sizeof(struct)` and using existing data-file-reading code as-is
- ❌ Judging there is no problem on the grounds that the compiler emits no warning (casts via `char*` are not warned about)

### Real-world Example
In the RPC communication of a calendar-related API, `time_t` was included in the wire format.
A policy of "keep 32-bit on the wire, 64-bit in memory" was decided, and this was handled with `xdr_time_t_compat()`.
Since all struct field access went through field names, no actual harm occurred from the layout change.

## DP-8: Rules for Creating a Platform config.h

### Purpose
When creating a config.h for the new OS from the copy-source OS's config.h, prevent
carrying over macro values that "compile fine but break at runtime."

### Rule
1. For each feature macro (`*_HAVE_*` / `*_USE_*`, etc.), verify the correct value on
   the new OS **individually** against `man` / official documentation. Do not just
   reuse the copy-source OS's value as-is.
2. The following categories are especially likely to have different semantics across
   OSes:
   - accept inheritance (O_NONBLOCK / INHERITED_NONBLOCK)
   - Differences in sendfile arguments and return values
   - The behavioral model of the event mechanism (edge/level, whether re-registration
     is needed)
   - Return values and memory ordering of atomic operations
   - Differences in socket option names (`TCP_CORK` vs `TCP_NOPUSH`)
3. A successful build is not proof of correctness. Incorrect macro values cannot be
   detected until runtime.

### How to Check
```bash
# Extract the list of macros in config.h
grep '#define.*HAVE_\|#define.*USE_' src/os/unix/<newos>_config.h
# For each macro:
man 2 <related_syscall>
# Or check the value against official documentation
```

### Anti-patterns
- ❌ Using the copy-source OS's config.h as-is and only adding headers
- ❌ Concluding "the build passed, so the macro value must be correct"
- ❌ Trusting what the configure script detected without checking it

## DP-9: Suspect the Initialization Sequence for Bugs Undetectable by Unit Tests

### Purpose
When a symptom appears where "a minimal test behaves correctly, but it misbehaves
through the real binary," narrow the cause down to a side effect of `main()`
initialization rather than function logic.

### Rule
1. When a unit test (calling the function directly) passes, but the symptom reproduces
   through the real binary, first suspect the following:
   - Global initialization functions called at the start of `main()`
     (`init_xxx`, `setup_xxx`)
   - C++ static constructors
   - Environment variable modification (`putenv`, `setenv`)
   - Locale / timezone settings (`setlocale`, `tzset`)
   - Signal handler registration
2. Compare a "version that calls the init function" against a "version that doesn't,"
   to isolate the side effect.
3. If fixing the function logic does not resolve the symptom, re-examine the
   initialization above.

### How to Check
```c
/* Build a version with the suspect init function and one without, and observe the
   difference */
extern void init_xxx(void);   /* Suspect initialization */
int main(void) {
    init_xxx();               /* ← Compare with and without this call */
    /* Call the same suspect function */
}
```
If a difference appears, that initialization function is the culprit.

### Anti-patterns
- ❌ Concluding a function is "correct" just because its unit test passes, and
  investigating only elsewhere
- ❌ Applying a speculative patch before establishing reproduction conditions
- ❌ Committing with debug output still embedded

### Real-world Example
A bug where a date-lookup feature displayed the previous day starting in 2038. Calling
the display-processing function directly did not reproduce it, and a minimal test
passed for all years. It only reproduced via `main`; the root cause was that
`putenv("TZ=UTC0UTC")` inside an initialization function was interpreted by
glibc as including USA Eastern DST rules, applying EST/EDT offsets to 2038 dates (→ DP-4).

<!-- ENTRIES END -->
