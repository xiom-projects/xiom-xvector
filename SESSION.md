# XIOM XVECTOR -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Project:** `E:\xiom-projects\xiom-xvector` -- production-grade vector
database engine for XIOM (dense vectors, metrics, flat + HNSW ANN,
collections, segments, WAL-backed durable writes; the working tree is the
`src/engine.xi` facade over `src/engine/core.xi` + the extracted modules).
**Written:** 2026-10-07 (bootstrap by the PULSE lane).
**Last updated:** 2026-10-09 (41 continuation passes: bootstrap -> Phase 2
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
found] -> v0.64.2 re-test: C-03/C-06/C-07/C-08 verified fixed, C-07/C-08
workarounds reverted, C-10..C-12 re-tested green -> wishlist refresh
(stdlib 0.64.3 re-check; xiom.wal/xiom.btree in-tree; relays updated) ->
production programme kickoff: requirements + v1.0 plan + checklist ->
M-D1 atomic WAL checkpoint (temp + io.rename; kill injection) ->
consumer handshakes (PULSE + ORBITDB integration files; bindings relay) ->
M-Q1 exact range search (kernel + engine + facade + probe) ->
M-Q2 batch ops (upsert_many / delete_many / search_many + BatchHits) ->
M-G bench harness + baseline [wal_persist O(L^2) fixed; native --icon] ->
M-D2 manifest file [collection registry file, atomic rename, torn-tail-safe
load, file-wins open with in-WAL migration fallback; XVC-C-13 found] ->
M-D3 multi-collection registry [named create/select/drop/list, per-
collection isolation, routed recovery (v2/v3 manifest records), whole-
registry manifest save; probe_collections]) -> M-D4 sealed segment files
[segment_file codec (vectors + payloads + Hnsw graph, atomic persist,
torn-tail load), engine seal/restore with WAL re-checkpoint; lifecycle
Mutable -> Sealing -> Sealed]).

---

## 0. STATE (hand-off point)

**Repo:** private, no pushes; clean tree. HEAD `7be7f36` (feat: M-D4
segment files) + this handoff commit. Recent slices: `7be7f36` M-D4
(segment files), `ba5ac3c` M-D3 wrap, `cf921ee` M-D3 (multi-collection),
`e8a32e8` M-D2 wrap, `6519f3a` M-D2 (manifest file), `6c48327` handoff
refresh. Identity `Lefteris Notas <lefterisnotas@gmail.com>`; conventional
commits, DCO `git commit -s`.

**Toolchain (latest-tracking; record hashes at every wrap):**

| Lane | Version / hash | Path |
|---|---|---|
| compiler | **v0.64.2** installed 2026-10-09 (tag `c51170a6`; Win 19:00 / WSL 18:37); compiler lane HEAD `d481c490` (post-tag fixes) | Win `%LOCALAPPDATA%\xiom.new\bin\xiom.exe`; WSL `~/.local/share/xiom` |
| stdlib | lane HEAD `ed6d46c` (waves 98-99; release **0.64.3 registry-LIVE**); durability primitives still stubs | `E:\xiom-lang\stdlib` (= `/mnt/e/xiom-lang/stdlib`) |
| packages | lane HEAD `26f7d0ae` (bindings batch 23 published, `eco-v0.1.123`); `xiom.wal` + `xiom.btree` 0.1.0 in-tree, ops-allowlist gate; `xiom.vectors` extraction gate MET awaiting owner greenlight | `E:\xiom-packages\packages` |
| xvector | `7be7f36` + this handoff commit | this repo |

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
  `probe_search_request` (real-module gate). Hydration flags were gated in
  that probe only while XVC-C-08 was open; since the v0.64.2 fix the suite
  asserts them too.
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
- **v0.64.2 re-test + workaround reverts (31st pass, 2026-10-09):** all
  relayed fixes verified on the tag archive (`c51170a6`, Windows + WSL).
  **C-07:** `Str::from_utf8(&Vec[UInt8])` compiles and returns correctly;
  the payload codec (`src/payload/payload.xi`) and suite mirror reverted to
  the `&` spelling. **C-08:** trailing-scalar repro exit 0, all 14
  `variants.xi` green; the suite hydration mirror is restored and asserts
  the trailer `has_payload` flags (suite 168 -> 169). **C-10:** the inline
  pad shape no longer segfaults; `pad_adj_slots` + strict bounds kept as
  hygiene. **C-11/C-12:** unguarded reads green in a copy of the original
  failing unit; byte parser + `file_size` guard kept as defense in depth.
  **C-09:** repro green on WSL + Windows (local-assign kept; weaker
  re-test). Batteries: suite 169/169 x2 + 18 probes x2, Windows + WSL.
- **Production programme kicked off (2026-10-09):** requirements intake
  (`docs/requirements/production-v1.md`), v1.0 flagship plan
  (`docs/PRODUCTION-PLAN.md`: M-G truth/benchmark, M-D on-disk durability,
  M-Q query surface, M-S server/security, M-O observability, M-P
  performance/scale, M-R release + owner handoff; first-12 slice backlog),
  execution checklist (`docs/checklists/production-v1.md`);
  ROADMAP/README/readiness aligned.
- **M-D1 atomic WAL checkpoint (2026-10-09):** `wal_persist` writes
  `<path>.tmp` then swaps via `io.rename` (platform replace semantics);
  `probe_wal_file` gained 7 fault-injection checks (no temp left behind;
  staged-complete temp and partial temp both leave the previous checkpoint
  intact; completed persist advances the file). Evidence: probe x2 +
  full batteries both platforms.
- **Consumer handshakes (2026-10-09):** `docs/PULSE-INTEGRATION.md` and
  `docs/ORBITDB-INTEGRATION.md` written (API surface + snippets, build/link
  contract + platform matrix, pin/stability + on-disk layout,
  findings/lifecycle incl. C-PULSE-14 RSS notes, conformance proposals,
  cross-asks). PULSE will build `probe_pkg_xvector`; ORBITDB the hybrid
  `probe_hybrid` (1k rows + vectors, join integrity after kill/reopen +
  repair). Bindings relay: accelerators stay GATED (sole unscheduled
  sector).
- **M-Q1 exact range search (2026-10-09):** `search_range_scan` kernel +
  `engine_search_range` + facade `search_range` -- every point within
  `radius` (inclusive), distance-sorted, bounded by `limit`; exact on both
  index kinds; errors for dim mismatch / limit 0 / negative radius. Gate
  `probe_range_search` (11 checks: 72 radius x limit combos vs a local
  brute-force scan, inclusive boundary, radius-0, KNN equivalence, Hnsw
  routing, reopen); suite mirror test added (169 -> 170).
- **M-Q2 batch ops (2026-10-09):** `upsert_many` / `delete_many` /
  `search_many` + `BatchHits` (one set per query, order preserved);
  all-or-nothing validation per call (bad dimension/length/empty leaves the
  engine untouched); delete counts actual removals (missing ids skipped);
  duplicate ids collapse; facade + engine paths. Gate `probe_batch_ops`
  (14 checks incl. recover equality and the Hnsw batch path); suite mirror
  test added (170 -> 171).
- **M-G benchmark harness + baseline (2026-10-09):** `bench/bench_main.xi`
  -- deterministic workloads (W1 ingest, W2 flat knn, W3 HNSW build/recall
  per ef, W4 filtered, W5 batch, W6 range, W7 recovery), integer-only JSON
  report at `out/bench_report.json`, group-calibrated per-op sampling,
  hard-capped loop budgets, `XV_BENCH_STAGE` diagnostics; runners
  `scripts/bench.ps1` / `bench.sh`; **bench smoke (quick) wired into both
  CI batteries**. Baseline committed in `docs/BENCHMARKS.md` (n=5000
  dim-4: flat knn p50 10.7 ms; HNSW ef=32 p50 0.44 ms recall 1.000;
  filtered Eq 1.13 ms; recovery 12.6 s). **Fixed the `wal_persist` O(L^2)
  string builder** (linear `append_bytes`; the builder drove multi-GB
  paging during harness bring-up -- all loops now capped + monitored);
  `probe_wal_file` +4 scale checks (1200-record roundtrip). Native `--icon`
  embedding wired in `scripts/build.ps1` + `images/xvector-icon.ico`
  (compiler m214/v0.64.2; rcedit workaround retired).
- **M-D2 manifest file (2026-10-09):** new `src/durability/manifest_file.xi`
  -- `xvector-manifest 1` text registry (one line per collection:
  `name dim mc kc m efc efs`; names 1..64 chars of `[A-Za-z0-9_.-]`),
  whole-file persist with atomic temp+rename (invalid name/dim/params
  refused, target untouched), byte-level torn-tail-safe load (longest
  complete-entry prefix; header-only = valid empty; missing/garbage =
  invalid; `file_size < 19` reads skipped). Engine: `engine_manifest_save`
  + `engine_recover_file` (facade `save_manifest` / `open_engine`) -- the
  file registry governs the config on open; the in-WAL manifest is the
  migration fallback (shared private `engine_recover_with`). Stable
  metric/kind codes moved to the leaf modules (`metric_code/_from_code`,
  `ann_kind_code/_from_code`); `wal_file` byte helpers (`parse_int_at`/
  `append_bytes`) shared with the new codec. Gate `probe_manifest_file`
  (38 checks: roundtrip/overwrite/valid-empty, invalid refusals, atomic
  staged/partial temp injection, 10-point truncation sweep, malformed-line
  prefixes, save/open wins-vs-fallback matrix, 500-entry scale). **Found
  XVC-C-13**: `&Str` parameters are unknown to the checker (i64 fallback,
  silent wrong values -- `first_byte("A")` = 71 Win / 127 WSL); repro
  `docs/repro/xv-str-ref-param/`; lane convention is `Str` by value.
- **M-D3 multi-collection (2026-10-09):** named collections with
  `create_named_collection` / `select_collection` / `drop_collection` /
  `list_collections` / `collection_count` (facade + engine; names 1..64
  chars of `[A-Za-z0-9_.-]`; duplicates, invalid names and invalid dims
  rejected). Per-collection isolation of stores, payloads, index kind and
  ANN params; the ACTIVE collection is materialized in the engine's
  top-level fields and parked entries live in `collections` (snapshot-copy
  discipline, shape-validated on v0.64.2; switches copy once, data ops
  never). Durable: WAL ManifestUpdate v2 config records (record value =
  cid) + v3 drop records; data records stamp the active cid; recovery
  builds every collection, routes data by cid in D3 strict mode (legacy
  logs route to the single collection), overrides configs from the
  manifest file by name, and checkpoints all alive collections.
  `save_manifest`/`engine_manifest_save` now persist the WHOLE registry;
  `open_engine` restores it (file-wins by name). Gate `probe_collections`
  (41 checks). Legacy `create_collection` -> "default" keeps every
  existing consumer green.
- **M-D4 sealed segment files (2026-10-09):** new
  `src/segment/segment_file.xi` -- the sealed-segment codec
  (`xvector-segment 1`; required meta line with seg_id/cid/state/dim/
  metric/index kind/params; `v` vector lines via `vector_encode`; `p`
  payload lines via `payload_encode`; optional `g` Hnsw graph line via
  `hnsw_encode`). Whole-file atomic persist (`<path>.tmp` -> `io.rename`;
  only Sealed/Immutable states accepted; invalid meta/state refused with
  the target untouched); byte-level torn-tail-safe load (complete-record
  prefix; malformed lines stop the prefix; graph best-effort/rebuildable;
  41-byte `file_size` guard). `segment_state_from_code` added; the seal
  drives the REAL lifecycle Mutable -> Sealing -> Sealed
  (`segment_state_can_transition`). Engine: `engine_seal_segment` (active
  collection -> vectors + payloads + graph) and `engine_restore_segment`
  (cid/dim/metric validated; swaps the live state; re-checkpoints the WAL
  through the new shared `engine_checkpoint_from` so a reopen replays the
  restored state). Facade `seal_segment`/`restore_segment`. Gate
  `probe_segment_file` (38 checks). Multi-segment read path + retention
  stay D5/D6.
- **FloatVal workaround unwound** after the v0.64.1 fix: float payload
  gates restored in the suite and probes.
- **Production tracker:** `docs/PRODUCTION-READINESS.md` -- weighted
  scorecard, **72 % today**; recompute at every wrap.

**Green evidence (compiler v0.64.2 installed 2026-10-09 + stdlib lane
`ed6d46c` = 0.64.3; latest re-verification = M-D2 manifest pass on the
current tree):**

- `scripts\run-probe.ps1 tests\probes\probe_engine_import.xi -Runs 2` green
  (the new-module import gate: `xiom.vector.engine` + `xiom.vector.engine.core`
  in one consumer).
- `scripts\run-suite.ps1 -Runs 2` -> **171/171 passed** twice, exit 0;
  WSL `bash scripts/run-suite.sh 2 240` -> **171/171 x2**.
- **v0.64.2 re-test pass (31st):** suite **169/169 x2** + 18 probes x2 on
  Windows and WSL, ALL GATES GREEN; repro bundles: C-07 exit 0, C-08 probe
  + 14 variants exit 0, C-10 exit 0, C-11/C-12 green in the original
  context unit, C-09 green on WSL; suite W004 count 0 (C-03).
- **M-Q2 batch pass:** suite **171/171 x2** + **20 probes x2** (Windows +
  WSL), ALL GATES GREEN; new `probe_batch_ops` (14 checks) plus the batch
  ops suite mirror test.
- **M-D2 manifest pass:** suite **171/171 x2** + **21 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_manifest_file`
  (38 checks, atomic/torn-tail/fallback matrix) wired into both batteries;
  WSL spot x2 bit-identical diagnostics.
- **M-D3 collections pass:** suite **171/171 x2** + **22 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_collections`
  (41 checks) wired into both batteries; WSL spot x2 bit-identical. No
  regression across the recovery rewrite (kill-recovery prefix exactness,
  wal_file, payload/soak/engine probes all green).
- **M-D4 segment pass:** suite **171/171 x2** + **23 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_segment_file`
  (38 checks: atomic temp injection, 14-point truncation sweep, seal/
  restore bit-exact search, WAL durability after restore) wired into both
  batteries; WSL spot x2 bit-identical.
- All **23 probes x2** green on Windows: `probe_hello`, `probe_bind_semantics`,
  `probe_engine_import`, `probe_vector_store`, `probe_filtered_search`,
  `probe_payload_recovery`, `probe_floatval_roundtrip`, `probe_search_request`,
  `probe_payload_index`, `probe_filter_plan`, `probe_hnsw_recall`,
  `probe_engine_hnsw`, `probe_hnsw_codec`, `probe_result_shapes`,
  `probe_fuzz_codecs`, `probe_soak_mixed`, `probe_kill_recovery`,
  `probe_wal_file`, `probe_manifest_file`, `probe_collections`,
  `probe_segment_file`, `probe_range_search`, `probe_batch_ops` (run via
  `scripts\run-probe.ps1`).
- Bench smoke: `scripts\bench.ps1 -Mode quick` / `bash scripts/bench.sh
  quick` green (Windows + WSL), wired into both CI batteries; baseline
  numbers in `docs/BENCHMARKS.md` (M-G).
- Per-ef tradeoff (n=200, 10 queries each): ef=8 -> 97/100 recall @ 63
  visited; ef=16 -> 100/100 @ 84; ef=32 -> 100/100 @ 126; ef=64 -> 100/100
  @ 171; ef=128 -> 100/100 @ 196; build work 62,129 distance ops.
- Release battery: `scripts/ci.ps1` and `scripts/ci.sh` -> `ci: ALL GATES
  GREEN` this pass on Windows and WSL (suite x2 + 18 probes x2 each); the
  file-WAL slice `c84ccbc` was verified through both batteries.
- Handoff re-verification (file-WAL wrap, v0.64.1-era): `scripts/ci.ps1` ->
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
  `probe_bind_semantics` 8/8, `probe_soak_mixed` 4/4 fresh builds (trailing
  field reads are asserted in the suite again since the v0.64.2 C-08 fix).
- WSL matrix `docs/repro/xv-f32-int-miscompile/linux_matrix.sh 3` -> 9/9
  exact (v0.64.1 fixed the per-build f32 lowering).

**Compiler findings (all reported; see `docs/COMPILER-FINDINGS-XVECTOR.md`):**

- **v0.64.2 re-test (2026-10-09): all relayed fixes verified, workarounds
  reverted.** C-03 (suite W004 count 0) and C-06 (pinned FloatVal probe)
  stay green; **C-07 FIXED** -- `Str::from_utf8(&Vec[UInt8])` compiles and
  returns correctly, the payload codec + suite mirror reverted to the `&`
  spelling; **C-08 FIXED** -- trailing-scalar repro exit 0, all 14 variants
  green, suite hydration flags asserted again (168 -> 169 checks).
- Extra re-tests beyond the relayed set: **C-10 FIXED** (inline pad shape
  no longer segfaults; `pad_adj_slots` + strict bounds kept as hygiene);
  **C-11/C-12 re-tested green in a copy of the original failing unit**
  (byte parser + `file_size` guard kept as defense in depth); **C-09 repro
  green on WSL + Windows** (local-assign pattern kept; weaker re-test --
  the inline pattern was green before too).
- Retained workarounds (deliberate choices, not blockers): `SearchHits`
  wrapper (C-04, zero-cost public API), suite direct dispatch (C-01),
  predicate-negative style (C-02).
- Relay for the compiler lane: `docs/RELAY-COMPILER.md` (Addenda 3-8;
  8 = v0.64.2 re-test). Incoming relay
  `docs/COMPILER-RELAY-2026-10-09-v0.64.2.md` (m220-m239) -- actioned:
  suite + pinned probes re-run on the archive, no residual reds.

---

## 1. NEXT TASKS (priority order)

**Programme:** `docs/PRODUCTION-PLAN.md` (v1.0 flagship plan) +
`docs/requirements/production-v1.md` + `docs/checklists/production-v1.md`.
Work proceeds autonomously slice-by-slice under the lane's goal loop, one
verified slice at a time (suite x2 + all probes x2, Windows + WSL spot,
signed commits, docs updated).

1. **M-D1 + M-D2 + M-D3 + M-D4 + M-Q1 + M-Q2 + M-G2/G3 DONE.** Next per
   the backlog: M-Q3 pagination -> Q4 delete-by-filter -> Q5 index admin ->
   Q6 request extensions; then M-S1 server & security, M-O observability.
   G1 (reference oracle) remains the open M-G item. D5/D6 (delta+fsync,
   retention) stay gated on the stdlib fsync chain.
2. **M-Q query surface:** Q1 range search + Q2 batch ops **DONE**; next:
   pagination (Q3), delete-by-filter (Q4), per-collection stats + index
   admin (Q5), SearchRequest extensions incl. range mode (Q6).
3. **M-G truth & measurement:** reference-oracle cross-check (G1), `bench/`
   harness (G2), `docs/BENCHMARKS.md` baseline + external-benchmark
   protocol (G3) -- this is what the owner's benchmark drives.
4. **M-S server & security:** HTTP skeleton (S1), config/limits/errors
   (S2), API-key auth (S3), security pass + SBOM (S4); **M-O**
   observability (metrics/health/logs/runbook) in the same wave.
5. **Gated (pick up when the stdlib lane lands the primitives):** D5 delta
   append + fsync + file-level kill-matrix; D6 truncate-based retention;
   P5 mmap segments. Re-check each pass (0.64.3: still stubs --
   `docs/STDLIB-WISHLIST-XVECTOR.md`).
6. **Porter flow (owner-gated):** `xiom.vectors`/`xiom.ann` extraction on
   greenlight; **`xiom.wal` adoption gate CLEARED** (0.1.0 registry-live,
   verified 2026-10-09) -- triage the first-adoption slice (codec alignment,
   source-roots wiring with a C-PULSE-02 re-check) alongside the backlog
   (`docs/PACKAGE-WISHLIST-XVECTOR.md`).
7. **Release gate:** when the M-R criteria are met the lane tells the owner
   -- the owner sets up the public release + benchmark (PULSE-style).

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
- **XVC-C-07 (fixed v0.64.2): `Str::from_utf8(&Vec[UInt8])` is valid again.**
  The lane uses the `&` spelling (reverted from the by-value workaround);
  repro `docs/repro/xv-from-utf8-vec-ref/` stays as a regression gate.
- **XVC-C-08 (fixed v0.64.2): trailing scalars after a Vec-bearing field are
  readable in large units again.** The suite hydration mirror asserts the
  flags (169 checks); repro `docs/repro/xv-trailing-field-vec/` stays as a
  regression gate. If a future archive reintroduces garbage reads, open a
  delta row instead of re-applying layout hacks.
- **XVC-C-09 (repro green v0.64.2; keep the pattern): build nested values in
  a local and assign the field once.** Always run the WSL spot before
  trusting a green Windows wrap; repro `docs/repro/xv-wsl-nested-field/`.
- **XVC-C-10 (fixed v0.64.2; keep the hygiene): keep large-volume push loops
  behind function boundaries and bound strict decode (`m <= 512`,
  `count <= words.len()`).** Repro `docs/repro/xv-decode-pad-loop/`; general
  gate `probe_fuzz_codecs`.
- **XVC-C-11/C-12 (re-tested green v0.64.2; keep defense in depth): read
  file content as bytes and parse byte-wise; guard short reads with
  `io.file_size` (WAL guard `< 25`).** Repro
  `docs/repro/xv-stdlib-file-read-defects/`.
- **XVC-C-13 (OPEN on v0.64.2; the workaround is the lane convention):
  never declare `&Str` parameters -- the checker warns `unknown type
  '&Str'` and defaults the parameter to i64, then the body reads garbage
  (`first_byte("A")` = 71 Windows / 127 WSL, expect 65). Pass `Str` by
  value.** Repro `docs/repro/xv-str-ref-param/`; relayed in Addendum 9.
- **filter_plan helper quirk (loud T001, not silent):** a private helper
  with two `&Vec[Int]` parameters can report `undefined variable` for its
  second parameter (three shapes tried, v0.64.1); inline the logic or use
  single-parameter helpers in `filter_plan.xi`.
- Historical v0.64.0/v0.64.1-era traps (C-01..C-08) are fixed; if any
  reappears, open a delta row instead of re-bisecting (details in the
  findings doc).
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

- **stdlib:** current lane HEAD `ed6d46c` (waves 98-99: iter/io/convert/
  array M7 closure + crypto/hash/math clauses; release **0.64.3
  registry-LIVE**). **Re-checked 2026-10-09: fsync/fdatasync, the fd path
  (`write_all` etc.), `append_file_bytes`, `truncate`/`ftruncate` are still
  stubs; no `f32_bits`/`bits_to_f32`; `flush_stdout` still a no-op** (see
  `docs/STDLIB-WISHLIST-XVECTOR.md`). `io.rename` exists -- atomic
  temp+rename checkpoint hardening is available today (used by M-D1).
  Byte-exact file writes / CRLF-clean reads since 0.64.2.
- **compiler:** **v0.64.2 installed** (2026-10-09; tag `c51170a6`; nine-tool
  install Windows + WSL). Re-test done: all relayed XVECTOR fixes verified
  (C-03/06/07/08), C-10..C-12 also green; workarounds reverted where
  applicable (Addendum 8). No residual reds from the re-test; **one new
  finding since: XVC-C-13** (`&Str` parameters unknown to the checker ->
  i64 fallback, silent wrong values) -- OPEN, relayed (Addendum 9); the
  lane convention (`Str` by value) sidesteps it.
- **packages:** lane HEAD `26f7d0ae`; bindings batch 23 published
  (`xiom.box2d` 0.2.0 + `xiom.imgui` 0.2.0, `eco-v0.1.123`); **36+ eco
  releases** (`xiom.http` 0.1.4 published). **`xiom.wal` 0.1.0 is
  PUBLISHED** (registry metadata verified at the M-D2 wrap: 0.1.0 signed,
  not yanked; `xiom.btree` 0.1.0 in-tree) -- the ops-allowlist publish
  gate has CLEARED. `xiom.wal` is the single WAL home (durable record shape
  + ORBITDB disk segment; `wal_flush` no-op on the same fsync gap);
  **next-slice triage: first-adoption design** (codec alignment +
  `xiom.toml` source-roots with a C-PULSE-02 re-check); the local
  `durability.wal`/`wal_file` stay until that slice lands. No
  `xiom.vectors`/`xiom.ann` dirs yet (names frozen);
  wishlist ledger (2026-10-09): **`xiom.vectors` extraction gate MET,
  awaiting owner greenlight**, then the porter flow. `xiom.metrics` planned
  for Phase 10; `xiom.kv` gated on C-PULSE-10 + fsync. Bindings relay
  (2026-10-09): blas-class accelerators stay **GATED** (incubating
  placeholders, no timeline; pilot complete through batch 22) -- sole
  unscheduled sector; M-P3 stays seam-first.
- Registry ready: `xiom.http` 0.1.1, `xiom.jwt` 0.2.0, `xiom.rate` 0.2.0,
  `xiom.metrics` 0.2.0, `xiom.router` 0.1.0, `xiom.http.middleware` 0.1.0,
  `xiom.session` 0.1.0, `xiom.static` 0.1.0, `xiom.kv` 0.1.0. Read
  `E:\xiom-projects\xiom-pulse\SESSION.md` + its relay docs before filing
  anything new (do not rediscover).

## 6. Relay rows (keep updated every wrap)

| Doc | For | State |
|---|---|---|
| `docs/COMPILER-FINDINGS-XVECTOR.md` | compiler | v0.64.2: C-03/06/07/08 verified fixed; C-10 fixed; C-11/C-12 in-context green; C-09 repro green; **C-13 OPEN (new)** |
| `docs/RELAY-COMPILER.md` | compiler | Addenda 3-9 (8 = v0.64.2 re-test; 9 = XVC-C-13 `&Str` params) |
| `docs/COMPILER-RELAY-2026-10-09-v0.64.2.md` | compiler -> XVECTOR | received; actioned (re-test done, no residual reds) |
| `docs/STDLIB-WISHLIST-XVECTOR.md` | stdlib | re-checked 2026-10-09 on 0.64.3: fsync/fd/append + f32-bits + truncate + flush_stdout all still open |
| `docs/PACKAGE-WISHLIST-XVECTOR.md` | packages | refreshed 2026-10-09 at the M-D2 wrap: `xiom.wal` 0.1.0 registry-LIVE (publish gate cleared; adoption triage next); `xiom.vectors` gate MET awaiting owner greenlight |
| `docs/PULSE-INTEGRATION.md` | PULSE (consumer) | written 2026-10-09; PULSE builds `probe_pkg_xvector` from it |
| `docs/ORBITDB-INTEGRATION.md` | ORBITDB (hybrid pair) | written 2026-10-09 (mirrors their `XVECTOR-INTEGRATION.md`); hybrid probe next |
| `docs/RELAY-INTRO-XVECTOR.md` | ops + all | OPS parked until owner greenlight |
| `docs/PRODUCTION-READINESS.md` | owner | 70 %; recompute every wrap |

---

## 7. Paste prompt for the next XVECTOR session

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first, then
README/SPEC/ARCHITECTURE/ROADMAP/AUDIT and docs/ (especially
docs/PRODUCTION-PLAN.md + docs/PRODUCTION-READINESS.md and the
requirements/checklists for the v1.0 programme). Consumer lane: never edit
E:\xiom-lang\stdlib, E:\xiom-lang\xiom, E:\xiom-packages\packages. Repo
stays PRIVATE; no pushes. Identity "Lefteris Notas
<lefterisnotas@gmail.com>"; conventional commits, DCO -s.

Orientation: HEAD `7be7f36` (feat: M-D4 segment files) + the handoff
commit; clean tree; `git log --oneline -12` shows the recent slice commits.
Lane pins: stdlib `ed6d46c`, packages `26f7d0ae`, compiler lane `d481c490`
(installed compiler v0.64.2, tag c51170a6).

Autonomous mode: arm a session goal with this objective (verbatim):
"Execute docs/PRODUCTION-PLAN.md for xiom-xvector autonomously, one
verified slice at a time, without further user prompting. Work the ordered
slice backlog: M-Q3 pagination -> Q4 delete-by-filter -> Q5 index admin ->
Q6 request extensions; M-G1 reference oracle; M-S1 HTTP service -> S2 config/limits/
errors -> S3 auth -> S4 security pass; M-O metrics/health/logs/runbook.
Re-check external lanes every pass (stdlib fsync/fd/append chain gates
D5/D6/P5; packages xiom.wal adoption + ops allowlist; compiler archives)
and pivot immediately when primitives land. Per slice: implement, extend
probe/suite gates, run suite x2 + all probes x2 + bench smoke on Windows +
WSL spot, update SPEC/ARCHITECTURE/SESSION/PRODUCTION-READINESS + checklist,
commit signed (-s, identity lefterisnotas@gmail.com). Repo stays private; no
pushes; never edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom,
E:\xiom-packages\packages. When the M-R release criteria are met (green
batteries + kill-matrix + benchmark report + security checklist + SBOM +
complete docs + v1.0.0-rc), report complete with the owner handoff summary
so the owner can set up the public release and benchmark (PULSE-style).
Report blocked only when no scheduled wait or non-gated slice can help."

Safety: check free memory before heavy runs -- bench bring-up once hit
multi-GB paging through the O(L^2) wal_persist (fixed in 5562f67); bench
loops are now hard-capped and monitored. Never raise bench loop budgets
without a memory monitor, and never leave a rebuilt binary from a red build.

Toolchain (latest-tracking): compiler v0.64.2 installed on Windows
(%LOCALAPPDATA%\xiom.new\bin\xiom.exe) and WSL (~/.local/share/xiom, use
`wsl.exe -d Ubuntu`); stdlib lane E:\xiom-lang\stdlib (lane HEAD ed6d46c =
release 0.64.3 registry-LIVE, waves 98-99; durability primitives still
stubs; /mnt/e/... in WSL); XIOM_RUNTIME_DIR
retired. Dot-source scripts\dev-env.ps1 (and .sh twin); scripts\build.ps1/.sh
build; scripts\run-suite.* runs the conformance suite; scripts\run-probe.*
runs probes. Green baseline: suite 171/171 x2 (Windows + WSL), 23 probes x2
(Windows) + WSL spot + bench smoke (quick) in both batteries.

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
both batteries then 18 probes) [XVC-C-11/C-12 found there]; M-D1 atomic
checkpoints via temp+io.rename (7 fault-injection checks); M-Q1 exact range
search (`search_range` facade/engine + `search_range_scan` kernel; gate
`probe_range_search`: 11 checks); M-Q2 batch ops (`upsert_many`/
`delete_many`/`search_many` + `BatchHits`; gate `probe_batch_ops`: 14
checks); M-G bench harness + baseline (`docs/BENCHMARKS.md`; bench smoke in
both batteries) [found + fixed the O(L^2) `wal_persist`; linear builder now
scale-guarded]; native `--icon` embedding wired (images/xvector-icon.ico);
M-D2 manifest file (`xvector-manifest 1` collection registry, atomic
temp+rename, torn-tail-safe load, `engine_manifest_save` +
`engine_recover_file` with facade `save_manifest`/`open_engine`, file-wins
open with in-WAL migration fallback; gate `probe_manifest_file`, 38 checks)
[XVC-C-13 found: `&Str` params mislower to i64]; M-D3 multi-collection
registry (named create/select/drop/list with per-collection isolation; WAL
v2 config + v3 drop records with cid-stamped data; routed multi-collection
recovery + whole-registry checkpoint; whole-registry `save_manifest` +
file-wins `open_engine`; legacy create_collection -> "default"; gate
`probe_collections`, 41 checks); M-D4 sealed segment files
(`segment_file` codec: vectors + payloads + Hnsw graph, atomic persist,
torn-tail-safe load; engine `seal_segment`/`restore_segment` with WAL
re-checkpoint; lifecycle Mutable -> Sealing -> Sealed; gate
`probe_segment_file`, 38 checks) -- 23 probes, suite 171).
FloatVal gates restored after the v0.64.1 fix. Compiler v0.64.2 re-test
(2026-10-09): C-03 (W004=0) and C-06 stay green; C-07 FIXED (&Vec spelling
works; workaround reverted in payload codec + suite); C-08 FIXED (repro +
all 14 variants green; suite hydration flags asserted again, 169 checks);
C-10 FIXED (inline pad no longer crashes); C-11/C-12 re-tested green in the
original context unit; C-09 repro green on WSL (workaround retained).
Retained workarounds (deliberate): SearchHits wrapper (C-04), suite direct
dispatch (C-01), local-assign nested writes (C-09), pad_adj_slots + strict
bounds (C-10), byte parser + file_size guard (C-11/C-12), Str params by
value (C-13).

NEXT TASK: execute docs/PRODUCTION-PLAN.md slice-by-slice (M-D1 + M-D2 +
M-D3 + M-D4 + M-Q1 + M-Q2 + M-G2/G3 done; next: M-Q3 pagination;
then Q4-Q6, M-S server/security, M-O observability; G1 reference oracle
pending). Non-gated work proceeds while the stdlib
fsync chain stays pending (0.64.3: still stubs). When the M-R release
criteria are met, TELL THE OWNER (public release + benchmark setup is the
owner's action, PULSE-style). C-01/C-02/C-04 unwinds are optional
deliberate API decisions, no longer compiler-blocked.
Keep the wrap discipline: full batteries (scripts/ci.ps1 + ci.sh, suite x2
+ 23 probes x2 + bench smoke), signed commits, docs updated.

Discipline: struct literals list every field; locals initialized; `Str`
params by value (XVC-C-13); numeric gates per build; watchdogs + exit
codes; check free memory before trusting a red build; suite x2 green before
any wrap; WSL spot every wrap; update
SESSION.md STATE + relay rows + docs/PRODUCTION-READINESS.md at every wrap;
commit signed at every step.
```
