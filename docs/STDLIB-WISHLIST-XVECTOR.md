<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Stdlib wishlist from the XVECTOR lane

Needs collected while building the xiom-xvector durable vector store with
the latest stdlib (`E:\xiom-lang\stdlib`, `/mnt/e/xiom-lang/stdlib` in WSL;
compiler v0.64.0). Format: `| Need | Evidence | Workaround | Blocks |`.

Already available and adopted by XVECTOR (no row needed): `io.read_file_bytes`
/ `io.write_file_bytes`, `io.open`, `xiom.hash.crc32_ieee` / `crc32c` /
`crc64_ecma` (WAL record checksums unblocked), `xiom.num.float.float_bits` /
`bits_to_float` (exact Float64 bitcast since v0.64.0/m194), `xiom.crypto`
SHA-256/HMAC (env-free since v0.64.0), `slice.str_bytes`.

| Need | Evidence (file:line or app path) | Workaround | Blocks |
|---|---|---|---|
| **`fsync`/`fdatasync` on a file (or fd)** -- the single highest-impact durability primitive for a WAL. `xiom.os.fs_ffi.fsync/fdatasync` and `xiom.os.sync_io.sync_fd/fsync_dir` are documented-Err stubs ("fsync syscall not available in the pure stdlib"). | `stdlib\xiom\os\fs_ffi.xi:238` (`fsync`), `:248` (`fdatasync`); `stdlib\xiom\os\sync_io.xi:80` (`sync_fd`), `:88` (`fsync_dir`). XVECTOR ROADMAP Phase 2 "fsync on commit" is [STOP] on exactly this gap; `wal_writer_flush` today is an in-memory no-op (`src\engine.xi`). | none in-process; documented as not-durable until fixed (ROADMAP Phase 2). PULSE filed the same need earlier; XVECTOR adds itself as requester. | crash-safe acknowledged writes (Phase 2 exit criterion); any real database |
| **A byte-level fd write path: `write_all(fd, &Vec[UInt8])` actually implemented** (open an fd via `io.open`, append/write bytes, then sync). Every `xiom.os.sync_io` fd helper is a documented stub: `read_exact`, `write_all`, `read_until_eof`, `read_line_buffered`, `copy_fd`, ... | `stdlib\xiom\os\sync_io.xi:28` (`write_all`), module header: "All require raw fd syscalls ... every function is a documented stub"; `io.open` (`stdlib\xiom\io\io.xi:502`) returns an fd that has no write API to pair with. | whole-file `read_file_bytes`/`write_file_bytes` (O(file) per WAL append -- unusable for a log); XVECTOR keeps the WAL in memory this session. | append-only WAL segments, segment files, any durable log |
| **`io.append_file_bytes(path, &Vec[UInt8])`** -- `append_file` is `Str`-only and `write_file_bytes` rewrites the file; a WAL appender needs byte append without a full rewrite. | `stdlib\xiom\io\io.xi:265` (`append_file(path, content: Str)`), `:914` (`write_file_bytes` whole-file), `:942` (`read_file_bytes`). | read-modify-write via the byte APIs (O(file) growth) or in-memory WAL (current). | same as above (WAL segments) |
| **`f32_bits(Float32) -> Int` / `bits_to_f32(Int) -> Float32`** -- direct IEEE-754 bitcast for 32-bit floats; today only the Float64 pair exists. | `stdlib\xiom\num\float.xi:43` (`float_bits(Float64)`), `:52` (`bits_to_float(Float64)`); XVECTOR's WAL codec goes `f as Float64` -> `float_bits` -> store, and back on decode (exact, but two conversions per dimension). | `float_bits(v as Float64)` / `bits_to_float(b) as Float32` in `src\engine.xi` `vector_encode`/`vector_decode` -- exact, just indirect. | efficiency only (hot path once fsync lands) |
| **`truncate`/`ftruncate` on a path/fd** -- needed to truncate a WAL segment after a checkpoint, and to repair a torn tail in place. | `stdlib\xiom\os\fs_ffi.xi:151` (`truncate`), `:155` (`ftruncate`) -- documented stubs. | none; XVECTOR recovery skips torn records instead of repairing the file. | WAL checkpoint/compaction file lifecycle (Phase 2/5) |
| **Durable `io.flush_stdout`** (PULSE row; XVECTOR adds itself as requester): redirected long-running process logs are lost on abnormal exit because `flush_stdout` is an empty body. | `stdlib\xiom\io\io.xi:903` (`flush_stdout` empty; comment says stdio is line-buffered -- false for redirected output). XVECTOR probe runners capture output to files; evidence can be lost on crash/abort (e.g. XVC-C-02 contract traps). | write evidence to files explicitly (scripts), or keep runs short. | observability of long-running servers/probes |
