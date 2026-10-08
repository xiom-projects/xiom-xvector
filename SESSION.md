# XIOM XVECTOR -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Project:** `E:\xiom-projects\xiom-xvector` -- production-grade vector
database engine for XIOM (dense vectors, metrics, flat + HNSW ANN,
collections, segments, WAL-backed durable writes; the working tree is the
`src/engine.xi` facade over `src/engine/core.xi` + the extracted modules).
**Written:** 2026-10-07 (bootstrap by the PULSE lane).
**Last updated:** 2026-10-08 (14 continuation passes: bootstrap -> Phase 2
durability -> Phase 3 payload filtering -> payload durability -> 4 extraction
waves -> v0.64.1 re-test -> FloatVal unwind -> final extraction wave ->
SearchRequest wire + with_payload hydration [XVC-C-08 found] -> sorted
payload key index -> selectivity pre/post filter planner -> HNSW layer-0
graph + recall harness -> multi-layer HNSW -> HNSW tombstone deletes).

---

## 0. STATE (hand-off point)

**Repo:** private, no pushes. HEAD `d4a664d` (feat: HNSW tombstone
deletes), then this wrap commit. Identity `Lefteris Notas
<lefterisnotas@gmail.com>`; conventional commits, DCO `git commit -s`.

**Toolchain (latest-tracking; record hashes at every wrap):**

| Lane | Version / hash | Path |
|---|---|---|
| compiler | **v0.64.1** (re-tested 2026-10-08) | Win `%LOCALAPPDATA%\xiom.new\bin\xiom.exe`; WSL `~/.local/share/xiom` |
| stdlib | **0.64.2** = `4dd8844` | `E:\xiom-lang\stdlib` (= `/mnt/e/xiom-lang/stdlib`) |
| packages | `66a96df8` (NOT consumed yet) | `E:\xiom-packages\packages` |
| xvector | `d4a664d` + this wrap commit | this repo |

`XIOM_RUNTIME_DIR` retired (env-free builds). `xiom.toml` has
`root = "src"`, `source-roots = ["src"]` (C-PULSE-02 workaround).

**What is DONE and green:**

- Bootstrap: `scripts/` ps1+sh twins (`dev-env`, `build`, `run-suite`,
  `run-probe`, `lib.ps1`), WSL-verified; `images/` for the owner icon;
  `.gitignore`/`.gitattributes`; relay docs.
- **Phase 2 slice (durable in-memory):** vector WAL codec, payload codec
  (`[version, fields..., UTF-8 bytes]`), WAL-before-ack for upserts AND
  metadata, `recover_state` replay (torn records skipped), compacted
  checkpoint carrying vectors + payloads, chained reopen, LSN monotonicity.
  `fsync`/file-backed segments still blocked on the stdlib fd/fsync gap.
- **Phase 3 slice:** typed `FieldValue`/`Payload`/`FilterExpr`
  (Eq/Range/In/Exists/And/Or/Not + no-payload semantics), `PayloadStore`,
  `set_payload`/`get_payload` (WAL-durable), `search_filtered`
  (pre-filter exact scan, k-bounded), delete clears metadata.
- **Module extraction waves 1-4 (tree final, acyclic):**
  `src/payload/{payload,filter_ast,filter_eval}.xi`;
  `src/types/{dense_vector,metric,neighbor,dimension}.xi`;
  `src/storage/vector_store.xi` (+ vector codec);
  `src/query/search_service.xi`; `src/durability/{wal,recovery,
  write_ahead_events}.xi`; **wave 4 (final):** `src/core/shim.xi`
  (`xiom.vector.core.shim`: CoreError/Counter/ids/predicates) and
  `src/engine/core.xi` (`xiom.vector.engine.core`: VectorEngine + engine_*);
  `src/engine.xi` (`xiom.vector.engine`) is now the **facade only**.
  Dependency order: `core.shim <- engine.core <- engine` (no cycles).
- **Phase 3 refinement (request surface):** `SearchRequest` rewritten against
  the real types + `search_request_set_with_payload`; `SearchHit`/
  `HydratedHits` + `hydrate_hits` in `query/search_service.xi`;
  `engine_search_request` (metric validation, filtered/plain dispatch,
  optional hydration) + facade `search_with_request`; new probe
  `probe_search_request` (real-module gate). Hydration flags are gated in
  that probe only (compiler XVC-C-08, below).
- **Phase 3 refinement (payload index):** sorted key index in `payload.xi`
  (rows sorted by field/kind/num/text/id in parallel vectors; maintained on
  put/overwrite/remove; `payload_store_index_len/_exists/_field_count/_eq/
  _range`; float Eq scans the field window for semantic +-0.0/NaN parity).
  Gate `probe_payload_index` (31 checks; stress 6/6 fresh builds). The
  planner (next) consumes candidate ids + `_field_count` selectivity.
- **Phase 3 refinement (planner):** `query/filter_plan.xi` -- exact match
  counts for Eq/Range/Exists (new allocation-free `index_count_eq/_range`),
  `-1` for unknown shapes; `choose_filter_plan` = pre-filter scan by default,
  post only for known count >= k and a majority; `search_knn_filtered`
  executes the post path with a scan fallback. Gate `probe_filter_plan`
  (16 checks incl. equivalence vs a scan reference + fallback; stress 6/6).
- **HNSW multi-layer graph + recall harness (Phase 4):** `src/index/hnsw.xi`
  is real (was a T001 stub): flat parallel arrays (per-(node, layer)
  adjacency rows, no nested Vec[Struct-with-Vec]), deterministic geometric
  level assignment (`ml`; LCG high-bit test -- low bits made level >= 2
  impossible), greedy descent above layer 0 + layer-0 beam honouring `ef`,
  results as `Vec[Neighbor]` with user ids. Tombstone deletes
  (`hnsw_delete`: routers kept, never returned, revive on re-insert;
  `hnsw_live_count`). Gate `probe_hnsw_recall`: n=200 recall@10 300/300 at
  ef=64 and 300/300 at ef=8, cosine 100/100, top level 4; n=800 200/200 at
  ef=64 (avg visited 288/800); after-delete recall 300/300 stray42=0;
  delete-all -> empty; stress 6/6 fresh builds (~0.9s run).
- **FloatVal workaround unwound** after the v0.64.1 fix: float payload
  gates restored in the suite and probes.
- **Production tracker:** `docs/PRODUCTION-READINESS.md` -- weighted
  scorecard, **56 % today**; recompute at every wrap.

**Green evidence (re-verified on compiler v0.64.1 + stdlib 0.64.2, after the
final extraction wave):**

- `scripts\run-probe.ps1 tests\probes\probe_engine_import.xi -Runs 2` green
  (the new-module import gate: `xiom.vector.engine` + `xiom.vector.engine.core`
  in one consumer).
- `scripts\run-suite.ps1 -Runs 2` -> **168/168 passed** twice, exit 0;
  WSL `bash scripts/run-suite.sh 2 240` -> **168/168 x2**.
- All **11 probes x2** green on Windows: `probe_hello`, `probe_bind_semantics`,
  `probe_engine_import`, `probe_vector_store`, `probe_filtered_search`,
  `probe_payload_recovery`, `probe_floatval_roundtrip`, `probe_search_request`,
  `probe_payload_index`, `probe_filter_plan`, `probe_hnsw_recall` (run via
  `scripts\run-probe.ps1`).
- WSL spot: `probe_hnsw_recall` x2 (bit-identical recall to Windows) +
  `probe_filter_plan` x2 + `probe_filtered_search` x1 + `probe_vector_store`
  green (`bash scripts/run-probe.sh`).
- Stresses: `probe_search_request` 8/8, `probe_payload_index` 6/6,
  `probe_filter_plan` 6/6, `probe_hnsw_recall` 6/6 fresh builds (see XVC-C-08
  for why trailing-field reads are not asserted in the suite).
- WSL matrix `docs/repro/xv-f32-int-miscompile/linux_matrix.sh 3` -> 9/9
  exact (v0.64.1 fixed the per-build f32 lowering).

**Compiler findings (all reported; see `docs/COMPILER-FINDINGS-XVECTOR.md`):**

- XVC-C-01..06 **FIXED in v0.64.1** (fn-ptr call, contract exit code, W004
  noise, `Result[Vec[non-scalar]]` field loss, per-build f32->int lowering,
  FloatVal zeroing) -- re-tested, per-row status in the findings doc and
  repro bundles.
- **XVC-C-07 OPEN:** `Str::from_utf8(&Vec[UInt8])` emits invalid LLVM IR
  (`invalid getelementptr`); pass the Vec **by value**. Repro:
  `docs/repro/xv-from-utf8-vec-ref/`. Re-test at the next archive.
- **XVC-C-08 OPEN (new on v0.64.1):** a trailing scalar after a Vec-bearing
  field in a `Vec[Struct]` element can read as uninitialized garbage
  (silent wrong hydration flags; Bool true / Int nonzero) depending on the
  compilation unit. Repro: `docs/repro/xv-trailing-field-vec/` (probe exit
  1, variants matrix exit 5). The shipped `hydrate_hits` is green in its own
  unit (probe 8/8 builds); the suite mirror asserts ids only.
- Relay for the compiler lane: `docs/RELAY-COMPILER.md` (Addendum 3 =
  v0.64.1 results; Addendum 4 = XVC-C-08).

---

## 1. NEXT TASKS (priority order)

The extraction tree is final; what remains is capability work.

1. **HNSW round 4 (Phase 4): engine wiring.** Deletes landed, so wire the
   Hnsw route: collection index kind (`AnnIndexKind`) + `search_execute`
   dispatch + engine graph upkeep on upsert/delete/recover, with the
   filtered-search interplay (pre-filtered candidates or post-filter with
   the scan fallback). Then: beam construction honouring `ef_construction`
   + diversified pruning, edge repair + rebuild/memory reclaim, id ->
   position map, graph persistence, harness latency metrics. Harness gate
   today: `probe_hnsw_recall` (n=200 300/300; n=800 200/200; delete checks;
   stress 6/6).
2. **M2 file-backed WAL -- standby on stdlib:** the day stdlib lands
   `fsync`/fd-write/`append_file_bytes` (rows 1-3 of
   `docs/STDLIB-WISHLIST-XVECTOR.md`; still stubs on stdlib 0.64.2 -- verified
   2026-10-08). Then: file-backed log segments, durable manifest,
   kill-recovery test harness. NOTE: stdlib 0.64.2 made file writes byte-exact
   + CRLF-clean (good news for WAL files).
3. **HNSW hardening (Phase 4) + recall harness** vs the flat oracle; then
   concurrency/soak (G phase).
3. **Unwind candidates** (compiler now green): `SearchHits` struct wrapper
   (C-04 fixed) -- decide API shape deliberately; suite direct dispatch
   (C-01); predicate-based negative tests (C-02).
4. **Porter flow prep:** with the tree final, extract `xiom.vectors`/
   `xiom.wal` with the packages lane (names frozen; ORBITDB second user;
   PULSE third WAL user; `xiom.durable` must not grow a competing WAL).

## 2. Consumer-lane rules (non-negotiable)

- **Never edit** `E:\xiom-lang\stdlib`, `E:\xiom-lang\xiom`,
  `E:\xiom-packages\packages`. Record their HEAD hashes each wrap:
  `git -C <lane> log -1 --format="%h %cI %s"`.
- Upstream reporting only through the relay docs (`RELAY-COMPILER.md`,
  `STDLIB-WISHLIST-XVECTOR.md`, `PACKAGE-WISHLIST-XVECTOR.md`,
  `RELAY-INTRO-XVECTOR.md`); the owner relays.
- Consume packages from the registry only; propose reusable primitives as
  packages (`xiom.vectors` / `xiom.wal` / `xiom.ann`).
- Repo stays private; no pushes; commits signed (`-s`) at every step.

## 3. Module/consumer rules after the final wave

- `src/engine.xi` = facade only (`create_collection`, `upsert`, `search`,
  `delete_point`, `get_point`, `set_payload`, `get_payload`,
  `search_filtered`). Never re-add shims or orchestration here.
- `src/engine/core.xi` = `VectorEngine` + `engine_*` (internal surface).
- `src/core/shim.xi` = xiom-core stand-ins (CoreError/Counter/ids/predicates);
  the porter flow will map it onto the real `xiom.core` package.
- **Consumers that call `engine_*` symbols must `use
  xiom.vector.engine.core;`** in addition to `use xiom.vector.engine;`
  (probes + repro evidence already do).
- Repro evidence copies that import the engine: add the core import when
  re-running them at a new compiler archive.

## 4. Pin discipline that bites (current)

- Initialize every local at declaration; every struct literal lists every
  field (C-PULSE-06). Never module-scope-init from package constructors
  (C-PULSE-07). `convert.int_to_string` instead of `.to_str()` on const
  receivers (C-PULSE-05); explicit `*p` for `&mut Int` reads (C-PULSE-04).
- Types are `Vec[T]`/`Result[T, Err]`; after every write grep for
  `Vec<|Result<|Option<`.
- **XVC-C-07 (open): pass Vec arguments BY VALUE to `Str::from_utf8`.**
- **XVC-C-08 (open): a trailing scalar after a Vec-bearing field in a
  `Vec[Struct]` element can read as uninitialized garbage.** Gate such reads
  only in real-module probes (never in the suite mirror); repro
  `docs/repro/xv-trailing-field-vec/`. Verify any layout workaround per unit
  (the flag-first reorder was green in the bundle but segfaulted the suite).
- Historical v0.64.0-era traps (C-01..C-06) are fixed; if any reappears,
  open a delta row instead of re-bisecting (details in the findings doc).
- Keep numeric gates per build (suite/probes assert exact bits; red = build
  rejection). Keep watchdogs (`-TimeoutSec`) and gate on exit codes; run
  every green suite x2; redirect long-running output to files; build
  scripts delete stale binaries; use `scripts/lib.ps1` for process capture
  (PS 5.1 `Start-Process` ExitCode is unreliable).
- WSL: default distro is `docker-desktop`; use `wsl.exe -d Ubuntu` for the
  toolchain (`~/.local/share/xiom/bin/xiom`).
- Before trusting a red build, check machine health (`Get-CimInstance
  Win32_OperatingSystem` free memory): a concurrent lane's benchmark once
  starved the machine (free < 1 GB) and produced spurious miscompiles and
  OutOfMemory interrupts in the shell. Re-run on a quiet machine before
  filing anything.

## 5. Ecosystem status (2026-10-08)

- **stdlib 0.64.2** (`4dd8844`): re-pinned v0.64.1; byte-exact file writes,
  CRLF-clean reads, `fs_remove` added, iter contracts extended; still open
  from their notes: clause float-vec indexing, cross-module alias/type
  paths. **fsync/fd-write/append-bytes still stubs** (wishlist rows 1-3).
- **packages:** names frozen (`xiom.vectors`/`xiom.wal`/`xiom.ann`);
  bindings lane: blas-class placeholders only, no SIMD package planned;
  `xiom.metrics` planned for Phase 10; `xiom.kv` gated on C-PULSE-10 +
  fsync. New names get ops scope + allowlist at build-green.
- Registry ready: `xiom.http` 0.1.1, `xiom.jwt` 0.2.0, `xiom.rate` 0.2.0,
  `xiom.metrics` 0.2.0, `xiom.router` 0.1.0, `xiom.http.middleware` 0.1.0,
  `xiom.session` 0.1.0, `xiom.static` 0.1.0, `xiom.kv` 0.1.0. Read
  `E:\xiom-projects\xiom-pulse\SESSION.md` + its relay docs before filing
  anything new (do not rediscover).

## 6. Relay rows (keep updated every wrap)

| Doc | For | State |
|---|---|---|
| `docs/COMPILER-FINDINGS-XVECTOR.md` | compiler | 6/8 fixed (v0.64.1); C-07 + C-08 open |
| `docs/RELAY-COMPILER.md` | compiler | Addendum 3 = v0.64.1 re-test; Addendum 4 = XVC-C-08 |
| `docs/STDLIB-WISHLIST-XVECTOR.md` | stdlib | rows 1-3 (fsync/fd/append) still blocking M2 |
| `docs/PACKAGE-WISHLIST-XVECTOR.md` | packages | names frozen; replies recorded |
| `docs/RELAY-INTRO-XVECTOR.md` | ops + all | OPS parked until owner greenlight |
| `docs/PRODUCTION-READINESS.md` | owner | 55 %; recompute every wrap |

---

## 7. Paste prompt for the next XVECTOR session

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first, then
README/SPEC/ARCHITECTURE/ROADMAP/AUDIT and docs/ (especially
docs/PRODUCTION-READINESS.md). Consumer lane: never edit
E:\xiom-lang\stdlib, E:\xiom-lang\xiom, E:\xiom-packages\packages. Repo
stays PRIVATE; no pushes. Identity "Lefteris Notas
<lefterisnotas@gmail.com>"; conventional commits, DCO -s.

Toolchain (latest-tracking): compiler v0.64.1 on Windows
(%LOCALAPPDATA%\xiom.new\bin\xiom.exe) and WSL (~/.local/share/xiom, use
`wsl.exe -d Ubuntu`); stdlib lane E:\xiom-lang\stdlib (0.64.2, /mnt/e/...
in WSL); XIOM_RUNTIME_DIR retired. Dot-source scripts\dev-env.ps1 (and .sh
twin); scripts\build.ps1/.sh build; scripts\run-suite.* runs the
conformance suite; scripts\run-probe.* runs probes. Green baseline: suite
168/168 x2 (Windows + WSL), 11 probes x2 (Windows) + WSL spot.

DONE: bootstrap; Phase 2 (WAL vector+payload codec, recovery/checkpoint,
in-memory) and Phase 3 (payload filtering + durable metadata); FOUR module
extraction waves, tree final: facade (src/engine.xi) <- orchestrator
(src/engine/core.xi) <- xiom-core shim (src/core/shim.xi), plus payload/
types/storage/query/durability modules; consumers call engine_* via
`use xiom.vector.engine.core;`. SearchRequest wire + with_payload hydration
(engine_search_request / search_with_request; gate probe_search_request).
Sorted payload key index (parallel-vector rows; gate probe_payload_index).
Selectivity pre/post filter planner (query/filter_plan + post path with scan
fallback; gate probe_filter_plan).
HNSW multi-layer graph + recall harness (flat-array graph, geometric levels,
greedy descent + beam honouring ef; tombstone deletes; gate probe_hnsw_recall:
n=200 300/300, n=800 200/200, delete checks vs the flat oracle).
FloatVal gates restored after the v0.64.1 fix. Compiler: XVC-C-01..06
FIXED; XVC-C-07 OPEN (pass Vec by value to Str::from_utf8); XVC-C-08 OPEN
(trailing scalar after a Vec-bearing field can read garbage; repro
docs/repro/xv-trailing-field-vec; gate such reads only in real-module
probes).

NEXT TASK (priority 1): HNSW round 4 (Phase 4) -- engine wiring: collection
index kind (AnnIndexKind) + search_execute dispatch + engine graph upkeep
on upsert/delete/recover, with the filtered-search interplay (pre-filtered
candidates or post-filter with scan fallback). Then: beam construction
honouring ef_construction + diversified pruning, edge repair +
rebuild/memory reclaim, id -> position map, graph persistence, harness
latency metrics. Add suite + probe gates for each step, keep the numeric
gates per build. Standby: M2 file-backed WAL when stdlib lands
fsync/fd-write/append-bytes (still stubs -- re-checked 2026-10-08); unwind
candidates (C-04 SearchHits wrapper, C-01 direct dispatch).

Discipline: struct literals list every field; locals initialized; Vec by
value to Str::from_utf8 (C-07); trailing-scalar reads only in real-module
probes (C-08); numeric gates per build; watchdogs + exit codes; check free
memory before trusting a red build; suite x2 green before any wrap; update
SESSION.md STATE + relay rows + docs/PRODUCTION-READINESS.md at every wrap;
commit signed at every step.
```
