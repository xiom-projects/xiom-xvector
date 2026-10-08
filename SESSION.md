# XIOM XVECTOR -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Written:** 2026-10-07 (bootstrap by the PULSE lane, owner request).
**Updated:** 2026-10-08 (first XVECTOR session: bootstrap executed + Phase 2
durability slice; continuation same day: Phase 3 payload filtering +
XVC-C-06; second continuation: durable payloads + XVC-C-07 + production
readiness tracker).
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
  - compiler: **v0.64.1** (re-pinned 2026-10-08 after the release),
    Windows `%LOCALAPPDATA%\xiom.new\bin\xiom.exe`,
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
  - Suite **165/165 x2**; new probe `tests/probes/probe_filtered_search.xi`
    green x2 (engine-import unit; FloatVal is diagnostic-only -- XVC-C-06).
- **Payload durability (second continuation):**
  - `payload_encode`/`payload_decode` (word codec: version, field count,
    UTF-8 key/value bytes, Float64-bit floats; strict, malformed -> None);
    `log_payload_set` appends `WalOpKind.Update` records; `engine_set_payload`
    is WAL-before-ack; `recover_state` replays store + payloads in LSN order
    (Delete clears metadata); the compacted checkpoint carries payloads so
    chained reopen keeps metadata.
  - Probes: `tests/probes/probe_payload_recovery.xi` green x2 (payload replay,
    chained overwrite, delete cleanup, filtered search on the recovered
    engine, torn-record skip).
  - Suite: SECTION 15 (9 tests) -> **165/165 x2**; readiness tracker
    `docs/PRODUCTION-READINESS.md` created (weighted scorecard; ~53 % today).
- **Module extraction milestone 3 (fifth continuation):** the durability
  layer is real too: `src/durability/wal.xi` (WalOpKind/WalRecord/WalWriter +
  append/append_payload/current_lsn/flush/resume), `src/durability/recovery.xi`
  (recover_state/recover_store + wal_writer_checkpoint_from),
  `src/durability/write_ahead_events.xi` (log_upsert/log_delete/
  log_payload_set). `engine.xi` now holds only: core-error/counter/ids,
  validity predicates, `engine_recover`, `VectorEngine` + `engine_*`, and the
  API facade. Suite 165/165 x2 (Windows + WSL) and Windows probes x2 green;
  WSL `probe_vector_store` drew 1 green / 2 red across 3 fresh builds --
  exactly the XVC-C-05 numeric-draw signature (the diag prints the int
  bit-pattern dot), not a regression (the suite and non-numeric checks stay
  green).
- **Module extraction milestone 2 (fourth continuation):** the types /
  storage / search layers are now real modules too:
  `src/types/dense_vector.xi` (Vector + dot/magnitude),
  `src/types/metric.xi` (DistanceMetric + 3 distances + dispatch),
  `src/types/neighbor.xi`, `src/storage/vector_store.xi` (VectorIndex CRUD +
  vector WAL codec), `src/query/search_service.xi` (SearchResult/SearchHits +
  search_knn/search_knn_filtered). All probes x2 + suite 165/165 green.
- **Module extraction milestone 1 (third continuation):** the payload/filter
  layer is now the first REAL module of the post-AUDIT tree --
  `src/payload/payload.xi` (FieldValue/Payload + codec + PayloadStore),
  `src/payload/filter_ast.xi` (FilterExpr + constructors),
  `src/payload/filter_eval.xi` (typed eval + payload_store_matches).
  All probes x2 + suite 165/165 x2 green after the extraction.
- **Green evidence (exact commands):**
  - `scripts\run-suite.ps1 -Runs 2` -> `165/165 passed` twice, exit 0,
    stderr 0; same on WSL: `bash scripts/run-suite.sh 2 180`.
  - `scripts\run-probe.ps1 tests\probes\probe_vector_store.xi -Runs 2`,
    `...probe_filtered_search.xi...`, `...probe_payload_recovery.xi...` ->
    0 failed checks x2 (rebuild-on-red discipline for XVC-C-05/06 draws).
  - `bash scripts/run-probe.sh tests/probes/probe_hello.xi 2 60` green in WSL.
  - `probe_engine_import` green (cross-file module import).
  - Every build is numerically re-verified (XVC-C-05 rule; the
    filtered-search probe draws red builds ~1 in 3 -- rebuild, don't trust).
- **Compiler re-test on v0.64.1 (sixth continuation): 6 of 7 findings FIXED**
  (XVC-C-01 invalid IR/crash, C-02 contract exit 0, C-03 W004 noise,
  C-04 Result[Vec[non-scalar]] field loss, C-05 per-build f32->int lowering,
  C-06 FloatVal payload zeroing); **XVC-C-07 OPEN**
  (`Str::from_utf8(&Vec)` invalid getelementptr; pass by value still required).
  Regression on v0.64.1: suite 165/165 x2 (Windows + WSL), all five probes
  x2 (new pin probe `probe_floatval_roundtrip.xi`), WSL matrix 9/9 exact.
  Workarounds left in place as unwind candidates (see findings doc).
- **New compiler findings this session (details in the relay doc):**
  XVC-C-01 `&fn()` call miscompile (invalid IR / runtime crash);
  XVC-C-02 runtime contract violation exits 0;
  XVC-C-03 W004 false unreachable-arm on unit enums;
  XVC-C-04 `Result[Vec[non-scalar]]` / `Option[Vec[non-scalar]]` payload
  field loss (struct wrapper workaround adopted);
  XVC-C-05 per-build nondeterministic Float32 -> integer bit-pattern
  lowering (no reliable flag workaround; verify numerics per build);
  XVC-C-06 Float32 enum payloads can read as 0 in affected builds
  (FloatVal gates avoided; diagnostic-only in the probe);
  XVC-C-07 `Str::from_utf8(&Vec[UInt8])` emits invalid LLVM IR -- pass the
  Vec by value (found in the payload codec; repro
  `docs/repro/xv-from-utf8-vec-ref/`).
- **stdlib status:** fsync/fdatasync still documented-Err stubs
  (`xiom/os/fs_ffi.xi:238`, `xiom/os/sync_io.xi:80`) -- Phase 2 file-backed
  WAL blocked; byte append (`append_file_bytes`) and fd write path missing;
  `crc32_ieee`/`crc32c` available and adopted for framing.
- **Next action (priority order):**
  1. Final extraction wave: move `VectorEngine` + `engine_*` + the API facade
     into `src/engine.xi`-style modules (`src/engine/engine.xi`,
     `src/api/vector_api.xi`), keep `src/engine.xi` as the thin facade (or
     retarget consumers to the modules), possibly move core-error/ids/counter
     to a `src/core/` shim. Then the tree is porter-ready.
  2. Phase 3 refinements: sorted key index (O(log n) lookup), pre/post-filter
     planner, `SearchRequest`-driven search + `with_payload` hydration.
  3. Compiler: v0.64.1 fixed XVC-C-01..06; **C-07 still open** (re-test
     `docs/repro/xv-from-utf8-vec-ref/` at the next archive). Optional:
     unwind the old workarounds now that the pin is green (restore FloatVal
     gates, consider unwrapping `SearchHits`). When fsync lands, implement
     file-backed WAL segments + durable manifest (Phase 2 exit criteria;
     stdlib wishlist rows 1-3).
  4. HNSW hardening (Phase 4) + recall harness; concurrency/soak next.

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

## 2. Pin discipline that bites (current pin v0.64.1; extended this session)

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
- **Historical v0.64.0-era traps (fixed in v0.64.1; kept for regression
  triage):** `&fn()` parameter calls emitted invalid IR / crashed
  (XVC-C-01); contract violations exited 0 (XVC-C-02); W004 false-positive
  arms (XVC-C-03); `Result[Vec[non-scalar]]` / `Option[Vec[non-scalar]]`
  payloads lost element fields (XVC-C-04); f32 ops lowered as integer bit
  patterns per build (XVC-C-05); FloatVal enum payloads read 0 (XVC-C-06).
  If any reappears, open a delta row instead of re-bisecting.
  Lane workarounds stay in place as documented unwind candidates
  (`SearchHits` wrapper, direct dispatch, predicate-based negative tests,
  FloatVal diagnostics).
- **XVC-C-07 still open:** pass Vec arguments **by value** to
  `Str::from_utf8` (`&Vec[UInt8]` -> invalid getelementptr).
- **Keep numeric gates per build** as general hygiene: the suite and probes
  assert exact bits; treat any red numeric check as a build rejection.
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

- Compiler findings relevant here: C-PULSE-02 (registry deps ->
  catalog roots; workaround `source-roots`), C-PULSE-04..07; PULSE
  C-PULSE-08..12; XVECTOR's XVC-C-01..06 are FIXED as of v0.64.1
  (re-tested), XVC-C-07 remains open (pass `Vec` by value to
  `Str::from_utf8`). C-PULSE-01 resolved on v0.64.0.
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

Toolchain (latest-tracking): compiler v0.64.1 on Windows
(%LOCALAPPDATA%\xiom.new\bin\xiom.exe) and WSL Ubuntu
(~/.local/share/xiom), stdlib lane E:\xiom-lang\stdlib (= /mnt/e/... in WSL),
XIOM_RUNTIME_DIR retired. Dot-source scripts\dev-env.ps1 (and its .sh
twin); build with scripts\build.ps1 / scripts\build.sh; suites via
scripts\run-suite.*; the critical probe is
tests\probes\probe_vector_store.xi (run via scripts\run-probe.*).

Bootstrap is DONE; Phase 2 (WAL vector+payload codec, recovery/checkpoint)
and Phase 3 (payload filtering + durable metadata) are implemented; the
suite is 165/165 x2 on both platforms. Three extraction waves are done
(payload, types/storage/query, durability); engine.xi is the thin
orchestration facade. Progress is measured by docs/PRODUCTION-READINESS.md
(weighted scorecard, ~54% today) -- recompute it at every wrap. Next:
final extraction wave (engine/core + API modules), then sorted payload
index + planner; file-backed WAL waits on the stdlib fsync gap; then HNSW
hardening.

Compiler status: v0.64.1 fixed XVC-C-01..06 (re-tested; see
docs/COMPILER-FINDINGS-XVECTOR.md); XVC-C-07 is still open -- pass Vec
arguments BY VALUE to `Str::from_utf8`. Keep numeric gates per build as
hygiene (suite/probes assert exact bits; red = build rejection). Update
SESSION.md STATE + the relay docs at every wrap; commit signed at every
step.
```
