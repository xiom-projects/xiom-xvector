<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Stdlib wishlist from the XVECTOR lane

Needs collected while building the xiom-xvector durable vector store with the
latest stdlib (`E:\xiom-lang\stdlib`, `/mnt/e/xiom-lang/stdlib` in WSL).
**Re-checked 2026-10-09 on stdlib lane HEAD `82ac2f3` (release 0.64.3, pinned
to compiler v0.64.2): every row below is STILL OPEN.** Format:
`| Need | Evidence | Workaround | Blocks |`.

**Status detail (2026-10-09):**

- `fsync` / `fdatasync` are still documented stubs (`fs_ffi.xi:238` /
  `:246`); the whole `sync_io` fd path is stubbed too (`write_all`
  `sync_io.xi:28`, `sync_fd` `:80`, `fsync_dir` `:88`).
- There is **no `append_file_bytes`**; only the `Str`-typed `append_file`
  (`io.xi:268`) and the whole-file `write_file_bytes` (`io.xi:918`).
- `truncate` / `ftruncate` are still stubs (`fs_ffi.xi:151` / `:160`).
- `f32_bits` / `bits_to_f32` are absent (`float.xi` has only the Float64 pair
  at `:43` / `:52`).
- `flush_stdout` (`io.xi:906`) is still an empty body.
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
