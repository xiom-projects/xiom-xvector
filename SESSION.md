# XIOM XVECTOR -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Written:** 2026-10-07 (bootstrap by the PULSE lane, owner request).
**Updated:** 2026-10-08 (first XVECTOR session: bootstrap executed + Phase 2
durability slice; continuation same day: Phase 3 payload filtering + XVC-C-06).
**Project:** production-grade vector database engine for XIOM (dense
vectors, distance metrics, flat + HNSW ANN, collections, segments,
WAL-backed durable writes; consolidated engine in `src/engine.xi` per AUDIT).

## 0. STATE (2026-10-08)

- **Repo:** `E:\xiom-projects\xiom-xvector` (formerly xiom-vector), private,
  no pushes. HEAD before this wrap: `7c7116a`. Identity `Lefteris Notas
  <lefterisnotas@gmail.com>`; conventional commits with DCO sign-off
  (`git commit -s`).
- **VERSION POLICY (owner decision): track the LATEST compiler / stdlib /
  packages.** Record exact versions and lane hashes at every wrap.
  - compiler: **v0.64.0**, Windows `%LOCALAPPDATA%\xiom.new\bin\xiom.exe`,
    WSL Ubuntu `~/.local/bin/xiom` (both verified this session).
  - stdlib: `E:\xiom-lang\stdlib` = `/mnt/e/xiom-lang/stdlib` -- lane
    checkout `9e64302` (2026-10-08, "refresh handoff snapshot 21").
  - packages: **none consumed yet**; registry installs would need
    `xiom.toml` `source-roots` (C-PULSE-02 still open on v0.64.0).
  - `XIOM_RUNTIME_DIR` retired; env-free builds verified.
- **Bootstrap DONE this session (was the todo from 2026-10-07):**
  - `scripts/dev-env.ps1` + `.sh`; `scripts/build.ps1` + `.sh`
    (watchdog, stale-binary removal, rcedit icon hook for
    `images\xvector-icon.ico`); `scripts/run-suite.ps1` + `.sh` (build +
    run x2, exit-code gate); `scripts/run-probe.ps1` + `.sh`;
    `scripts/lib.ps1` (reliable .NET process capture -- PS 5.1
    `Start-Process` ExitCode is unreliable with redirected output).
  - `xiom.toml` project manifest (`root = "src"`, `source-roots = ["src"]`);
    cross-file `use xiom.vector.engine;` resolves on v0.64.0.
  - probes: `tests/probes/probe_hello.xi`, `probe_engine_import.xi`,
    `probe_vector_store.xi` (critical primitive: create -> upsert ->
    search -> reopen -> search identical -> delete -> reopen again ->
    LSN continuity).
  - relay docs: `docs/COMPILER-FINDINGS-XVECTOR.md`,
    `docs/STDLIB-WISHLIST-XVECTOR.md`,
    `docs/PACKAGE-WISHLIST-XVECTOR.md`, `docs/RELAY-INTRO-XVECTOR.md`,
    repro bundles under `docs/repro/`.
  - `.gitignore` refreshed (kilo/workspace/out/logs); `images/` created for
    the owner's icon; `xiom-xvector.code-workspace` now ignored.
- **Phase 2 slice implemented (in-memory WAL, no fsync yet):**
  - durable vector codec: `vector_encode`/`vector_decode`
    (`[dim, Float64-bits...]`, exact; malformed -> None);
  - WAL: `wal_writer_append_payload` (key = point id, value = collection
    id), `wal_writer_resume`, `wal_writer_checkpoint_from`;
  - recovery: `recover_store` (replay inserts/deletes, skip torn payloads)
    + `engine_recover` (replay + compacted checkpoint log; LSN monotonic;
    chained reopen works);
  - public `search` returns `Result[SearchHits, CoreError]` --
    `SearchHits { items: Vec[SearchResult] }` is a **required** struct
    wrapper (XVC-C-04); `test_search_hits_shape` is the regression guard;
  - WAL record `log_upsert`/`log_delete` now carry point/collection
    consistently (point as key) -- fixed during the suite run.
- **Phase 3 slice implemented (payload & metadata filtering):**
  - `FieldValue`/`Payload`/`FilterExpr` fully typed evaluation (Eq exact
    within type, Range inclusive with Int->Float32 promotion, In, Exists,
    And/Or/Not, no-payload semantics), `payload_get` + overwrite `payload_set`.
  - Engine integration: `PayloadStore` (id -> payload, swap-remove),
    `engine_set_payload` (Ok(false) for missing point), `engine_get_payload`,
    `engine_search_filtered`/`search_filtered` (pre-filter exact scan,
    k-bounded), delete removes metadata.
  - Suite **156/156 x2**; new probe `tests/probes/probe_filtered_search.xi`
    green x2 (engine-import unit; FloatVal is diagnostic-only -- XVC-C-06).
  - Payload durability is a follow-up (WAL does not encode payloads yet;
    recovery drops metadata -- see the `engine_recover` NOTE).
- **Green evidence (exact commands):**
  - `scripts\run-suite.ps1 -Runs 2` -> `156/156 passed` twice, exit 0,
    stderr 0; same on WSL: `bash scripts/run-suite.sh 2 120`.
  - `scripts\run-probe.ps1 tests\probes\probe_vector_store.xi -Runs 2` and
    `scripts\run-probe.ps1 tests\probes\probe_filtered_search.xi -Runs 2` ->
    0 failed checks x2.
  - `bash scripts/run-probe.sh tests/probes/probe_hello.xi 2 60` green in WSL.
  - `probe_engine_import` green (cross-file module import).
  - Every build is numerically re-verified (XVC-C-05 rule; the
    filtered-search probe draws red builds ~1 in 3 -- rebuild, don't trust).
- **New compiler findings this session (details in the relay doc):**
  XVC-C-01 `&fn()` call miscompile (invalid IR / runtime crash);
  XVC-C-02 runtime contract violation exits 0;
  XVC-C-03 W004 false unreachable-arm on unit enums;
  XVC-C-04 `Result[Vec[non-scalar]]` / `Option[Vec[non-scalar]]` payload
  field loss (struct wrapper workaround adopted);
  XVC-C-05 per-build nondeterministic Float32 -> integer bit-pattern
  lowering (no reliable flag workaround; verify numerics per build);
  XVC-C-06 Float32 enum payloads can read as 0 in affected builds
  (FloatVal gates avoided; diagnostic-only in the probe).
- **stdlib status:** fsync/fdatasync still documented-Err stubs
  (`xiom/os/fs_ffi.xi:238`, `xiom/os/sync_io.xi:80`) -- Phase 2 file-backed
  WAL blocked; byte append (`append_file_bytes`) and fd write path missing;
  `crc32_ieee`/`crc32c` available and adopted for framing.
- **Next action (priority order):**
  1. Payload durability: encode payloads into WAL records (or a side log) so
     `engine_recover` restores metadata; then Phase 3's sorted key index and
     the pre/post-filter planner.
  2. Restore the layered module tree: cross-file imports now work on
     v0.64.0 (probe_engine_import green); the AUDIT-era consolidation can be
     unwound incrementally (engine.xi stays the stable facade until each
     layer compiles + passes the suite). The Phase 3 payload/filter code is
     the natural first extracted module.
  3. Watch compiler lane for XVC-C-01..06; re-run the repro bundles at the
     next archive, then re-pin. When fsync lands, implement file-backed WAL
     segments + durable manifest (Phase 2 exit criteria).
  4. HNSW hardening (Phase 4) after the tree cleanup/porter extraction.

## 1. Consumer-lane rules (non-negotiable)

- **Never edit** `E:\xiom-lang\stdlib`, `E:\xiom-lang\xiom`,
  `E:\xiom-packages\packages`. Record their HEAD hashes each wrap:
  `git -C <lane> log -1 --format="%h %cI %s"`.
- Report upstream only through the three relay docs + SESSION rows; the
  owner relays to the stdlib/packages/compiler lanes (intro message:
  `docs/RELAY-INTRO-XVECTOR.md`).
- Consume packages from the registry only; never vendor a package copy.
  Reusable primitives this lane grows should be **proposed as packages**
  in the package wishlist (`xiom.vectors` / `xiom.wal` / `xiom.ann`).

## 2. Pin discipline that bites (v0.64.0, extended this session)

- Initialize every local at declaration (`var x: T = <default>;`); every
  **struct literal must list every field** -- a missing field reads
  uninitialized garbage and can crash (C-PULSE-06).
- Never initialize module-scope variables with **cross-package
  constructor calls** (C-PULSE-07). Keep package aggregates caller-owned.
- Never call `.to_str()` on a module-`const` receiver -- W005 stub
  (C-PULSE-05; `convert.int_to_string` is the workaround). Explicit `*p`
  for every `&mut Int` read (C-PULSE-04).
- Types are `Vec[T]` / `Result[T, Err]`; after every write run the
  byte-level grep for `Vec<|Result<|Option<`.
- **XVC-C-01: never call a `&fn() -> T` parameter as `f()`** (invalid IR) or
  `(*f)()` (runtime crash). Evaluate at the call site or use a struct-field
  fn pointer.
- **XVC-C-02: never call a contracted function out of contract** -- a
  runtime `requires` violation aborts with **exit 0** (silent green). Test
  the predicate, not the contracted entry point.
- **XVC-C-04: never return `Result[Vec[non-scalar], E]` /
  `Option[Vec[non-scalar]]`** -- wrap the Vec in a struct Ok-payload
  (`SearchHits` pattern).
- **XVC-C-05: verify numerics per build.** Treat a red numeric check as a
  build rejection; rebuild rather than trusting the binary. `--sequential`
  is an A/B diagnostic only.
- Keep a `-TimeoutSec` watchdog on every run/suite and gate on exit code;
  run every green suite x2; soak anything long-running.
- Start long-running processes with output redirected to **files** (never
  an undrained PowerShell pipe -- a chatty child holding inherited pipes
  hangs the caller).
- Build scripts must delete a stale output binary before compiling (a
  failed compile otherwise leaves the previous binary to be run as "fresh").
- PS 5.1: `Start-Process` + redirected output gives unreliable
  `ExitCode` (sometimes `$null`) -- use `scripts/lib.ps1`
  (`Invoke-XvectorProcess`, .NET ProcessStartInfo + async readers).

## 3. Known ecosystem status (2026-10-08)

- Open compiler findings relevant here: C-PULSE-02 (registry deps ->
  catalog roots; workaround `source-roots`), C-PULSE-04, C-PULSE-05,
  C-PULSE-06, C-PULSE-07; PULSE C-PULSE-08..12; plus XVECTOR's
  XVC-C-01..05 (above). C-PULSE-01 resolved on v0.64.0.
- Stdlib: SHA-256/HMAC usable env-free; `crc32_ieee`/`crc32c` available;
  fsync/fd-syscall family still stubs (see wishlist).
- Registry ready for consumers: `xiom.http` 0.1.1, `xiom.jwt` 0.2.0,
  `xiom.rate` 0.2.0, `xiom.metrics` 0.2.0, `xiom.router` 0.1.0,
  `xiom.http.middleware` 0.1.0, `xiom.session` 0.1.0, `xiom.static`
  0.1.0, `xiom.kv` 0.1.0. Read `E:\xiom-projects\xiom-pulse\SESSION.md` +
  its three relay docs before filing anything new (do not rediscover).

## 4. Paste prompt for the next XVECTOR session

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first, then
README/SPEC/ARCHITECTURE/ROADMAP/AUDIT and docs/. Consumer lane: never
edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom, E:\xiom-packages\packages.
Repo stays PRIVATE; no pushes without owner approval. Identity
"Lefteris Notas <lefterisnotas@gmail.com>"; conventional commits, DCO -s.

Toolchain (latest-tracking): compiler v0.64.0 on Windows
(%LOCALAPPDATA%\xiom.new\bin\xiom.exe) and WSL Ubuntu
(~/.local/bin/xiom), stdlib lane E:\xiom-lang\stdlib (= /mnt/e/... in WSL),
XIOM_RUNTIME_DIR retired. Dot-source scripts\dev-env.ps1 (and its .sh
twin); build with scripts\build.ps1 / scripts\build.sh; suites via
scripts\run-suite.*; the critical probe is
tests\probes\probe_vector_store.xi (run via scripts\run-probe.*).

Bootstrap is DONE; Phase 2 (WAL vector codec + recovery/checkpoint) and
Phase 3 (payload filtering: typed eval + engine integration + filtered
search) are implemented; the suite is 156/156 x2 on both platforms.
Continue the ROADMAP: payload durability (WAL encodes payloads), then
unwind the AUDIT-era consolidation into the layered module tree
(cross-file imports now work on v0.64.0; extract the payload/filter module
first), then HNSW hardening; file-backed WAL waits on the stdlib fsync gap.

Pin discipline additions: never call `&fn()` parameters (XVC-C-01);
never call contracted functions out of contract -- violations abort with
exit 0 (XVC-C-02); never return Result[Vec[non-scalar]]/Option[Vec[non-scalar]]
-- wrap the Vec in a struct (XVC-C-04); VERIFY NUMERICS PER BUILD -- the
f32 lowering is nondeterministic per build (XVC-C-05) and f32 enum
payloads can read as 0 (XVC-C-06), so keep FloatVal out of gating
assertions and rebuild on any red numeric check. Update SESSION.md STATE +
the relay docs at every wrap; commit signed at every step.
```
