# XIOM XVECTOR -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Project:** `E:\xiom-projects\xiom-xvector` -- production-grade vector
database engine for XIOM (dense vectors, metrics, flat + HNSW ANN,
collections, segments, WAL-backed durable writes; the working tree is the
`src/engine.xi` facade over `src/engine/core.xi` + the extracted modules).
**Written:** 2026-10-07 (bootstrap by the PULSE lane).
**Last updated:** 2026-10-09 (30 continuation passes: bootstrap -> Phase 2
durability -> Phase 3 payload filtering -> payload durability -> 4 extraction
waves -> v0.64.1 re-test -> FloatVal unwind -> final extraction wave ->
SearchRequest wire + with_payload hydration [XVC-C-08 found] -> sorted
payload key index -> selectivity pre/post filter planner -> HNSW layer-0
graph + recall harness -> multi-layer HNSW -> HNSW tombstone deletes ->
engine HNSW wiring -> HNSW tombstone compaction -> HNSW graph codec ->
beam construction + diversified pruning -> HNSW id map [XVC-C-09 found] ->
shape pins + unwind decision -> HNSW+filter integration -> fuzz gate +
decoder hardening [XVC-C-10 found] -> mixed-workload soak -> latency metrics
+ release-prep drafts -> upsert fix + index-driven candidates -> durable
collection manifest -> HNSW update re-linking -> kill-recovery acceptance ->
multi-key intersections -> file-backed WAL whole-file checkpoint [XVC-C-11/C-12
found]).

---

## 0. STATE (hand-off point)

**Repo:** private, no pushes. HEAD `c84ccbc` (feat: file-backed WAL --
whole-file checkpoint codec + torn-tail load), then this wrap commit;
preceded by `d7097ce`/`63dd1ea` (multi-key intersections). Identity
`Lefteris Notas <lefterisnotas@gmail.com>`; conventional commits, DCO
`git commit -s`.

**Toolchain (latest-tracking; record hashes at every wrap):**

| Lane | Version / hash | Path |
|---|---|---|
| compiler | **v0.64.1** installed; **v0.64.2 announced release-ready** (relay 2026-10-09, tag held for owner -- re-test at tag) | Win `%LOCALAPPDATA%\xiom.new\bin\xiom.exe`; WSL `~/.local/share/xiom` |
| stdlib | lane HEAD `d54929d` (wave 97, 2026-10-09); the consumed release for the v0.64.1 re-test was **0.64.2** = `4dd8844` | `E:\xiom-lang\stdlib` (= `/mnt/e/xiom-lang/stdlib`) |
| packages | `66a96df8` (NOT consumed yet) | `E:\xiom-packages\packages` |
| xvector | `c84ccbc` + this wrap commit | this repo |

`XIOM_RUNTIME_DIR` retired (env-free builds). `xiom.toml` has
`root = "src"`, `source-roots = ["src"]` (C-PULSE-02 workaround).

**What is DONE and green:**

- Bootstrap: `scripts/` ps1+sh twins (`dev-env`, `build`, `run-suite`,
  `run-probe`, `lib.ps1`), WSL-verified; `images/` for the owner icon;
  `.gitignore`/`.gitattributes`; relay docs.
- **Phase 2 slice (durable in-memory + whole-file WAL):** vector WAL codec,
  payload codec (`[version, fields..., UTF-8 bytes]`), WAL-before-ack for
  upserts AND metadata, `recover_state` replay (torn records skipped),
  compacted checkpoint carrying vectors + payloads, chained reopen, LSN
  monotonicity; whole-file WAL checkpoint on disk landed 2026-10-09 (see
  below). `fsync`/append + file-backed segments still blocked on the stdlib
  fd/fsync gap.
- **Phase 3 slice:** typed `FieldValue`/`Payload`/`FilterExpr`
  (Eq/Range/In/Exists/And/Or/Not + no-payload semantics), `PayloadStore`,
  `set_payload`/`get_payload` (WAL-durable), `search_filtered`
  (pre-filter exact scan, k-bounded), delete clears metadata.
- **Module extraction waves 1-4 (tree final, acyclic):**
  `src/payload/{payload,filter_ast,filter_eval}.xi`;
  `src/types/{dense_vector,metric,neighbor,dimension}.xi`;
  `src/storage/vector_store.xi` (+ vector codec);
  `src/query/search_service.xi`; `src/durability/{wal,recovery,
  write_ahead_events}.xi` (+ `wal_file.xi` 2026-10-09); **wave 4 (final):**
  `src/core/shim.xi`
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
- **Engine HNSW wiring (Phase 4):** `VectorEngine` owns `graph/index_kind/
  ann`; `set_index(kind, params)` validates and builds the graph from the
  flat store; `engine_upsert` feeds `hnsw_insert_ref`, `engine_delete`
  tombstones the graph, `engine_search` + the request plain path route
  through `hnsw_search` (`ef = ann.ef_search`); filtered search stays the
  exact flat scan. In-memory only -- re-apply after `engine_recover`. Gate
  `probe_engine_hnsw`: two engines (flat oracle vs Hnsw) over 150 points,
  engine recall 200/200, delete/revive, filtered exact, Flat switch
  bit-identical, invalid params Err, recover + re-apply; stress 6/6.
- **HNSW compaction:** `hnsw_compact(g, metric)` rebuilds from live nodes
  only (tombstones dropped, edges rebuilt, slots reclaimed); engine
  `compact_index` (Flat -> `Ok(0)`, returns reclaimed). Gates: compact-all
  -> empty graph; 50 deletes -> size/live 150 with recall 200/200 and
  stray_deleted=0; engine-level reclaim 1 + post-compact recall holds.
- **HNSW graph codec:** `hnsw_encode`/`hnsw_decode` (deterministic word
  stream, strict decode: malformed/truncated/tampered -> None; version 2
  carries ef_construction). Gate `probe_hnsw_codec` (9 checks: 100-node
  structural roundtrip + search bit-identical, tombstones, empty graph,
  seven rejection cases, decoded graph mutable). File-backed segments stay
  pending on stdlib I/O.
- **HNSW beam construction:** `hnsw_insert` descends greedily then runs a
  per-layer beam (`search_layer_build`, width = `max(m, ef_construction)`)
  with diversified selection (`select_diverse`); full blocks are pruned with
  the same heuristic. `ef_construction` lives on the graph (default 200;
  setter ignores < 1) and is seeded by `set_index` from AnnParams. Harness:
  n=200 300/300 (ef=64) / 296/300 (ef=8), n=800 200/200,
  deletes/compaction still green, run ~1.8s.
- **HNSW id map + XVC-C-09 workaround:** sorted `id_keys`/`id_vals` map
  (binary-search insert/find; duplicate ids rejected; codec unchanged and
  rebuilds the map; compaction rebuilds it). Wiring it exposed **XVC-C-09**:
  the compiled `engine_set_index` segfaulted on WSL while Windows stayed
  green; fixed by building the graph in a local then assigning `eng.graph`
  once. Repro pinned at `bca8b7f`: `docs/repro/xv-wsl-nested-field/`.
- **Workaround pins + unwind decision (slice 5):** new per-build pin
  `probe_result_shapes.xi` gates the whole XVC-C-04 shape matrix (incl. the
  real engine path) on every build -- 8/8 fresh builds Windows + 2/2 WSL;
  `probe_bind_semantics` pins C-01 (8/8 + 2/2). Decision: KEEP the
  `SearchHits` wrapper (zero-cost, public API, C-08/C-09 family still open)
  and KEEP the suite's direct dispatch; revisit at the next compiler
  archive.
- **HNSW+filter integration:** `hnsw_search_filtered` (ANN fetch `ef_search`
  wide + matching subset; falls back to the exact flat filtered scan when
  under-filled) behind `engine_search_filtered` and the request-driven
  filtered branch; Flat keeps the planner. Gate `probe_engine_hnsw`:
  majority filter k-filled 8/8 with recall 80/80 vs the oracle; 1- and
  3-match filters fall back bit-identically; zero-match empty; stress 6/6.
- **Fuzz gate + decoder hardening:** new `probe_fuzz_codecs.xi`
  (deterministic random/mutated/truncated streams into `payload_decode`,
  `hnsw_decode`, WAL replay + chained checkpoint). It found **XVC-C-10**:
  `hnsw_decode`'s inline pad loop segfaulted at `m >= 512`; fixed by moving
  the pad step behind `pad_adj_slots` and adding strict bounds
  (`m <= 512`, `count <= words.len()`). Repro pinned at `e0b1f7f`:
  `docs/repro/xv-decode-pad-loop/`. Gate: 400+400+200 cases green,
  invariants hold on every `Some`, recovery keeps exactly the valid
  records; stress 6/6.
- **Mixed-workload soak:** `probe_soak_mixed.xi` (400-point Hnsw
  collection, 600 deterministic ops: 311 upserts / 115 searches / 63
  filtered / 61 payload sets / 50 deletes) with per-op bookkeeping
  invariants (search live/bounded/sorted/unique; filtered hits match the
  bucket; Ok flags == presence), periodic consistency + compaction, and
  final + chained recovery checks. ~2.5s; stress 4/4. NOTE: op/id/bucket
  selection uses LCG HIGH bits (low-bit residue 8 was unreachable -- the
  payload branch never ran; same degeneracy class as the level fix).
- **Latency metrics + release-prep (slice 4/J):** `hnsw_build_ops`
  (construction distance-op proxy; n=200: 62,129, bounded 4*n^2) and a
  per-ef visited/recall table in the harness (ef=8 -> 97/100 @ 63 visited;
  ef=16/32/64/128 -> 100/100 @ 84/126/171/196). Release-prep:
  `scripts/ci.ps1` + `scripts/ci.sh` (full battery, aggregated exit; both
  green end-to-end this pass), `VERSION` (0.1.0-dev), a SHA-pinned
  `.github/workflows/ci.yml` draft (activates with self-hosted runners) and
  `docs/RELEASE-CHECKLIST.md` (owner-gated flow).
- **Upsert update-in-place fix (found during E-stretch recon):**
  `index_add` used to reject an existing id and keep the OLD vector, so
  re-upserting silently diverged from the HNSW graph (which updates in
  place) and compaction reverted updates; recovery also kept the first
  vector. Now it updates in place (WAL replay matches live behavior).
  Regression gate in `probe_vector_store` (size stays, get_point/search
  see the NEW vector bits, recovery keeps the latest).
- **Index-driven candidates + compound upper bounds (E stretch):** store
  gains a sorted id -> slot map (O(log n) `index_get`/`index_add`/
  `index_remove`, swap-remove updates the moved slot); `filter_plan` gains
  plan 3 (index: exact Eq/Range/Exists candidates, incl.
  `payload_store_index_field_ids`) and `filter_matching_upper` for And/Or/
  Not (post when the bound is a majority, scan otherwise);
    `search_knn_filtered` executes the index plan with distances only for
    matches. Gate `probe_filter_plan` (20 checks: plan codes, upper bounds
    And=3 Or=1 Not=2 In=-1, index equivalence bit-identical to the scan
    reference).
- **Durable collection manifest:** `create_collection`/`set_index` log a
  `ManifestUpdate` record (`[version=1, dim, metric_code, kind_code, m,
  ef_construction, ef_search]`); `engine_recover` restores dim/metric/index
  kind/params from the latest manifest (rebuilding an Hnsw graph) without a
  manual `set_index`; `wal_writer_checkpoint_from` carries it forward, so
  chained recovery keeps the config; legacy/malformed logs fall back to the
  caller config + Flat. Gates in `probe_engine_hnsw` (23 checks).
- **HNSW update re-linking:** re-inserting an existing id now refreshes the
  node's edges for the new vector (per-layer beam through the old
  structure + diversified replacement; connect factored into `beam_select`/
  `apply_layer_edges`, construction behavior-identical). Gate: recall@10
  200/200 after 60 in-place updates vs the flat oracle (`probe_hnsw_recall`,
  size/live unchanged).
- **Kill-recovery acceptance:** `probe_kill_recovery.xi` proves the crash
  guarantee at the WAL model level -- for every prefix of a 46-record
  scripted log, recover(prefix) + apply(record t) == recover(prefix +
  record t) (store bits, payloads, config); same on the compacted
  checkpoint log (28 records); full recovery equals the live engine; empty
  log and corrupt-final-record cases hold. ~120ms; batteries then ran 17
  probes (18 since the file-WAL probe, below).
- **Multi-key intersections:** the index plan serves And of indexable
  clauses (Eq/Range/Exists) via per-clause candidate intersection;
  `choose_filter_plan` routes answerable compounds to the index when the
  upper bound is selective or < k (`filter_index_answerable`). Gate:
  planner probe 23 checks (And(grp=1,tier=1) -> index, {1,5} bit-identical;
  disjoint -> empty). NOTE (compiler quirk): a private helper with two
  `&Vec[Int]` params reported T001 undefined-second-parameter in three
  shapes; the intersection is inlined in the And arm.
- **File-backed WAL (whole-file checkpoint):** new
  `src/durability/wal_file.xi` -- `wal_persist(w, path)` writes a text
  checkpoint (header + one line per record: `lsn op key value timestamp
  payload_len [words...]`) and `wal_load(path)` is a byte-level,
  torn-tail-safe prefix load (longest run of complete valid records;
  missing/garbage/empty -> empty). Built on the stdlib whole-file APIs
  that exist today (`write_file_bytes`/`read_file_bytes`/`file_exists`/
  `file_size`); no fsync/append yet, so it is a checkpoint rewrite at
  quiescent points, not a delta log. Gate `probe_wal_file`: roundtrip
  equality vs the live WAL, kill/reopen (== live incl. Hnsw config),
  overwrite persistence, 9-point truncation sweep with per-cut prefix
  checks, record-boundary cuts, missing/garbage/empty files. Both
  batteries now run 18 probes. Found **XVC-C-11** (`io.read_file` content
  does not survive in some units -- `slice.str_bytes(s)` = 0 bytes for a
  written 11-/1771-byte file; silent wrong data) and **XVC-C-12**
  (`io.read_file_bytes` aborts on files of <= 8 bytes: `contract
  violated: ensures at 947:12`). Repro:
  `docs/repro/xv-stdlib-file-read-defects/`; workarounds: read bytes and
  parse byte-wise (never handle file content as a Str), guard with
  `file_size < 25` (semantically exact for a WAL).
- **FloatVal workaround unwound** after the v0.64.1 fix: float payload
  gates restored in the suite and probes.
- **Production tracker:** `docs/PRODUCTION-READINESS.md` -- weighted
  scorecard, **70 % today**; recompute at every wrap.

**Green evidence (compiler v0.64.1 + stdlib 0.64.2; latest re-verification
= file-WAL slice `c84ccbc` + this handoff wrap):**

- `scripts\run-probe.ps1 tests\probes\probe_engine_import.xi -Runs 2` green
  (the new-module import gate: `xiom.vector.engine` + `xiom.vector.engine.core`
  in one consumer).
- `scripts\run-suite.ps1 -Runs 2` -> **168/168 passed** twice, exit 0;
  WSL `bash scripts/run-suite.sh 2 240` -> **168/168 x2**.
- All **18 probes x2** green on Windows: `probe_hello`, `probe_bind_semantics`,
  `probe_engine_import`, `probe_vector_store`, `probe_filtered_search`,
  `probe_payload_recovery`, `probe_floatval_roundtrip`, `probe_search_request`,
  `probe_payload_index`, `probe_filter_plan`, `probe_hnsw_recall`,
  `probe_engine_hnsw`, `probe_hnsw_codec`, `probe_result_shapes`,
  `probe_fuzz_codecs`, `probe_soak_mixed`, `probe_kill_recovery`,
  `probe_wal_file` (run via `scripts\run-probe.ps1`).
- Per-ef tradeoff (n=200, 10 queries each): ef=8 -> 97/100 recall @ 63
  visited; ef=16 -> 100/100 @ 84; ef=32 -> 100/100 @ 126; ef=64 -> 100/100
  @ 171; ef=128 -> 100/100 @ 196; build work 62,129 distance ops.
- Release battery: `scripts/ci.ps1` and `scripts/ci.sh` -> `ci: ALL GATES
  GREEN` this pass on Windows and WSL (suite x2 + 18 probes x2 each); the
  file-WAL slice `c84ccbc` was verified through both batteries.
- Handoff re-verification (2026-10-09, this wrap): `scripts/ci.ps1` ->
  `ci: ALL GATES GREEN` (suite 168/168 x2 + 18 probes x2); WSL spot
  `bash scripts/run-probe.sh tests/probes/probe_wal_file.xi 2` -> 2/2
  green with bit-identical diagnostics; both stdlib-defect control probes
  (`docs/repro/xv-stdlib-file-read-defects/`) green in their own units.
- WSL spot: `probe_soak_mixed` x2 + `probe_fuzz_codecs` x1 + the pad-loop
  repro probe + `probe_result_shapes` x2 + `probe_bind_semantics` x2 +
  `probe_engine_hnsw` x2 + `probe_hnsw_recall` x2 + `probe_filter_plan` x2 +
  `probe_filtered_search` x1 + `probe_vector_store` green
  (`bash scripts/run-probe.sh`).
- Stresses: `probe_search_request` 8/8, `probe_payload_index` 6/6,
  `probe_filter_plan` 6/6, `probe_hnsw_recall` 6/6, `probe_engine_hnsw` 6/6,
  `probe_hnsw_codec` 6/6, `probe_fuzz_codecs` 6/6, `probe_result_shapes` 8/8,
  `probe_bind_semantics` 8/8, `probe_soak_mixed` 4/4 fresh builds (see
  XVC-C-08 for why trailing-field reads are not asserted in the suite).
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
- **XVC-C-09 OPEN (new on v0.64.1, WSL only):** the compiled
  `engine_set_index` segfaulted on WSL while Windows was green (context-
  sensitive lowering; same family as C-08). Worked around (local graph then
  single field assign). Repro pinned at `bca8b7f`:
  `docs/repro/xv-wsl-nested-field/`.
- **XVC-C-10 OPEN (new on v0.64.1):** `hnsw_decode`'s inline pad loop
  segfaulted at `m >= 512` (Windows + WSL) on otherwise pristine streams.
  Worked around (`pad_adj_slots` function boundary + strict bounds). Repro
  pinned at `e0b1f7f`: `docs/repro/xv-decode-pad-loop/`.
- **XVC-C-11 OPEN (new 2026-10-09):** `io.read_file` content does not
  survive in some units (silent wrong data: `slice.str_bytes(s)` = 0 bytes
  for a written 11-/1771-byte file; same class via `Str::from_utf8`).
  Green in a minimal control unit -- unit-context-sensitive (C-08 family).
  Repro: `docs/repro/xv-stdlib-file-read-defects/`. Workaround: read bytes
  and parse byte-wise; never handle file content as a Str.
- **XVC-C-12 OPEN (new 2026-10-09):** `io.read_file_bytes` aborts on files
  of <= 8 bytes in some units (`contract violated: ensures at 947:12`),
  zero-byte files included; 9+ bytes read fine; green in a minimal control.
  Workaround: `io.file_size` guard (WAL guard `< 25` is semantically
  exact). Repro: same bundle.
- Relay for the compiler lane: `docs/RELAY-COMPILER.md` (Addendum 3 =
  v0.64.1 results; 4 = C-08; 5 = C-09; 6 = C-10; 7 = C-11/C-12). Incoming
  relay `docs/COMPILER-RELAY-2026-10-09-v0.64.2.md` (v0.64.2 release-ready;
  m220-m239; re-run the suite + pinned probes when the tag lands).

---

## 1. NEXT TASKS (priority order)

The extraction tree is final; what remains is capability work plus
owner-gated release steps (`docs/RELEASE-CHECKLIST.md`).

1. **M2 durable-on-disk -- partly landed (whole-file WAL); fsync/append
   still stdlib-gated.** `durability.wal_file` (whole-file checkpoint +
   torn-tail-safe load + kill/reopen gate) shipped 2026-10-09. Remaining
   M2 path: stdlib `fsync`/fd-write/`append_file_bytes` (rows 1-3 of
   `docs/STDLIB-WISHLIST-XVECTOR.md`; still stubs on the lane -- re-check
   each pass), then a delta append log, file-backed segment files, a
   separate manifest file, and the file-level kill test. Pivot immediately
   when the stdlib gap lands. NOTE: stdlib 0.64.2 made file writes
   byte-exact + CRLF-clean (good news for WAL files).
2. **Non-gated extras:** range-search surface (B remaining: exact on the
   flat store; Hnsw routes there; brute-force gate), reference oracle
   cross-check (metric identities/axioms), adaptive ef/latency budget;
   batch search / pagination (F remaining) when wanted.
3. **Compiler re-test when the v0.64.2 tag lands** (incoming relay
   2026-10-09: keep `probe_floatval_roundtrip` pinned; re-run the suite +
   probes; relay residual reds with minimal repros). The C-08..C-12 family
   stays exposed meanwhile; re-test all repro bundles and refresh the
   findings doc per-row status.
4. **Unwind candidates** (revisit after the v0.64.2 re-test): `SearchHits`
   struct wrapper (C-04 fixed) -- decide API shape deliberately; suite
   direct dispatch (C-01); predicate-based negative tests (C-02).
5. **Porter flow prep:** with the tree final, extract `xiom.vectors`/
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
- **XVC-C-09 (open, WSL only): a compiled function that mutates a nested
  struct field through another module in a loop can segfault on WSL while
  Windows is green.** Build the nested value in a local and assign the field
  once; repro `docs/repro/xv-wsl-nested-field/` (pinned `bca8b7f`). Always
  run the WSL spot before trusting a green Windows wrap.
- **XVC-C-10 (open): `hnsw_decode`'s inline pad loop segfaults at larger
  `m`.** Keep large-volume push loops behind function boundaries and bound
  strict decode (`m <= 512`, `count <= words.len()`); repro
  `docs/repro/xv-decode-pad-loop/` (pinned `e0b1f7f`); general gate
  `probe_fuzz_codecs`.
- **XVC-C-11 (open): never handle file content as a Str in a large unit.**
  `io.read_file` content can be silently lost (0 bytes) in some units; read
  bytes via `read_file_bytes` and parse byte-wise. Repro
  `docs/repro/xv-stdlib-file-read-defects/`.
- **XVC-C-12 (open): `io.read_file_bytes` aborts on files of <= 8 bytes in
  some units.** Guard with `io.file_size` and skip short reads (the WAL
  guard `< 25` is semantically exact). Repro: same bundle.
- **filter_plan helper quirk (loud T001, not silent):** a private helper
  with two `&Vec[Int]` parameters can report `undefined variable` for its
  second parameter (three shapes tried, v0.64.1); inline the logic or use
  single-parameter helpers in `filter_plan.xi`.
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

## 5. Ecosystem status (2026-10-09)

- **stdlib:** consumed release for the v0.64.1 re-test was **0.64.2**
  (`4dd8844`: byte-exact file writes, CRLF-clean reads, `fs_remove` added,
  iter contracts extended); the lane has since advanced to `d54929d`
  (wave 97, 2026-10-09) and builds consume `E:\xiom-lang\stdlib` directly,
  so re-check `git -C E:\xiom-lang\stdlib log -1` each pass.
  **fsync/fd-write/append-bytes still stubs** (wishlist rows 1-3) --
  whole-file WAL workaround shipped, delta log still gated.
- **compiler:** v0.64.1 installed; v0.64.2 **release-ready** on the
  compiler repo's local main (incoming relay 2026-10-09: m220-m239 cover
  XVC-C-03/C-06/C-07/C-08; tag/push held for the owner). Re-test the suite
  + probes when the tag lands.
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
| `docs/COMPILER-FINDINGS-XVECTOR.md` | compiler | 6/12 fixed (v0.64.1); C-07..C-12 open |
| `docs/RELAY-COMPILER.md` | compiler | Addenda 3-7 (re-test; C-08; C-09; C-10; C-11/C-12) |
| `docs/COMPILER-RELAY-2026-10-09-v0.64.2.md` | compiler -> XVECTOR | received; re-test at the v0.64.2 tag |
| `docs/STDLIB-WISHLIST-XVECTOR.md` | stdlib | rows 1-3 (fsync/fd/append) still gating M2 delta log |
| `docs/PACKAGE-WISHLIST-XVECTOR.md` | packages | names frozen; replies recorded |
| `docs/RELAY-INTRO-XVECTOR.md` | ops + all | OPS parked until owner greenlight |
| `docs/PRODUCTION-READINESS.md` | owner | 70 %; recompute every wrap |

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

Toolchain (latest-tracking): compiler v0.64.1 installed on Windows
(%LOCALAPPDATA%\xiom.new\bin\xiom.exe) and WSL (~/.local/share/xiom, use
`wsl.exe -d Ubuntu`); v0.64.2 is release-ready upstream (re-test at the
tag); stdlib lane E:\xiom-lang\stdlib (lane HEAD d54929d; consumed release
0.64.2 = 4dd8844, /mnt/e/... in WSL); XIOM_RUNTIME_DIR retired. Dot-source
scripts\dev-env.ps1 (and .sh twin); scripts\build.ps1/.sh build;
scripts\run-suite.* runs the conformance suite; scripts\run-probe.* runs
probes. Green baseline: suite 168/168 x2 (Windows + WSL), 18 probes x2
(Windows) + WSL spot.

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
Engine HNSW wiring (set_index Flat/Hnsw, upsert graph upkeep, engine_search
routing with ef=ann.ef_search, filtered stays exact; gate
probe_engine_hnsw: engine recall 200/200, delete/revive, recover+re-apply;
hnsw_compact tombstone compaction + engine compact_index; hnsw_encode/
hnsw_decode strict graph codec; beam construction honouring
ef_construction with diversified pruning; sorted id map; XVC-C-04 shape
pin probe; C-01 bind pin; HNSW+filter integration with exact fallback;
deterministic fuzz gate + decoder hardening [XVC-C-10 found];
mixed-workload soak harness; latency metrics + release battery scripts +
VERSION/checklist; durable collection manifest; HNSW update re-linking;
kill-recovery prefix-exactness acceptance; file-backed WAL (whole-file
checkpoint codec + torn-tail-safe byte-level load; gate probe_wal_file;
both batteries now 18 probes) [XVC-C-11/C-12 found there]).
FloatVal gates restored after the v0.64.1 fix. Compiler: XVC-C-01..06
FIXED; XVC-C-07 OPEN (pass Vec by value to Str::from_utf8); XVC-C-08 OPEN
(trailing scalar after a Vec-bearing field can read garbage; repro
docs/repro/xv-trailing-field-vec; gate such reads only in real-module
probes); XVC-C-09 OPEN (WSL-only nested-field mutation segfault; build into
a local then assign once; repro docs/repro/xv-wsl-nested-field pinned at
bca8b7f); XVC-C-10 OPEN (hnsw_decode inline pad loop segfaults at larger m;
pad step behind pad_adj_slots + strict bounds; repro
docs/repro/xv-decode-pad-loop pinned at e0b1f7f); XVC-C-11 OPEN
(io.read_file content lost in some units -- read bytes, parse byte-wise;
repro docs/repro/xv-stdlib-file-read-defects); XVC-C-12 OPEN
(io.read_file_bytes aborts at <= 8 bytes in some units -- file_size guard;
same repro).

NEXT TASK (priority 1): M2 is partly landed -- whole-file WAL checkpoint +
torn-tail load shipped (durability.wal_file); the delta append/fsync log,
file-backed segments, manifest file and file-level kill test await the
stdlib fd/fsync gap (re-check each pass, pivot when it lands). Non-gated
extras: range-search surface, reference oracle cross-check, adaptive
ef/latency budget. Re-test the suite + pinned probes when the v0.64.2 tag
lands (keep probe_floatval_roundtrip pinned); public release/runners/
rulesets await the owner (docs/RELEASE-CHECKLIST.md).
Keep the wrap discipline: full batteries (scripts/ci.ps1 + ci.sh, suite x2
+ 18 probes x2), signed commits, docs updated.

Discipline: struct literals list every field; locals initialized; Vec by
value to Str::from_utf8 (C-07); trailing-scalar reads only in real-module
probes (C-08); numeric gates per build; watchdogs + exit codes; check free
memory before trusting a red build; suite x2 green before any wrap; update
SESSION.md STATE + relay rows + docs/PRODUCTION-READINESS.md at every wrap;
commit signed at every step.
```
