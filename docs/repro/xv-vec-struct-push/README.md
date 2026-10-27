<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xv-vec-struct-push -- named `Struct{..., Vec}` pushed into `Vec[Struct]` frees the payload (v0.65.2)

**STATUS (2026-10-27): OPEN on v0.65.2; green control on v0.65.1.**
This is a **v0.65.2 release blocker** for xvector. v0.65.2 is **not
accepted**; the lane stays on v0.65.1 + stdlib-v0.65.1.

## Symptom

A named local struct that owns a `Vec` is pushed into a `Vec` of that
struct; at the end of the enclosing scope the compiler frees the struct's
`Vec` field, even though the Vec element still references it. Later
allocations reuse the freed buffer and the element's fields read as
corrupt values.

```xiom
var r = R{ id: i, xs: xs };   // named local
rs.push(r);                   // shallow copy of the Vec handle into the Vec
// ... scope exit drops r.xs, which is still the element's payload
```

The **inline literal form is green**:

```xiom
rs.push(R{ id: i, xs: ys });
```

## Observed

| Build | named-literal | inline-literal | exit |
|---|---|---|---|
| v0.65.1 + stdlib-v0.65.1 (control) | `bad=0 first=-1` | `bad=0` | 0 |
| **v0.65.2 + stdlib-v0.65.2** | **`bad=23..32 first=0`** | `bad=0` | **23..32** |

The sample forces allocator reuse with a `Vec[Int].with_len(8)` after each
push; without that pressure the corruption is still present but can be
masked by untouched freed memory.

## Impact in the lane

`src/durability/wal_file.xi` builds each loaded record exactly this way:

```xiom
var rec = WalRecord{ lsn: fields[0], ..., payload: payload, ... };
w.records.push(rec);
```

On v0.65.2 `probe_wal_file` fails **10 checks** (roundtrip, kill/reopen,
overwrite, torn-tail prefixes, 1200-record roundtrip) because the loaded
record payloads are freed/corrupted; on v0.65.1 the same probe is **0
failed checks**. `probe_manifest_file` and `probe_replica` stay green, so
the trigger is the named-struct push, not general file IO (a raw
`io.write_file_bytes`/`read_file_bytes` 256-byte roundtrip is also green).

This shape is used throughout the engine (WAL records, payloads, index
entries); a release with it is unsafe for any durable path.

## Run

```
. .\scripts\dev-env.ps1
.\scripts\build.ps1 docs\repro\xv-vec-struct-push\probe.xi -Name repro_vec_struct_push
powershell -File .\scripts\run-capped.ps1 -FilePath .\out\repro_vec_struct_push.exe `
  -WorkingDirectory . -MaxMemoryMB 256
```

Expected (fixed): `named-literal bad=0`, `inline-literal bad=0`, `PASS`,
exit 0.

## Suspect

The v0.65.2 borrowed/aggregate Vec reclaim (`8ec0904a5`): the aggregate
drop for the named local survives the `Vec.push` copy and frees the Vec
that the element retains. Inline literals (no named local) are excluded
from that drop.

**Filed:** relay item for compiler v0.65.2 (xvector lane).
