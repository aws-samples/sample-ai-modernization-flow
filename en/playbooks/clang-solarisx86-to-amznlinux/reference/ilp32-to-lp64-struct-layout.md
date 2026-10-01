# Struct Layout Changes When Migrating ILP32→LP64 (details for DP-7)

This document is the detailed version of DP-7 in the Playbook's `practices.md`.
`practices.md` keeps only the essentials, the checks and the anti-patterns;
the background explanation and the code examples are separated out here
(the quantitative discipline for knowledge).

## Example of a Layout Change

```c
// ILP32 (Solaris SPARC/x86)
struct event {
    int      id;       // 4 bytes, offset 0
    time_t   start;    // 4 bytes, offset 4   ← ILP32: time_t = 4 bytes
    int      duration; // 4 bytes, offset 8
};  // sizeof = 12

// LP64 (Linux x86_64)
struct event {
    int      id;       // 4 bytes, offset 0
    // padding 4 bytes (alignment to 8)
    time_t   start;    // 8 bytes, offset 8   ← LP64: time_t = 8 bytes
    int      duration; // 4 bytes, offset 16
    // padding 4 bytes
};  // sizeof = 24
```

## Dangerous Patterns

| Pattern | Risk level | Description |
|---------|--------|------|
| Bulk-reading a struct from a file with `fread(&struct, sizeof, ...)` | **High** | Reading a file written in a 32-bit environment from a 64-bit environment shifts the fields |
| Accessing a field via `(char*)ptr + offset` (hardcoded offset) | **High** | If the offset assumes ILP32, it reads the wrong position under LP64 |
| Serializing a whole struct via XDR/RPC | **Medium** | If the wire format is fixed at 32-bit, decoding will be shifted |
| Sharing a struct through shared memory | **High** | Breaks when 32-bit / 64-bit processes are mixed |
| Copying an array of structs with `memcpy(dst, src, n * sizeof)` | **Medium** | The stride (spacing between elements) changes |

```c
// ❌ Dangerous: hardcoded offset (assumes ILP32)
char *ptr = (char *)&record;
time_t *start = (time_t *)(ptr + 4);  // offset 4 under ILP32, but offset 8 under LP64

// ✅ Safe: access via field name
time_t start = record.start;          // the compiler computes the correct offset

// ✅ Safe: use the offsetof macro
time_t *start = (time_t *)((char *)&record + offsetof(struct event, start));
```

## Safe Cases

- **Accessing via field name** (`record.field`): the compiler computes the offset correctly
- **Self-contained within a single binary**: recompiling keeps the struct layout consistent
- **Using XDR on a per-field basis**: the encoder/decoder serializes each field individually

## Pattern for time_t Compatibility in XDR

When maintaining compatibility with 32-bit clients while using a 64-bit time_t on the server side:

```c
// Keep 32-bit on the wire (compatible with existing clients)
// 64-bit time_t in memory
bool_t xdr_time_t_compat(XDR *xdrs, time_t *tp) {
    int32_t wire_val;
    if (xdrs->x_op == XDR_ENCODE) {
        wire_val = (int32_t)*tp;
        return xdr_int32_t(xdrs, &wire_val);
    } else {
        if (!xdr_int32_t(xdrs, &wire_val)) return FALSE;
        *tp = (time_t)wire_val;
        return TRUE;
    }
}
```
