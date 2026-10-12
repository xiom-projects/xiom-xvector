<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Stdlib wishlist from the XVECTOR lane

> **Coordination bus (2026-10-10):** the open rows below are migrated to
> the private `xiom-lang/xiom-relays` repo (one item per row; `--to stdlib
> --kind wishlist`): fsync/fdatasync = **REL-20261010-1550-xvector-2**, fd
> write path = **-3**, append_file_bytes = **-4**, truncate/ftruncate =
> **-5**, f32_bits = **-6**, bounded-depth json_parse = **-7**,
> flush_stdout = **-8**; **mmap family = REL-20261012-1945-xvector-2**
> (2026-10-12, owner-requested production relay). This file keeps the
> closed history; new rows go to the bus.

Needs collected while building the xiom-xvector durable vector store with the
latest stdlib (`E:\xiom-lang\stdlib`, `/mnt/e/xiom-lang/stdlib` in WSL).
**Re-checked 2026-10-11 (closure pass) on stdlib lane HEAD `9a2b5ab`
(wave 111, committed): the durability/fd/mmap rows below are STILL OPEN;
the `str_bytes`/`json_parse` quadratic is **FIXED + verified on the
committed pin** (both xvector repros exit 0 on Windows + WSL; bus
`REL-20261011-1453-xvector` / `-1543-xvector` closed; see
`docs/repro/xv-json-parse-quadratic/`); the bounded-depth `json_parse`
row is FIXED (wave 102 `5b7bf8f`). `str_chars`/`str_code_points` were
fixed at **wave 113 (`a996f7b`)** -- the str-family is fully closed and
re-verified at that HEAD (2026-10-11).** Format:
`| Need | Evidence | Workaround | Blocks |`.

**Status detail (2026-10-11):**

- `fsync` / `fdatasync` are still documented stubs (`fs_ffi.xi:238` /
  `:246`); the whole `sync_io` fd path is stubbed too (`write_all`
  `sync_io.xi:28`, `sync_fd` `:80`, `fsync_dir` `:88`). Re-checked at
  `b8eda7d`.
- The full mmap family is still stubbed (P5 gate): `xiom/os/mmap.xi`
  (12 documented stubs) + `fs_ffi.mmap`/`munmap`/`msync`/`madvise`/
  `mlock`, all "not available in the pure stdlib". Re-checked 2026-10-11;
  **filed as `REL-20261012-1945-xvector-2` (2026-10-12; re-checked
  `cd281b7`: `mmap_anonymous` Err).**
- There is **no `append_file_bytes`**; only the `Str`-typed `append_file`
  (`io.xi:268`) and the whole-file `write_file_bytes` (`io.xi:918`).
- `truncate` / `ftruncate` are still stubs (`fs_ffi.xi:151` / `:160`).
- `f32_bits` / `bits_to_f32` are absent (`float.xi` has only the Float64 pair
  at `:43` / `:52`).
- `flush_stdout` (`io.xi:906`) is still an empty body.
- **`slice.str_bytes` / `json_parse` quadratic: FIXED + verified on
  stdlib main `9a2b5ab` (wave 111)** (`json.xi` sha256 `E69E0275...`,
  `slice.xi` `874A8F67...`, `string.xi` `36D1F4FF...`; both repro probes
  exit 0 on Windows + WSL; full xvector batteries green on the committed
  pin; bus `-1453`/`-1543` closed). The lane keeps the byte-level fast
  scanner as the canonical hot path regardless (`src/api/json_fast.xi`,
  `probe_json_fast`).
- The byte-file APIs XVECTOR depends on work and are byte-exact/CRLF-clean
  since 0.64.2: `write_file_bytes` (`io.xi:918`), `read_file_bytes`
  (`io.xi:946`), `file_size` (`io.xi:977`).
- The 2026-10-09 `io.read_file` Str-content and tiny-read defects
  (XVC-C-11/C-12) were **compiler lowering bugs, fixed in compiler v0.64.2**
  -- no stdlib action needed.

Already available and adopted by XVECTOR (no row needed): `io.read_file_bytes`
/ `io.write_file_bytes`, `io.file_size`, `io.rename` (atomic temp+rename is
possible today -- a candidate hardening for `wal_file` checkpoints; noted in
SESSION), `io.create_dir(_all)` / `remove_file`, `xiom.hash.crc32_ieee` /
`crc32c` / `crc64_ecma` (WAL record checksums), `xiom.num.float.float_bits` /
`bits_to_float` (exact Float64 bitcast since v0.64.0/m194), `xiom.crypto`
SHA-256/HMAC (env-free since v0.64.0), `slice.str_bytes`.

| Need | Evidence (file:line or app path) | Workaround | Blocks |
|---|---|---|---|
| **`fsync`/`fdatasync` on a file (or fd)** -- the single highest-impact durability primitive for a WAL. `xiom.os.fs_ffi.fsync/fdatasync` and `xiom.os.sync_io.sync_fd/fsync_dir` are documented-Err stubs ("fsync syscall not available in the pure stdlib"). | `stdlib\xiom\os\fs_ffi.xi:238` (`fsync`), `:246` (`fdatasync`); `stdlib\xiom\os\sync_io.xi:80` (`sync_fd`), `:88` (`fsync_dir`). XVECTOR ROADMAP Phase 2 "fsync on commit" is [STOP] on exactly this gap; `wal_writer_flush` today is an in-memory no-op (`src\engine.xi`); the packages lane's new `xiom.wal` ships `wal_flush` as an honest no-op on the same gap. | none in-process; documented as not-durable until fixed (ROADMAP Phase 2). PULSE filed the same need earlier; XVECTOR + `xiom.wal` are requesters. | crash-safe acknowledged writes (Phase 2 exit criterion); any real database; M2 delta append log |
| **A byte-level fd write path: `write_all(fd, &Vec[UInt8])` actually implemented** (open an fd via `io.open`, append/write bytes, then sync). Every `xiom.os.sync_io` fd helper is a documented stub: `read_exact`, `write_all`, `read_until_eof`, `read_line_buffered`, `copy_fd`, ... | `stdlib\xiom\os\sync_io.xi:28` (`write_all`), module header: "All require raw fd syscalls ... every function is a documented stub"; `io.open` (`stdlib\xiom\io\io.xi:502`) returns an fd that has no write API to pair with. | whole-file `read_file_bytes`/`write_file_bytes` (O(file) per WAL append -- unusable for a log); XVECTOR keeps the WAL in memory + whole-file checkpoints (`durability.wal_file`). | append-only WAL segments, segment files, any durable log |
| **`io.append_file_bytes(path, &Vec[UInt8])`** -- `append_file` is `Str`-only and `write_file_bytes` rewrites the file; a WAL appender needs byte append without a full rewrite. | `stdlib\xiom\io\io.xi:268` (`append_file(path, content: Str)`), `:918` (`write_file_bytes` whole-file), `:946` (`read_file_bytes`). | read-modify-write via the byte APIs (O(file) growth) or in-memory WAL (current); `xiom.wal` uses line appends via the Str path. | same as above (WAL segments) |
| **`f32_bits(Float32) -> Int` / `bits_to_f32(Int) -> Float32`** -- direct IEEE-754 bitcast for 32-bit floats; today only the Float64 pair exists. | `stdlib\xiom\num\float.xi:43` (`float_bits(Float64)`), `:52` (`bits_to_float(Float64)`); XVECTOR's WAL codec goes `f as Float64` -> `float_bits` -> store, and back on decode (exact, but two conversions per dimension). | `float_bits(v as Float64)` / `bits_to_float(b) as Float32` in `src\payload\payload.xi` `vector_encode`/`vector_decode` -- exact, just indirect. | efficiency only (hot path once fsync lands) |
| **`truncate`/`ftruncate` on a path/fd** -- needed to truncate a WAL segment after a checkpoint, and to repair a torn tail in place. | `stdlib\xiom\os\fs_ffi.xi:151` (`truncate`), `:160` (`ftruncate`) -- documented stubs. | none; XVECTOR recovery skips torn records instead of repairing the file (`wal_load` returns the longest valid prefix); `xiom.wal` heals by temp+rename truncate. | WAL checkpoint/compaction file lifecycle (Phase 2/5) |
| **Durable `io.flush_stdout`** (PULSE row; XVECTOR adds itself as requester): redirected long-running process logs are lost on abnormal exit because `flush_stdout` is an empty body. | `stdlib\xiom\io\io.xi:906` (`flush_stdout` empty; comment says stdio is line-buffered -- false for redirected output). XVECTOR probe runners capture output to files; evidence can be lost on crash/abort. | write evidence to files explicitly (scripts), or keep runs short. | observability of long-running servers/probes |
| **Bounded-depth `json_parse` (recursion guard)** -- `xiom.serialize.json.json_parse` recurses per nesting level; a ~60 KB run of `[` (well under typical body limits) overflows the process stack: **access violation 0xC0000005, exit -1073741819** (found by `probe_http_fuzz`, M-S4). Balanced nesting is fine to ~4 k depth; unbalanced 60 k depth crashes before any error path. **FIXED 2026-10-10 (wave 102 `5b7bf8f`); bus item -7 verified + closed.** | `stdlib\xiom\serialize\json.xi` (`json_parse`); repro: the `probe_http_fuzz` `t-unbalanced` case (pre-guard the probe died at that mark). | XVECTOR pre-scans request bodies with `json_depth_ok(body, 64)` at the HTTP edge (`src\api\http_service.xi`) and rejects deeper payloads with 400 before the parser sees them; the stdlib should add an internal depth cap returning `Err`. | DoS-safety of any service parsing untrusted JSON |
