# verify Snippets — C / Solaris x86 → Amazon Linux

A collection of snippets for implementing each verify.sh gate in this domain.
(For the skeleton and usage of verify.sh, see the harness's verify.sh.template)

## build gate: Example expected artifacts

```bash
# Typical artifacts of a C native product (shared library + executable binary)
EXPECTED_ARTIFACTS=(
  "$MODERNIZED/lib/foo/libfoo.so.2.1"
  "$MODERNIZED/programs/bar/bar"
)
```

## smoke gate

```bash
# --- CLI: --help returns rc=0 ---
smoke_cli() {
  "$MODERNIZED/path/to/cli" --help > /dev/null 2>&1 \
    && pass "cli --help" || fail "cli --help"
}

# --- Daemon: survives for 2 seconds (timeout's rc=124 means "alive" = PASS) ---
smoke_daemon() {
  timeout 2 "$MODERNIZED/path/to/daemon" <ARGS>; rc=$?
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 0 ]; then
    pass "daemon alive (rc=$rc)"
  else
    fail "daemon died (rc=$rc; 139=SIGSEGV, 127=lib missing)"
  fi
}

# --- Shared library: no unresolved dependencies ---
smoke_libs() {
  local lib unresolved=0
  for lib in "${EXPECTED_ARTIFACTS[@]}"; do
    case "$lib" in *.so*)
      if ldd "$lib" | grep -q "not found"; then
        fail "$lib: unresolved deps"; ldd "$lib" | grep "not found"
        unresolved=1
      fi ;;
    esac
  done
  if [ "$unresolved" -eq 0 ]; then pass "all libs resolve"; fi
}
```

Note: Preconditions for smoke tests (prerequisite daemons such as rpcbind, LD_LIBRARY_PATH, DISPLAY/Xvfb)
should be documented explicitly in the "Preconditions" section of test-procedures.md, and set up or
checked within verify.sh.

## integration gate

- ToolTalk/RPC-related: verify registration with `rpcinfo -p | grep <prog-number>`
- X11-related: verify properties with `xprop -root` (or `-id <win>`)
- Each test is implemented as a self-contained script in 02-test/integration/*.sh (rc=0 = PASS)

## Multi-repository setups and diagnostic-marker scanning

```bash
# If one product is split across multiple repositories (e.g. the shared libraries and the executables
# live in separate repositories), list them all. Keep them aligned with the repo-ids in repository-inventory.md.
MODERNIZED_TREES=(
  "../libs-modernized"
  "../programs-modernized"
)

# Paths to scan for diagnostic-code markers (DIAG-). For C, narrowing to the implementation sources is faster
DIAG_SCAN_PATHS=(
  "lib"
  "programs"
)
```

Keep the expected artifacts and integration tests as a single cross-repository list
(the gates ask "does it work as a system," so do not split them per repository).

## Mechanical detection of lost functionality

```bash
# For CLI/daemon programs the golden path means "the sequence of operations a real user always runs".
# With no UI you may leave REQUIRE_GOLDEN_PATH at 0, but in exchange always place the
# "start -> handle a request -> exit cleanly" sequence in the integration gate
REQUIRE_GOLDEN_PATH=0
GOLDEN_PATH_TESTS=(
  # "02-test/integration/e2e-request-lifecycle.sh"
)

# Patterns that must not appear in committed code (a second net for unintended disabling).
# Tag temporary ones with `/* STUB-<id>: */` (detected by the repo-sync gate)
FORBIDDEN_PATTERNS=(
  "not implemented"
  "/\\* *stub *\\*/"
  "return NULL; */\\* *(temporary|stub)"
)
FORBIDDEN_SCAN_PATHS=(
  "lib"
  "programs"
)
```

**C-specific cautions:**

| Pattern | Caution |
|---------|------|
| `#if 0` | A strong signal of a disabled code block. It is easy to wrap something temporarily during a migration and forget it. Well worth adding to `FORBIDDEN_PATTERNS` |
| `#ifdef NOTYET` etc. | Measure the project's own conventions and add them |
| `abort()` / `assert(0)` | Sometimes used to mark an unimplemented path. Measure before deciding |

In a migration, "it builds but the feature is disabled" is the hardest thing to see.
**Map** any range wrapped in `#if 0` **to the corresponding row of the adaptation ledger** and set its
disposition to `not_applicable` (reason required).

## nonfunc gate (opt-in)

```bash
# --- Resource leaks (long-running — AI can handle this via background execution + log monitoring) ---
nonfunc_leak() {
  valgrind --leak-check=yes --error-exitcode=1 "$MODERNIZED/path/to/binary" <ARGS>
}

# --- Performance (baseline comparison. Example: ±20% tolerance) ---
nonfunc_perf() {
  for i in $(seq 1 10); do
    /usr/bin/time -p "$MODERNIZED/path/to/cli" <ARGS> 2>&1 | awk '/^real/{print $2}'
  done > /tmp/perf-current.txt
  # Compare against measured values in 02-test/test-results/baseline/
}
```
