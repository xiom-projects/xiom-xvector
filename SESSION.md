# XIOM XVECTOR -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Project:** `E:\xiom-projects\xiom-xvector` -- production-grade vector
database engine for XIOM (dense vectors, metrics, flat + HNSW ANN,
collections, segments, WAL-backed durable writes; the working core is in
`src/engine.xi` + the extracted modules).
**Written:** 2026-10-07 (bootstrap by the PULSE lane).
**Last updated:** 2026-10-08 (clean handoff after 7 continuation passes:
bootstrap -> Phase 2 durability -> Phase 3 payload filtering -> payload
durability -> 3 extraction waves -> v0.64.1 re-test -> FloatVal unwind).

---

## 0. STATE (hand-off point)

**Repo:** private, no pushes. HEAD `a60966c` (then this handoff commit).
Identity `Lefteris Notas <lefterisnotas@gmail.com>`; conventional commits,
DCO `git commit -s`.

**Toolchain (latest-tracking; record hashes at every wrap):**

| Lane | Version / hash | Path |
|---|---|---|
| compiler | **v0.64.1** (re-tested 2026-10-08) | Win `%LOCALAPPDATA%\xiom.new\bin\xiom.exe`; WSL `~/.local/share/xiom` |
| stdlib | **0.64.2** = `4dd8844` | `E:\xiom-lang\stdlib` (= `/mnt/e/xiom-lang/stdlib`) |
| packages | `66a96df8` (NOT consumed yet) | `E:\xiom-packages\packages` |
| xvector | `a60966c` + handoff commit | this repo |

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
- **Module extraction waves 1-3:** real modules with `engine.xi` importing
  them -- `src/payload/{payload,filter_ast,filter_eval}.xi`;
  `src/types/{dense_vector,metric,neighbor}.xi`;
  `src/storage/vector_store.xi` (+ vector codec);
  `src/query/search_service.xi`; `src/durability/{wal,recovery,
  write_ahead_events}.xi`.
- **FloatVal workaround unwound** after the v0.64.1 fix: float payload
  gates restored in the suite and probes.
- **Production tracker:** `docs/PRODUCTION-READINESS.md` -- weighted
  scorecard, **54 % today**; recompute at every wrap.

**Green evidence (re-verified on compiler v0.64.1 + stdlib 0.64.2):**

- `scripts\run-suite.ps1 -Runs 2` -> **166/166 passed** twice, exit 0;
  WSL `bash scripts/run-suite.sh 2 240` -> **166/166 x2**.
- Probes x2 all green: `probe_hello`, `probe_engine_import`,
  `probe_vector_store`, `probe_filtered_search`, `probe_payload_recovery`,
  `probe_floatval_roundtrip` (run via `scripts\run-probe.ps1` /
  `bash scripts/run-probe.sh`).
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
- Relay for the compiler lane: `docs/RELAY-COMPILER.md` (Addendum 3 has the
  v0.64.1 results).

---

## 1. NEXT TASK -- final extraction wave (priority 1)

Close the post-AUDIT tree with `engine.xi` left as the consumer-facing
facade. Planned layout (avoids circular imports):

1. **`src/core/shim.xi`** (module `xiom.vector.core.shim`): `CoreError`,
   `Counter` + `counter_new/inc`, `CollectionId`/`VectorId`/`SegmentId` +
   helpers, `is_valid_dimension`/`is_valid_top_k`. (These are the
   xiom-core stand-ins; the porter flow will later map them onto the real
   package.)
2. **`src/engine/core.xi`** (module `xiom.vector.engine.core`): `VectorEngine`
   + `engine_new`, `engine_create_collection`, `engine_upsert`,
   `engine_search`, `engine_delete`, `engine_set_payload`,
   `engine_get_payload`, `engine_search_filtered`, `engine_recover`,
   `engine_size`, `engine_durable_lsn`. Imports `core.shim` + all extracted
   layers.
3. **`src/engine.xi`** (module `xiom.vector.engine`) keeps ONLY the public
   facade: `create_collection`, `upsert`, `search`, `delete_point`,
   `get_point`, `set_payload`, `get_payload`, `search_filtered` --
   delegating to `engine.core`. Do NOT keep shims here (shim <- core <-
   facade must stay acyclic).
4. **Consumers:** probes/evidence that call `engine_*` symbols
   (`probe_vector_store`, `probe_filtered_search`, `probe_payload_recovery`,
   the `docs/repro/xv-f32-*` evidence copies) gain
   `use xiom.vector.engine.core;`; facade users keep
   `use xiom.vector.engine;`. Batch-edit script pattern used before works.
5. **Verify:** engine import probe -> suite x2 -> all probes x2 -> WSL spot;
   then docs (ARCHITECTURE tree + note, SPEC engine section, SESSION,
   readiness J bump).

Fallback if the split tangles (e.g., cross-module `CoreError` type identity
in `Result` signatures): move only the facade to
`src/api/vector_api.xi` and keep `engine_*` in `engine.xi`.

## 2. FOLLOW-UPS (after the extraction wave)

1. **Phase 3 refinements:** sorted key index (O(log n) field lookup),
   pre/post-filter planner, `SearchRequest`-driven search +
   `with_payload` hydration.
2. **Unwind candidates** (compiler now green): `SearchHits` struct wrapper
   (C-04 fixed) -- decide API shape deliberately; suite direct dispatch
   (C-01); predicate-based negative tests (C-02).
3. **M2 file-backed WAL** the day the stdlib lands `fsync`/fd-write/
   `append_file_bytes` (rows 1-3 of `docs/STDLIB-WISHLIST-XVECTOR.md`;
   still stubs on stdlib 0.64.2 -- verified 2026-10-08). Then: durable
   manifest, kill-recovery test harness. NOTE: stdlib 0.64.2 made file
   writes byte-exact + CRLF-clean (good news for WAL files).
4. **HNSW hardening (Phase 4) + recall harness** vs the flat oracle;
   then concurrency/soak (G phase).
5. **Porter flow prep:** when the tree is final, extract
   `xiom.vectors`/`xiom.wal` with the packages lane (names frozen;
   ORBITDB second user; PULSE third WAL user; `xiom.durable` must not grow
   a competing WAL).

## 3. Consumer-lane rules (non-negotiable)

- **Never edit** `E:\xiom-lang\stdlib`, `E:\xiom-lang\xiom`,
  `E:\xiom-packages\packages`. Record their HEAD hashes each wrap:
  `git -C <lane> log -1 --format="%h %cI %s"`.
- Upstream reporting only through the relay docs (`RELAY-COMPILER.md`,
  `STDLIB-WISHLIST-XVECTOR.md`, `PACKAGE-WISHLIST-XVECTOR.md`,
  `RELAY-INTRO-XVECTOR.md`); the owner relays.
- Consume packages from the registry only; propose reusable primitives as
  packages (`xiom.vectors` / `xiom.wal` / `xiom.ann`).
- Repo stays private; no pushes; commits signed (`-s`) at every step.

## 4. Pin discipline that bites (current)

- Initialize every local at declaration; every struct literal lists every
  field (C-PULSE-06). Never module-scope-init from package constructors
  (C-PULSE-07). `convert.int_to_string` instead of `.to_str()` on const
  receivers (C-PULSE-05); explicit `*p` for `&mut Int` reads (C-PULSE-04).
- Types are `Vec[T]`/`Result[T, Err]`; after every write grep for
  `Vec<|Result<|Option<`.
- **XVC-C-07 (open): pass Vec arguments BY VALUE to `Str::from_utf8`.**
- Historical v0.64.0-era traps (C-01..C-06) are fixed; if any reappears,
  open a delta row instead of re-bisecting (details in the findings doc).
- Keep numeric gates per build (suite/probes assert exact bits; red = build
  rejection). Keep watchdogs (`-TimeoutSec`) and gate on exit codes; run
  every green suite x2; redirect long-running output to files; build
  scripts delete stale binaries; use `scripts/lib.ps1` for process capture
  (PS 5.1 `Start-Process` ExitCode is unreliable).

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
| `docs/COMPILER-FINDINGS-XVECTOR.md` | compiler | 6/7 fixed (v0.64.1); C-07 open |
| `docs/RELAY-COMPILER.md` | compiler | Addendum 3 = v0.64.1 re-test results |
| `docs/STDLIB-WISHLIST-XVECTOR.md` | stdlib | rows 1-3 (fsync/fd/append) still blocking M2 |
| `docs/PACKAGE-WISHLIST-XVECTOR.md` | packages | names frozen; replies recorded |
| `docs/RELAY-INTRO-XVECTOR.md` | ops + all | OPS parked until owner greenlight |
| `docs/PRODUCTION-READINESS.md` | owner | 54 %; recompute every wrap |

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
(%LOCALAPPDATA%\xiom.new\bin\xiom.exe) and WSL (~/.local/share/xiom);
stdlib lane E:\xiom-lang\stdlib (0.64.2, /mnt/e/... in WSL);
XIOM_RUNTIME_DIR retired. Dot-source scripts\dev-env.ps1 (and .sh twin);
scripts\build.ps1/.sh build; scripts\run-suite.* runs the conformance
suite; scripts\run-probe.* runs probes. Green baseline: suite 166/166 x2
(Windows + WSL), six probes green.

DONE: bootstrap; Phase 2 (WAL vector+payload codec, recovery/checkpoint,
in-memory) and Phase 3 (payload filtering + durable metadata); three
module extraction waves (payload, types/storage/query, durability);
FloatVal gates restored after the v0.64.1 fix. Compiler: XVC-C-01..06
FIXED, XVC-C-07 OPEN (pass Vec by value to Str::from_utf8).

NEXT TASK (priority 1): final extraction wave -- move VectorEngine +
engine_* into src/engine/core.xi (module xiom.vector.engine.core), core
shims (CoreError/Counter/ids/predicates) into src/core/shim.xi, keep
src/engine.xi as the facade only (no shims there; acyclic: shim <- core <-
facade). Add `use xiom.vector.engine.core;` to consumers that call
engine_* symbols. Verify: engine-import probe, suite x2, all probes x2,
WSL spot; update ARCHITECTURE/SPEC/SESSION/readiness; commit signed.
Fallback if the split tangles: move only the facade to
src/api/vector_api.xi. Then follows: Phase 3 refinements (sorted payload
index, pre/post planner, SearchRequest/with_payload); M2 file-backed WAL
when stdlib lands fsync/fd-write/append-bytes (still stubs); HNSW
hardening + recall harness.

Discipline: struct literals list every field; locals initialized; Vec by
value to Str::from_utf8 (C-07); numeric gates per build; watchdogs + exit
codes; suite x2 green before any wrap; update SESSION.md STATE + relay
rows + docs/PRODUCTION-READINESS.md at every wrap; commit signed at every
step.
```
