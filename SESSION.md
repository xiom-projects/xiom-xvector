# XIOM XVECTOR -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Project:** `E:\xiom-projects\xiom-xvector` -- production-grade vector
database engine for XIOM (dense vectors, metrics, flat + HNSW ANN,
collections, segments, WAL-backed durable writes; the working tree is the
`src/engine.xi` facade over `src/engine/core.xi` + the extracted modules).
**Written:** 2026-10-07 (bootstrap by the PULSE lane).
**Last updated:** 2026-10-10 (54 continuation passes: bootstrap -> Phase 2
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
Mutable -> Sealing -> Sealed]) -> M-Q3 pagination [search_page (offset) +
search_after (after-id cursor) over the (distance asc, id asc) total
order; probe_pagination]) -> M-Q4 delete-by-filter [planner-driven
selective delete (index candidates or scan), per-point WAL, tombstones +
payload/index cleanup; probe_delete_filter]) -> M-Q5 index admin
[per-collection stats + admin rebuild_index (before/after/reclaimed);
probe_index_admin]) -> M-Q6 request extensions [SearchRequest mode
(knn/range) + offset/after-id pagination; SearchBatchRequest +
search_batch_with_request; probe_search_request extended]) -> M-G1
reference oracle [independent Float64 oracle vs kernels + axioms + all
ranked/paged/cursor/range/Hnsw paths; probe_reference_oracle]) -> M-S1
HTTP service skeleton [api.http_service byte-level HTTP/1.1 pipeline +
router; probe_http_service]) -> M-S2 service config/limits/errors
[ServiceConfig + env/file loaders; enforced limits; {error,kind,status};
shutdown checkpoint; probe_service_limits]) -> M-S3 auth + rate limiting
[API keys (constant-time, scopes read/write/admin, XVECTOR_API_KEYS);
token-bucket RateLimiter; ServiceState; probe_service_auth]) -> M-S4
security pass [fuzz gate (2500 inputs) + JSON depth guard (found+fixed a
stdlib stack-overflow); SBOM + unsafe gate scripts; SECURITY.md;
probe_http_fuzz]) -> M-O observability [metrics module (histograms +
counters + JSON log ring), /metrics + health readiness, runbook;
probe_metrics]) -> M-R release candidate [checklist audit + repro re-runs +
release notes + SBOM snapshot + owner handoff; v1.0.0-rc.1; final
batteries green at the tagged commit]) -> xiom.wal first adoption
[registry install + trust pin + xiom.toml dependency; op-code alignment
gate; D5 migration plan] -> xiom.metrics 0.2.0 adoption (observability
internals package-backed behind the same surface; engine stat counters
unified on the package; shim Counter retired after XVC-C-14;
probe_package_metrics added; bus item -7 verified + closed) -> xiom.rate
0.2.0 adoption (token-bucket internals on the package behind the same
API; carry-exact refill; probe_package_rate added; 35 probes) ->
compiler v0.64.3 re-pin + lane-local isolation (shared-home wipe incident
diagnosed + filed; out/toolchain + out/xiom-home; XVC-C-13/C-14 re-tested
unchanged; release-check verdicts filed; both batteries green isolated) ->
xiom.http helper evaluation + adoption (status phrases on the package
behind a lane adapter; router/parser evaluated, not adopted;
probe_package_http; 36 probes) -> xiom.vectors 0.1.0 wiring + fidelity
gate (byte-exact carve verified, 6/6 pins; probe_package_vectors;
atomic all-surfaces swap planned -- XVC-C-14 constraint; 37 probes) ->
xiom.vectors internals swap EXECUTED (atomic: 11 src + 27 probe imports
onto the package; five local modules deleted; codec extracted from
vector_store; batteries green both platforms).

---

## 0. STATE (hand-off point)

**Repo:** private, no pushes; clean tree. HEAD `c414e2a` (feat: xiom.vectors
internals swap) + this handoff commit; tag `v1.0.0-rc.1` still on
`530b041`. Recent slices: `c414e2a` vectors swap, `db8c443` vectors
wiring, `a7e8421` http helper slice, `845ddbc` v0.64.3 re-pin/isolation,
`a0d631f` rate adoption, `843d3ca` metrics wrap, `31b95d9` metrics
adoption, `37e9d57` XV-ORBITDB-01 wrap, `3c36f34` XV-ORBITDB-01 fix,
`1db0550` relay bus adoption, `4c02577` xiom.wal adoption, `530b041`
M-R wrap.
Identity `Lefteris Notas <lefterisnotas@gmail.com>`; conventional
commits, DCO `git commit -s`.

**Toolchain (latest-tracking; record hashes at every wrap):**

| Lane | Version / hash | Path |
|---|---|---|
| compiler | **v0.64.3 installed lane-local (2026-10-10)** on Windows (`out\toolchain`) + WSL (`~/.xvector-toolchain`); release run `38071481303` green; tag `v0.64.3` on `a5b87965` | lane-local + `%LOCALAPPDATA%\xiom.new` fallback; WSL `~/.xvector-toolchain` |
| stdlib | lane HEAD `dd352f6` (wave 105.1, io `read_file_bytes` clause fix; compatibility re-checked 2026-10-11: suite 171/171 + codec probe green); **fsync/fdatasync/fsync_dir still Err stubs** (re-checked 2026-10-11) | `E:\xiom-lang\stdlib` (= `/mnt/e/xiom-lang/stdlib`) |
| packages | lane HEAD `2b9b1146` (SESSION 19:15Z: **`xiom.ann` extracted**; assimp 0.7.0 + glfw 0.3.0; eco-v0.1.132, 48 releases); **`xiom.vectors` LIVE (eco 508)** | `E:\xiom-packages\packages` |
| xvector | `c414e2a` + this handoff commit (rc tag `v1.0.0-rc.1` = `530b041`) | this repo |

`XIOM_RUNTIME_DIR` retired (env-free builds). `xiom.toml` has
`root = "src"`, `source-roots = ["src"]` (C-PULSE-02 workaround).

**Toolchain isolation (2026-10-10):** the lane pins its OWN toolchain and
package home -- Windows `out\toolchain` + `out\xiom-home`, WSL
`~/.xvector-toolchain` + `~/.xvector-home`; both dev-env scripts set them
and every build/probe/battery inherits it. Reason: concurrent sessions on
this machine deleted the shared `%LOCALAPPDATA%\xiom\packages` home and
parts of `%LOCALAPPDATA%\xiom.new` mid-battery (bus incident
`REL-20261010-1835-xvector`), and a v0.64.3 `xiom pkg install` bug with a
custom `XIOM_HOME` on WSL misplaced the `xiom.wal` install
(`REL-20261010-1937-xvector`). Never build against the shared homes.

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
- **M-Q3 pagination (2026-10-09):** new `src/query/pagination.xi` -- the
  paginated total order is **(distance ascending, id ascending)**:
  `search_page_scan(idx, query, k, offset)` returns ranks [offset,
  offset+k); `search_after_scan(..., k, after_id)` returns the next k ranks
  strictly after the CURRENT position of `after_id` (its live vector defines
  the cursor distance; `None` when the id is gone). Both scan the raw store
  (exact on Flat AND Hnsw; ANN widening is M-P) with a bounded collector
  carrying the id tie-break. Engine `engine_search_page` /
  `engine_search_after` (facade `search_page` / `search_after`; missing
  cursor -> `Err(NotFound)`). Gate `probe_pagination` (22 checks: page
  reconstruction without gaps/dupes, exact tie clusters {1,7,8} /
  {2,15,16,17} id-ascending, cursor walks incl. tie boundaries, refusals,
  Flat/Hnsw parity, pages after recovery, deleted cursors).
- **M-Q4 delete-by-filter (2026-10-09):** `engine_delete_filter` + facade
  `delete_filter` -- remove every live point matching a typed filter.
  Planner-driven: index-answerable shapes (Eq/Range/Exists/And-of-those)
  resolve candidates from the sorted payload index (each verified);
  In/Or/Not scan the live store. Ids are collected BEFORE mutating (store
  shifts cannot skip points) and applied ascending (plan-independent WAL)
  through the gated single-delete path: per-point WAL record, graph
  tombstone (Hnsw), payload + index cleanup. Nothing matching -> Ok(0).
  Gate `probe_delete_filter` (26 checks: eq/range/exists/in/not/or/and
  plans, idempotence, index cleanup, match-none/ match-all, lsn delta per
  removal, recovery + chained recovery, Hnsw tombstones + compaction +
  search exclusion, multi-collection isolation).
- **M-Q5 index admin (2026-10-09):** `engine_collection_stats` + facade
  `collection_stats` -- per-collection stats (name/cid/dim/metric/index
  kind/ANN params, live points, payloads, Hnsw nodes + tombstones, shared
  WAL lsn); the active collection reports from the live fields, parked
  collections from their registry entries (no switching); unknown ->
  Err(NotFound). `engine_rebuild_index` + facade `rebuild_index` -- admin
  rebuild from the flat store with `IndexStats` (kind/points/nodes_before/
  nodes_after/reclaimed): Hnsw = fresh graph over live nodes (tombstones
  reclaimed), Flat = no-op with zeroed stats; `compact_index` stays the Int
  wrapper. Gate `probe_index_admin` (20 checks: config/counts exactness,
  tombstone accounting, rebuild stats/idempotence/search equality vs a
  flat twin, parked-vs-live agreement, set_index transitions,
  compact_index compat, lsn/points movement, recovery consistency).
- **M-Q6 request extensions (2026-10-09):** `SearchRequest` gains `mode`
  (`SearchMode.Knn | Range`), `radius` (range mode; `top_k` = inclusive-
  radius limit), `offset` (knn page ranks) and `after_id` (knn cursor,
  -1 = none), with setters `set_mode/set_range/set_page/set_after`;
  defaults are the old plain-knn behavior. Dispatch: Range -> exact range
  path (hydrated); filters/pagination are Knn-only and rejected loudly in
  range mode; `offset`+`after_id` mutually exclusive; pagination does not
  combine with filters yet; cursor keeps `Err(NotFound)`. Batch:
  `SearchBatchRequest` + `HydratedBatch` + `search_batch_with_request`
  (one HydratedHits per request, order preserved, all-or-nothing).
  `probe_search_request` extended to 24 checks (range radii 0.5/1.0
  inclusive + hydration, range refusals, page/cursor dispatch matching
  the kernels, mutex + filter refusals, batch order/empty/abort).
- **M-G1 reference oracle (2026-10-09):** new `probe_reference_oracle`
  (22 checks) -- an INDEPENDENT Float64 oracle (own loops over the raw
  Float32 storage, `math.sqrt` in Float64, no `vector_distance` calls):
  pairwise kernel agreement for cosine/dot/euclidean (780 seeded pairs
  each; measured deviations at Float32-ulp scale: 1.70e-07 / 9.83e-07 /
  5.06e-07, bit-identical Windows/WSL), metric axioms (exact symmetry;
  self-distance l2==0 / cosine~0 / dot==-|v|^2; euclidean triangle
  inequality on engine values; cosine bounds [0,2] + exact x2 scale
  invariance; zero-vector cosine guard == 1.0), and the ranked search
  paths vs the oracle ranking (top-5 rank exact per metric; hit
  distances within tolerance; page ranks 5..12; cursor ranks 7..14;
  inclusive-range subset at a midpoint radius + engine-distance boundary
  inclusion; Hnsw recall@5 == 5/5 + distance fidelity).
- **M-S1 HTTP service skeleton (2026-10-09):** new `src/api/http_service.xi`
  -- transport-agnostic `http_service_handle(eng, raw) -> response`
  (parse -> route -> JSON -> serialize; bytes in, bytes out; no sockets
  until the `xiom.net` proof, C-PULSE-02). Strict HTTP/1.1 parsing (CRLF
  framing, lowercased headers, Content-Length must match the body
  exactly; incomplete -> 400 "incomplete request", trailing -> 400).
  Endpoints: GET /health, GET/POST /collections, GET/POST/DELETE
  /collections/{n}/points, POST /search (knn/range/page/batch), GET
  /stats?collection=; honest statuses 400/404/405/409/500. Uses the
  stdlib JSON engine with QUALIFIED calls (`json.json_*`): unqualified
  names misresolve to the parent `xiom.serialize` helpers in this unit
  (BUG 25 #1 -- documented in the json module header) and silently built
  empty string values; numeric request fields are strictly typed. Two
  real parser bugs found via the probe: the method was validated but
  never stored, and the header scan dropped the final header line
  (Content-Length). Gate `probe_http_service` (40 checks).
- **M-S2 service config/limits/errors (2026-10-09):** `ServiceConfig`
  (max_request_bytes 65536 / max_top_k 1000 / max_batch 256 / max_dim
  1024) + `service_config_from_env` (XVECTOR_MAX_*; malformed ignored)
  + `service_config_load` (key=value file; comments; unknown keys
  ignored; malformed line -> valid=false with good lines kept).
  `http_service_handle_cfg` enforces limits (413 size/batch before/at
  routing, 400 named top_k/dim; boundary requests accepted); every error
  is `{error,kind,status}` with stable kinds, and `core_err_response`
  maps the full CoreError enum. `http_service_shutdown(eng, wal_path)` =
  drain + whole-file WAL checkpoint (false when unwritable). Gate
  `probe_service_limits` (27 checks).
- **M-S3 auth + rate limiting (2026-10-09):** `ApiScope { Read; Write;
  Admin }` (ordered) + `ServiceAuth` (keys 8..128 of `[A-Za-z0-9_.-]`,
  duplicates rejected; first key enables; disabled default in embedded
  mode); lookups via the stdlib constant-time comparator
  (`xiom.crypto.mac.constant_time_eq`); `service_auth_parse_list` /
  `service_auth_from_env` (`XVECTOR_API_KEYS`). Route scope map (/health
  public; POST /collections Admin; points POST/DELETE Write; else Read);
  401 unauthorized / 403 forbidden / 429 rate_limited kinds. Token-bucket
  `RateLimiter` (capacity + refill/sec, explicit clock, `last_ms = -1`
  sentinel); `ServiceState { cfg; auth; rate }` +
  `http_service_handle_state` (rate -> parse -> auth/scope -> route;
  auth-off == handle_cfg). Gate `probe_service_auth` (24 checks).
- **M-S4 security pass (2026-10-09):** `docs/SECURITY.md` (assets, trust
  boundaries, secure-defaults table, threat/control matrix, dependency +
  SBOM statement, no-unsafe audit, honest out-of-scope list).
  `probe_http_fuzz` (14 checks: 1200 seeded mutations + 1300 random
  streams all well-formed; targeted abuse -- empty/lying-CL/header-flood/
  30 KB header/60 KB unbalanced JSON/8000-deep nesting/NUL/500-segment
  path/300-burst; phase marks in `out/fuzz_mark.txt` for forensics).
  **Found + fixed a remote stack-exhaustion DoS**: the stdlib `json_parse`
  recurses per nesting level, so ~60 KB of `[` (inside the body limit)
  crashed the service with an access violation; the HTTP edge now
  pre-scans with `json_depth_ok(body, 64)` (string-aware, linear) and
  rejects deeper payloads with 400 -- the stdlib gap is filed in
  `docs/STDLIB-WISHLIST-XVECTOR.md`. `scripts/sbom.ps1`/`sbom.sh` emit
  `out/sbom.json` (compiler, stdlib pin, per-module sha256, unsafe=0) and
  FAIL on any `unsafe` in src/; both batteries now run the SBOM + unsafe
  gate.
- **M-O observability core (2026-10-09):** new
  `src/observability/metrics.xi` -- fixed-bucket latency `Histogram`
  (1/5/10/50/100/500/1000 ms + `+Inf`; `_sum`/`_count`/p50/p95/p99),
  `ServiceMetrics` (requests/errors/search_ops/upsert_ops/auth_failures/
  rate_limited counters + global and search histograms) and a bounded
  JSON-log `LogRing` (method/path/status/ms/slow, hostile strings
  sanitized, oldest-first eviction + `dropped`). Service: public
  `GET /metrics` (prometheus text: counters, cumulative buckets +
  percentiles, live gauges collections/points_active/lsn), `/health`
  gains `ready:true`, and `http_service_handle_state` instruments every
  request (status-derived counters, latency, op classification, one log
  line). Worked around the XVC-C-09 family AGAIN: nested-field mutation
  through a `&mut` param (`st.metrics.counter`) silently does not
  persist -- the wrapper copies the metrics struct out and writes back
  once. `docs/OPERATIONS.md` runbook (start/stop, config, monitoring +
  alerts, backup/restore drill, failure domains, migration, diagnostics).
  Gate `probe_metrics` (23 checks).
- **M-R release candidate v1.0.0-rc.1 (2026-10-09):** `VERSION` =
  `1.0.0-rc.1`; `docs/RELEASE-NOTES-v1.0.0-rc.1.md`;
  `docs/sbom-v1.0.0-rc.1.json` (44 modules, unsafe=0);
  `docs/OWNER-HANDOFF.md` (repo public / runners / rulesets / publish
  flow / benchmark protocol + gated-pivot table + evidence index);
  `docs/RELEASE-CHECKLIST.md` audited step-by-step with the repro re-runs
  (9 green, `contract-trap-exit0` exit 1 = fixed symptom, XVC-C-13 open
  by design). Final batteries at the rc commit `5226226`: Windows + WSL,
  ALL GATES GREEN. Tag `v1.0.0-rc.1` annotated (no GPG key on this
  machine; commits carry DCO sign-off). **The owner has been told; the
  public release + benchmark are the owner's actions.**
- **xiom.wal first adoption (2026-10-10):** C-PULSE-02 RESOLVED in v0.64.2
  -- `xiom.toml [dependencies] xiom.wal = "0.1.0"` maps the installed
  package root into the catalog; `xiom.wal` 0.1.0 installed from the
  registry on Windows + WSL (sha256 + ed25519 verified; registry key
  pinned via `xiom pkg trust`, fp `4f:3b:47:f3:ae:17:b1:3c`). Alignment
  verified: op codes 1..7 byte-identical to our codec (8/9/10 txn ops);
  same payload carrier (+ `timestamp`); same LSN semantics; equivalent
  torn-tail outcome. Gate `probe_package_wal` (9 checks: codes, tagged
  roundtrip, LSN resume, torn-tail skip + heal-on-open, missing-path
  open). Design + D5 migration plan: `docs/XIOM-WAL-ADOPTION.md`.
  Discovery: `XIOM_HOME/packages` also carries `xiom.metrics` 0.2.0,
  `xiom.rate` 0.2.0, `xiom.router` 0.1.0, `xiom.http` 0.1.4 -- scheduled
  as gated adoption slices (metrics first).
- **xiom.metrics 0.2.0 adoption (2026-10-10, 55th pass):** second
  registry adoption. `observability.metrics` internals run on the package
  behind the same exported surface (`/metrics` output byte-identical):
  package `Histogram`/`Counter` value types, lane accessors + the
  percentile helper (package SPEC excludes percentiles), the Prometheus
  histogram block moved into the module (consumers never name the package
  types); engine stat counters (`upserts`/`deletes`) moved onto the
  package and the core shim `Counter` was retired -- forced by
  **XVC-C-14** (two same-named struct types across modules shadow each
  other's field layout; clang store reject when incompatible, silent when
  compatible). Minimal repro `docs/repro/xv-counter-type-shadow/`
  (Windows + WSL identical, clang exit 1); relay Addendum 10; bus item
  `REL-20261010-1709-xvector`. Gates: new `probe_package_metrics`
  (12 checks, direct package) + re-gated `probe_metrics` (24 checks incl.
  package min/max/mean alignment); both batteries now **34 probes**.
  Record: `docs/XIOM-METRICS-ADOPTION.md`.
- **xiom.rate 0.2.0 adoption (2026-10-10, 56th pass):** third registry
  adoption. The S3 `RateLimiter` internals run on the package
  `TokenBucket` behind the same API (`rate_limiter_new/_disabled/_allow`
  unchanged; 429 path + the rate-limited counter unchanged). Accuracy
  delta: unearned sub-token remainders are now carried, so fractional
  refill is exact (the lane limiter consumed the whole elapsed span and
  discarded remainders); every gate-visible boundary (capacity drain,
  rate 0, whole-second refill) is unchanged -- `probe_service_auth` (24
  checks) and `probe_metrics` (24) stay green unmodified. Gates: new
  `probe_package_rate` (14 checks: bucket drain/refill/carry/rate 0/
  clamp/retry/cost, fixed window, keyed bucket + keyed window layers);
  batteries now **35 probes**. Record: `docs/XIOM-RATE-ADOPTION.md`.
  Also this pass: orbitdb **closed** the `REL-20261010-1550-orbitdb-11`
  bus item after their verification of the XV-ORBITDB-01 fix; v0.64.3
  **released** by the compiler lane (assets staged + sha256-verified;
  version upgrade + full re-test + release-check verdicts are the next
  pass).
- **compiler v0.64.3 re-pin + isolation (2026-10-10, 57th pass):** v0.64.3
  released (run `38071481303`; tag `v0.64.3` on `a5b87965`), assets
  sha256-verified, installed lane-local on Windows + WSL; full re-test:
  all 12 repro bundles re-run (17/18 single-file probes green), XVC-C-13
  (Win 71 / WSL 127) and XVC-C-14 (clang `xiominput.ll:850`) re-tested
  **UNCHANGED** -> release-check verdicts filed
  (`release-checks/compiler-compiler-v0.64.3`); then the shared-home wipe
  incident hit mid-battery on both platforms: diagnosed (recursive delete
  of the shared homes by concurrent activity), filed as
  `REL-20261010-1835-xvector`, and neutralized for the lane with
  lane-local toolchain + package home; the WSL `xiom pkg install`
  custom-`XIOM_HOME` misplacement was found and filed on the way
  (`REL-20261010-1937-xvector`); final isolated batteries green on both
  platforms. Also recorded: **`xiom.vectors` LIVE (eco 508)** + `xiom.ann`
  extracted by the packages lane (our wishlist items `-9` fixed /
  `-10` acked).
- **xiom.http helper evaluation + adoption (2026-10-10, 58th pass):**
  `xiom.router` 0.1.0 + `xiom.http` 0.1.4 evaluated for the service:
  **`xiom.http.status.http_status_text` ADOPTED** behind a 3-line lane
  adapter (every emitted code keeps its pre-adoption wire text;
  the package has no 507 -> the lane keeps "Insufficient Storage" and
  its "Error" fallback; upstream gap filed `REL-20261010-2002-xvector`);
  **router + parser/types/client NOT adopted** (static 7-route dispatch
  + strict byte pipeline are gate-pinned; full reasons in
  `docs/XIOM-HTTP-EVAL.md`). New `probe_package_http` (5 checks) + the
  `probe_http_service` raw `HTTP/1.1 507 Insufficient Storage` pin
  (41 checks); batteries now **36 probes**. Next adoption candidate:
  **`xiom.vectors` (LIVE)**.
- **xiom.vectors 0.1.0 wiring + fidelity gate (2026-10-10, 59th pass):**
  the registry extraction of THIS lane's own primitives; **all six SPEC
  extraction pins match the current tree byte-for-byte** (byte-exact
  carve; behavior-identical by construction). `xiom.toml` dependency +
  new `probe_package_vectors` (13 checks: distances on
  exactly-representable corpora, normalize, metric codes, dimension,
  top-K ordering/eviction, codec round-trip, torn-skip replay); the
  package's own codec probe runs green from the lane home (bit-exact
  incl. -0.0 / denormal / max). Batteries now **37 probes**. Internals
  swap planned as **one atomic step** (all six surfaces at once --
  partial swaps are an XVC-C-14 short-name hazard; ~45 import sites) in
  `docs/XIOM-VECTORS-EVAL.md`; gated on owner greenlight `-12` + a quiet
  window, sequenced with the `xiom.ann` porter flow.
- **xiom.vectors internals swap EXECUTED (2026-10-10, 60th pass):** the
  atomic change set (51 files: 96 insertions, 409 deletions) put every
  consumer on the package -- 11 source modules + 27 probes now import
  `xiom.vectors`; the five local modules
  (`types/dense_vector|metric|neighbor|dimension`, `query/topk_heap`)
  are deleted; the WAL value codec was stripped from
  `storage/vector_store` (encode/decode resolve through the package
  import). Behavior-identical by construction (pins byte-exact);
  verified by the full batteries on **Windows AND WSL** (suite 171/171
  x2 + sbom + 37 probes x2 + bench smoke), including the
  `probe_reference_oracle` kernel-fidelity and `probe_floatval_roundtrip`
  bit-exact gates. Docs swept to the package paths (SPEC/ARCHITECTURE/
  contracts/core-vs-vector/query-execution/vector-types-and-metrics);
  record: `docs/XIOM-VECTORS-EVAL.md` §3. Also found + filed the
  v0.64.3 diagnostic gap: unresolvable imports are silently ignored
  (`REL-20261010-2124-xvector`; explained part of the shared-home
  incident misdiagnosis).
- **Bus round (2026-10-10, 55th pass):** `REL-20261010-1550-xvector-7`
  (json depth cap) **verified + closed** -- boundary re-run against the
  stdlib checkout (`a16daff`): 128-deep Ok; 129 and 60000-deep Err
  `json_parse: nesting too deep`; Windows + WSL identical; the HTTP
  64-level pre-scan stays as defense in depth. XVC-C-14 filed to the
  compiler lane (bug). Shared-clone note: the bus clone on this machine
  is used by several lane sessions; scope `git add` to your own item
  files (ops item `REL-20261010-1709-compiler` tracks per-lane
  clone/helper proposals; expect interleaved commits).
- **XV-ORBITDB-01 fix (2026-10-10):** relay item from the orbitdb lane on
  the new bus: chained persist/load of a RECOVERED engine's WAL reloaded
  EMPTY because `wal_load` required the first record's LSN to be exactly
  1, while recovered checkpoints resume LSNs (silent vector loss on the
  next open). Fixed in `wal_file.wal_load` (commit `3c36f34`): the first
  record may start at any LSN >= 1, consecutive +1 stepping still
  enforced, torn-tail/corruption behavior unchanged. Gate
  `probe_wal_file` +3 chained checks (persist a recovered checkpoint,
  non-empty reload with the resumed first LSN, second recovery equals
  live). Bus item moved open -> acked -> fixed with the commit ref
  (orbitdb verifies at its next release check).
- **FloatVal workaround unwound** after the v0.64.1 fix: float payload
  gates restored in the suite and probes.
- **Production tracker:** `docs/PRODUCTION-READINESS.md` -- weighted
  scorecard, **80 % today**; recompute at every wrap.

**Green evidence (compiler v0.64.2 installed 2026-10-09 + stdlib lane
`d2b18dc` = 0.64.3; latest re-verification = XV-ORBITDB-01 fix pass on
the current tree):**

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
- **M-Q3 pagination pass:** suite **171/171 x2** + **24 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_pagination`
  (22 checks) wired into both batteries; WSL spot x2 bit-identical.
- **M-Q4 delete-filter pass:** suite **171/171 x2** + **25 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_delete_filter`
  (26 checks) wired into both batteries; WSL spot x2 bit-identical.
- **M-Q5 index-admin pass:** suite **171/171 x2** + **26 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_index_admin`
  (20 checks) wired into both batteries; WSL spot x2 bit-identical.
- **M-Q6 request-extensions pass:** suite **171/171 x2** + **26 probes x2**
  + bench smoke (Windows + WSL), ALL GATES GREEN; `probe_search_request`
  extended 10 -> 24 checks (probe-only gate; suite mirror untouched --
  the mirror is a standalone re-implementation); WSL spot x2
  bit-identical.
- **M-G1 reference-oracle pass:** suite **171/171 x2** + **27 probes x2** +
  bench smoke (Windows + WSL), ALL GATES GREEN; new
  `probe_reference_oracle` (22 checks) wired into both batteries; WSL
  spot x2 bit-identical (same Float32-ulp deviations).
- **M-S1 service pass:** suite **171/171 x2** + **28 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_http_service`
  (40 checks) wired into both batteries; WSL spot x2 bit-identical.
- **M-S2 limits pass:** suite **171/171 x2** + **29 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_service_limits`
  (27 checks) wired into both batteries; WSL spot x2 bit-identical.
- **M-S3 auth pass:** suite **171/171 x2** + **30 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_service_auth`
  (24 checks) wired into both batteries; WSL spot x2 bit-identical.
- **M-S4 security pass:** suite **171/171 x2** + **SBOM/unsafe gate** +
  **31 probes x2** + bench smoke (Windows + WSL), ALL GATES GREEN; new
  `probe_http_fuzz` (14 checks) wired into both batteries; the JSON depth
  guard fixed a found stack-overflow DoS; WSL spot (sbom.sh + fuzz x2)
  bit-identical.
- **M-O observability pass:** suite **171/171 x2** + **SBOM/unsafe gate** +
  **32 probes x2** + bench smoke (Windows + WSL), ALL GATES GREEN; new
  `probe_metrics` (23 checks) wired into both batteries; WSL spot x2
  bit-identical.
- **M-R release-candidate pass:** final batteries at commit `5226226`
  (v1.0.0-rc.1): suite **171/171 x2** + **SBOM/unsafe gate** + **32 probes
  x2** + bench smoke on **Windows AND WSL**, ALL GATES GREEN; all primary
  repro bundles re-run at v0.64.2 (expected statuses); checklist + owner
  handoff + release notes committed; annotated tag `v1.0.0-rc.1`.
- **xiom.wal adoption pass:** suite **171/171 x2** + **SBOM/unsafe gate** +
  **33 probes x2** + bench smoke on **Windows AND WSL**, ALL GATES GREEN
  with the registry dependency active in every build; `probe_package_wal`
  (9 checks) wired into both batteries; WSL spot x2 bit-identical.
- **XV-ORBITDB-01 fix pass:** suite **171/171 x2** + **SBOM/unsafe gate** +
  **33 probes x2** + bench smoke on **Windows AND WSL**, ALL GATES GREEN;
  `probe_wal_file` gained the three chained-reopen checks; the relay item
  is `fixed` with commit `3c36f34`; WSL spot x2 bit-identical.
- **xiom.metrics adoption pass (55th):** suite **171/171 x2** +
  **SBOM/unsafe gate** + **34 probes x2** + bench smoke on **Windows AND
  WSL**, ALL GATES GREEN; new `probe_package_metrics` (12 checks) and the
  re-gated `probe_metrics` (24 checks) green on both platforms;
  `docs/repro/xv-counter-type-shadow` reproduces XVC-C-14 on both
  (clang exit 1, `xiominput.ll:850`); the json-depth boundary unit
  (128-deep Ok; 129/60000 Err) green on Windows + WSL (bus item -7
  verified + closed; stdlib checkout `a16daff`).
- **xiom.rate adoption pass (56th):** suite **171/171 x2** +
  **SBOM/unsafe gate** + **35 probes x2** + bench smoke on **Windows AND
  WSL**, ALL GATES GREEN; new `probe_package_rate` (14 checks) green on
  both platforms; `probe_service_auth`/`probe_metrics` re-verified with
  the package-backed limiter (orbitdb closed the XV-ORBITDB-01 bus item
  this pass).
- **v0.64.3 re-pin pass (57th):** Windows AND WSL isolated batteries ALL
  GATES GREEN (suite **171/171 x2** + sbom + **35 probes x2** + bench
  smoke each); repro re-test on v0.64.3: 12 bundles, 17/18 single-file
  probes green, C-13/C-14 red as filed; release-check verdicts filed on
  `release-checks/compiler-compiler-v0.64.3`; the first two WSL battery
  reds were the shared-home wipe (environmental), root-caused and fixed
  with lane-local isolation.
- **xiom.http helper pass (58th):** Windows AND WSL batteries ALL GATES
  GREEN (suite **171/171 x2** + sbom + **36 probes x2** + bench smoke
  each); new `probe_package_http` (5 checks) green both platforms;
  `probe_http_service` 41/41 incl. the raw 507 status-line pin;
  `probe_service_limits` 27/27 with the package-backed phrases.
- **xiom.vectors wiring pass (59th):** Windows AND WSL batteries ALL
  GATES GREEN (suite **171/171 x2** + sbom + **37 probes x2** + bench
  smoke each); new `probe_package_vectors` (13 checks) green both
  platforms; extraction pins re-hashed 6/6 MATCH; the package's own
  codec probe green (bit-exact).
- **xiom.vectors swap pass (60th):** Windows AND WSL batteries ALL GATES
  GREEN on the swapped tree (suite **171/171 x2** + sbom + **37 probes
  x2** + bench smoke each); zero stale module references; three
  representative probes compiled green on first try; scratch resolver
  experiments (positive/negative controls) confirmed the silent-import
  behavior filed as `REL-20261010-2124-xvector`.
- All **37 probes x2** green on Windows: `probe_hello`, `probe_bind_semantics`,
  `probe_engine_import`, `probe_vector_store`, `probe_filtered_search`,
  `probe_payload_recovery`, `probe_floatval_roundtrip`, `probe_search_request`,
  `probe_payload_index`, `probe_filter_plan`, `probe_hnsw_recall`,
  `probe_engine_hnsw`, `probe_hnsw_codec`, `probe_result_shapes`,
  `probe_fuzz_codecs`, `probe_soak_mixed`, `probe_kill_recovery`,
  `probe_wal_file`, `probe_manifest_file`, `probe_collections`,
  `probe_segment_file`, `probe_range_search`, `probe_pagination`,
  `probe_delete_filter`, `probe_index_admin`, `probe_reference_oracle`,
  `probe_http_service`, `probe_service_limits`, `probe_service_auth`,
  `probe_http_fuzz`, `probe_metrics`, `probe_package_wal`,
  `probe_package_metrics`, `probe_package_rate`, `probe_package_http`,
  `probe_package_vectors`, `probe_batch_ops`
  (run via `scripts\run-probe.ps1`); plus the SBOM + unsafe gate
  (`scripts/sbom.ps1`, `scripts\sbom.sh`).
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
- Relay for the compiler lane: `docs/RELAY-COMPILER.md` (Addenda 3-10;
  8 = v0.64.2 re-test; 9 = XVC-C-13; 10 = XVC-C-14). Incoming relay
  `docs/COMPILER-RELAY-2026-10-09-v0.64.2.md` (m220-m239) -- actioned:
  suite + pinned probes re-run on the archive, no residual reds.
- **XVC-C-14 (OPEN, found 2026-10-10, 55th pass):** two same-named
  struct types across modules shadow each other's field layout
  (short-name resolution at struct emission; clang store reject when the
  layouts differ, silent wrong fields when they match). Found during the
  xiom.metrics adoption (shim `Counter` + package `Counter`); repro
  `docs/repro/xv-counter-type-shadow/` (4 modules + manifest; Windows +
  WSL identical); workaround adopted (single `Counter` type; shim
  Counter retired); relay Addendum 10; bus item
  `REL-20261010-1709-xvector`; re-test at the next archive (v0.64.3 is
  in the compiler lane's release gate -- no installable archive yet).

---

## 1. NEXT TASKS (priority order)

**Programme:** `docs/PRODUCTION-PLAN.md` (v1.0 flagship plan) +
`docs/requirements/production-v1.md` + `docs/checklists/production-v1.md`.
Work proceeds autonomously slice-by-slice under the lane's goal loop, one
verified slice at a time (suite x2 + all probes x2, Windows + WSL spot,
signed commits, docs updated).

1. **ALL SLICES DONE + v1.0.0-rc.1 PREPARED + five registry surfaces
   live (`xiom.wal`, `xiom.metrics`, `xiom.rate`, `xiom.http` status
   subset, **`xiom.vectors` swapped -- the package now backs all vector
   consumers**) + compiler v0.64.3 re-pinned lane-local (isolated).**
   Remaining order: the `xiom.ann` porter flow (awaits its publication;
   registry 404 as of 2026-10-10), the replay-loop delegation at the
   D-ledger store migration, then the owner's public release +
   benchmark. Gated pivots: D5/D6 on the stdlib fsync chain (still Err
   stubs at `5468469`), the socket adapter on the stdlib `xiom.net`
   proof, P5 on stdlib mmap, `xiom.kv` on C-PULSE-10 + fsync.
2. **M-Q query surface: DONE (Q1-Q6** -- range search, batch ops,
   pagination, delete-by-filter, per-collection stats + index admin,
   SearchRequest extensions). All gated by their probes.
3. **M-G truth & measurement: DONE (G1-G3)** -- reference-oracle
   cross-check, `bench/` harness, `docs/BENCHMARKS.md` baseline +
   external-benchmark protocol (this is what the owner's benchmark
   drives).
4. **M-S server & security: DONE (S1-S4** -- HTTP skeleton,
   config/limits/errors, API-key auth + rate limiting, security pass +
   SBOM); **M-O observability DONE** (metrics//metrics/logs/runbook).
5. **Gated (pick up when the stdlib lane lands the primitives):** D5 delta
   append + fsync + file-level kill-matrix; D6 truncate-based retention;
   P5 mmap segments. Re-check each pass (0.64.3: still stubs --
   `docs/STDLIB-WISHLIST-XVECTOR.md`).
6. **Porter flow (owner-gated):** `xiom.vectors`/`xiom.ann` extraction on
   greenlight (items `REL-20261010-1550-xvector-9/-10/-12`); **`xiom.wal`
   ADOPTED** (0.1.0 registry install + trust pin + `xiom.toml
   [dependencies]`; C-PULSE-02 resolved; gate `probe_package_wal`);
   `docs/PACKAGE-WISHLIST-XVECTOR.md` keeps the lane ledger.
7. **Release gate:** when the M-R criteria are met the lane tells the owner
   -- the owner sets up the public release + benchmark (PULSE-style).

## 2. Consumer-lane rules (non-negotiable)

- **Reference study area (owner-granted, 2026-10-11): `E:\repos` may hold
  cloned MIT-licensed projects as STUDY references -- ideas, patterns,
  mechanics from battle-tested production code -- to elevate xvector.
  Rules: MIT only; study, never vendor blindly or add as a build
  dependency; any adopted pattern is re-implemented in our module tree
  under our license and gated by our probes (commit notes the source
  reference).** Cloned and MIT-verified 2026-10-11: `sqlite-vec`
  (MIT/Apache; compact embeddable vector search -- brute-force kernels,
  quantization, host ergonomics), `faiss` (MIT; HNSW/IVF/PQ mechanics,
  memory mapping, SIMD layouts), `DiskANN` (MIT; SSD-resident ANN --
  informs D5/D6 segment reads + P5 mmap). Sibling-lane references already
  present: `redb`/`bbolt` (storage lanes), `godot`/`JoltPhysics` (game
  lanes). Study backlog (one item per slice, findings recorded in the
  slice docs): (1) faiss HNSW level assignment + search sampling vs ours;
  (2) faiss/vec product quantization for compaction; (3) sqlite-vec
  quantized brute-force kernels vs our flat scan; (4) DiskANN layout
  notes for D5 delta segments + P5 mmap. Study item 1 (FAISS HNSW)
  DONE 2026-10-11 -> `docs/REFERENCE-STUDY-01-FAISS.md` (ranked
  proposals: P-a level-0 degree generosity -- first candidate slice, gate
  `probe_hnsw_recall` + per-ef table; P-b visited generation tags for
  M-P; P-e quantization next study).**

- **Coordination bus (2026-10-10, owner rollout): at session start and
  before finishing any task, pull `E:\xiom-lang\xiom-relays`
  (`git pull --ff-only`) and process items addressed to this lane
  (`python tools/relay.py view --lane xvector`). Recurring doorbell: a
  3-hour cron session check is armed.**
- **Shared bus clone:** the local `xiom-relays` working copy is shared by
  several lane sessions on this machine -- scope `git add` to your own
  item files (never `git add .`), expect commits interleaved by other
  lanes, and re-pull before every transition batch. Ops item
  `REL-20261010-1709-compiler` tracks per-lane clones / a
  `relay.py commit --lane` helper (helper now exists: use
  `python tools/relay.py commit --lane xvector <ids...>`).
- **Shared-machine rule (2026-10-10):** never build against the shared
  toolchain/package homes (`%LOCALAPPDATA%\xiom*`,
  `~/.local/share/xiom`); the dev-env scripts pin lane-local paths
  (`out\toolchain` + `out\xiom-home`; `~/.xvector-toolchain` +
  `~/.xvector-home`). Concurrent sessions deleted the shared state
  mid-battery (`REL-20261010-1835-xvector`); treat sudden
  unresolved-package build errors as environmental first.
- **Never edit another lane's item; open a new item instead** (one item =
  one file; only the addressed lane moves open->acked->fixed; only the
  reporter moves fixed->verified->closed; owner items are the owner's).
- **Never edit** `E:\xiom-lang\stdlib`, `E:\xiom-lang\xiom`,
  `E:\xiom-packages\packages`. Record their HEAD hashes each wrap:
  `git -C <lane> log -1 --format="%h %cI %s"`.
- Upstream reporting now goes through `xiom-relays` items (the relay docs
  keep closed history with a header pointing at the relay ids);
  `RELAY-INTRO-XVECTOR.md` stays as the lane intro.
- Consume packages from the registry only; propose reusable primitives as
  packages (`xiom.vectors` / `xiom.wal` / `xiom.ann`).
- Repo stays private; no pushes (the private relay bus is the only shared
  mailbox); commits signed (`-s`) at every step.

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
- **XVC-C-14 (OPEN on v0.64.2; the workaround is the lane convention):
  never let two same-named struct types meet in one program -- struct
  field layouts resolve by short name across modules (clang store reject
  when the shapes differ, silent wrong fields when they match).** The
  lane keeps a single `Counter` type (engine stats + observability on
  `xiom.metrics`); repro `docs/repro/xv-counter-type-shadow/`; relay
  Addendum 10; re-test at the next archive.
- **Stdlib JSON calls must be QUALIFIED (`json.json_*`) in this lane: the
  parent `xiom.serialize` defines same-named helpers that misresolve
  under the compiler (BUG 25 #1, documented in the stdlib json module
  header); unqualified `json_string()` silently built empty string
  values in `api.http_service`.** Gate `probe_http_service` pins the
  wire behavior.
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

## 5. Ecosystem status (2026-10-10)

- **stdlib:** current lane HEAD `dd352f6` (wave 105.1: io `read_file_bytes`
  clause made payload-free -- pulse-reported nested-path static-read
  trap; compatibility re-checked 2026-10-11: suite + codec probe green).
  Wave 102 `5b7bf8f` = **bounded-depth `json_parse` FIXED** -- the
  xvector bus item `-7` is verified + closed 2026-10-10: 128-deep Ok;
  129/60000 Err; Windows + WSL identical. **Re-checked 2026-10-11:
  fsync/fdatasync/fsync_dir return Err stubs (`xiom/os/fs_ffi.xi:238`,
  `xiom/os/sync_io.xi:88`); the fd path (`write_all` etc.),
  `append_file_bytes`, `truncate`/`ftruncate` still open; no
  `f32_bits`/`bits_to_f32`; `flush_stdout` still a no-op** (see
  `docs/STDLIB-WISHLIST-XVECTOR.md`). `io.rename` exists -- atomic
  temp+rename checkpoint hardening is available today (used by M-D1).
  Byte-exact file writes / CRLF-clean reads since 0.64.2.
- **compiler:** **v0.64.3 installed lane-local** (2026-10-10; release
  `REL-20261010-1727-compiler`; run `38071481303` green; tag on
  `a5b87965`; scope m243-m246, m248, m249, m252 -- m247/m250/m251
  reverted). Full re-test on v0.64.3: all 12 repro bundles re-run
  (17/18 single-file probes green); **XVC-C-13 and XVC-C-14 re-tested
  UNCHANGED** (still open; verdicts filed on
  `release-checks/compiler-compiler-v0.64.3`; C-13: Win 71 / WSL 127;
  C-14: clang store mismatch at `xiominput.ll:850`). v0.64.2-era
  re-tests: relayed fixes C-03/06/07/08 verified, C-10..C-12 green
  (Addendum 8). **Findings acked by the compiler lane** (accepted into
  their queue 2026-10-10, still unfixed): **XVC-C-13** (`&Str`
  parameters unknown
  to the checker -> i64 fallback, silent wrong values; Addendum 9)
  **and XVC-C-14** (same-named struct types shadow field layouts;
  Addendum 10; bus items `REL-20261010-1550-xvector` /
  `-1709-xvector` now `acked`). Compiler-lane HEAD `6cbcc53e`.
- **packages:** lane HEAD `2b9b1146` (2026-10-10 19:15Z: **`xiom.ann`
  extracted**, assimp 0.7.0 + glfw 0.3.0 published, eco-v0.1.132,
  48 eco releases); xiom.durable port + WAL reconciliation
  wrapped earlier (152/152 x2). **`xiom.wal` 0.1.0 is ADOPTED by XVECTOR
  (2026-10-10)** -- installed from the registry on Windows + WSL (sha256 +
  ed25519 verified), registry key pinned via `xiom pkg trust`
  (fp `4f:3b:47:f3:ae:17:b1:3c`), `xiom.toml [dependencies]` wired
  (C-PULSE-02 RESOLVED in v0.64.2), gate `probe_package_wal`; op codes
  1..7 byte-identical, migration plan in `docs/XIOM-WAL-ADOPTION.md`.
  `xiom.wal` is the single WAL home (`wal_flush` no-op on the same fsync
  gap); the local `durability.wal`/`wal_file` stay until the D5 slice
  swaps the disk segment. **`xiom.vectors` LIVE (eco 508)** and
  **`xiom.ann` extracted** (our wishlist items `-9` fixed / `-10`
  acked; owner greenlight item `-12` still open; porter flow next); a
  WSL `xiom pkg install` custom-`XIOM_HOME` misplacement was found
  during lane-home setup (`REL-20261010-1937-xvector`). **`xiom.metrics`
  0.2.0 + `xiom.rate` 0.2.0 ADOPTED by XVECTOR (2026-10-10, 55th/56th
  passes; see `docs/XIOM-METRICS-ADOPTION.md` /
  `docs/XIOM-RATE-ADOPTION.md`); **router/http evaluated 2026-10-10: the
  `xiom.http.status` helper subset ADOPTED, router/parser not adopted
  (`docs/XIOM-HTTP-EVAL.md`); `xiom.vectors` 0.1.0 WIRED + GATED +
  SWAPPED (59th/60th passes; the package now backs every vector
  consumer -- `docs/XIOM-VECTORS-EVAL.md`)**;
  `xiom.kv` gated on C-PULSE-10 + fsync. Bindings relay (2026-10-09):
  blas-class accelerators stay **GATED** (incubating placeholders, no
  timeline; pilot complete through batch 22) -- sole unscheduled sector;
  M-P3 stays seam-first.
- Registry ready: `xiom.http` 0.1.1, `xiom.jwt` 0.2.0, `xiom.rate` 0.2.0,
  `xiom.metrics` 0.2.0, `xiom.router` 0.1.0, `xiom.http.middleware` 0.1.0,
  `xiom.session` 0.1.0, `xiom.static` 0.1.0, `xiom.kv` 0.1.0. Read
  `E:\xiom-projects\xiom-pulse\SESSION.md` + its relay docs before filing
  anything new (do not rediscover).

## 6. Relay rows (keep updated every wrap)

| Doc | For | State |
|---|---|---|
| `docs/COMPILER-FINDINGS-XVECTOR.md` | compiler | v0.64.3 re-test: C-13/C-14 **UNCHANGED** (both `acked` by the compiler lane 2026-10-10; verdicts filed; unfixed); v0.64.2-era: C-03/06/07/08 verified fixed; C-10 fixed; C-11/C-12 in-context green; C-09 repro green |
| `docs/RELAY-COMPILER.md` | compiler | Addenda 3-10 (8 = v0.64.2 re-test; 9 = XVC-C-13 `&Str` params; 10 = XVC-C-14 short-name layout shadow) |
| `docs/COMPILER-RELAY-2026-10-09-v0.64.2.md` | compiler -> XVECTOR | received; actioned (re-test done, no residual reds) |
| `docs/STDLIB-WISHLIST-XVECTOR.md` | stdlib | re-checked 2026-10-10 (lane `030f748`): fsync/fdatasync/fsync_dir + fd/append + f32-bits + truncate + flush_stdout still open; bounded-depth `json_parse` **FIXED** (wave 102 `5b7bf8f`) -- bus item -7 verified + closed |
| `docs/PACKAGE-WISHLIST-XVECTOR.md` | packages | refreshed 2026-10-10: `xiom.wal` + `xiom.metrics` + `xiom.rate` **ADOPTED**; router/http evaluated (status subset adopted); **`xiom.vectors` WIRED + GATED + SWAPPED** (60th; the package backs all vector consumers); `xiom.vectors` LIVE eco 508 / `xiom.ann` extracted (items `-9` fixed / `-10` acked / `-12` closed) |
| `docs/XIOM-HTTP-EVAL.md` | packages (record) | written 2026-10-10: router/http evaluation; status-helper adoption + 507 upstream gap |
| `docs/XIOM-VECTORS-EVAL.md` | packages (record) | written 2026-10-10: extraction fidelity (6/6 pins), wiring + gate, **atomic swap executed** (60th; §3) |
| `docs/XIOM-METRICS-ADOPTION.md` | packages/compiler (record) | written 2026-10-10: observability internals on `xiom.metrics` 0.2.0; XVC-C-14 record + gates |
| `docs/XIOM-RATE-ADOPTION.md` | packages/compiler (record) | written 2026-10-10: S3 token-bucket internals on `xiom.rate` 0.2.0 (carry-exact refill); gates + follow-ups |
| `docs/PULSE-INTEGRATION.md` | PULSE (consumer) | written 2026-10-09; PULSE builds `probe_pkg_xvector` from it |
| `docs/ORBITDB-INTEGRATION.md` | ORBITDB (hybrid pair) | written 2026-10-09 (mirrors their `XVECTOR-INTEGRATION.md`); hybrid probe next |
| `docs/RELAY-INTRO-XVECTOR.md` | ops + all | OPS parked until owner greenlight |
| `docs/PRODUCTION-READINESS.md` | owner | 81 %; recompute every wrap |
| **`xiom-relays` (bus)** | all lanes | onboarding ack `REL-20261010-1549-xvector`; migrated open items: compiler `-1550-xvector` + XVC-C-14 `REL-20261010-1709-xvector`, stdlib `-2..-8` (json `-7` verified + closed), packages `-9` fixed / `-10` acked (vectors LIVE + ann extracted), bindings `-11`, owner `-12`; orbitdb item `-1550-orbitdb-11` **closed** by orbitdb; compiler **v0.64.3 released** (`-1727-compiler`; release-check verdicts for C-13/C-14 filed); **shared-home wipe incident `REL-20261010-1835-xvector` (to ops, open)** + **pkg custom-`XIOM_HOME` bug `REL-20261010-1937-xvector` (to packages)** + **507 wishlist `REL-20261010-2002-xvector`**; shared-clone ops item `-1709-compiler` (helper `relay.py commit` now exists); 3-hour doorbell cron |
| (lane-local homes) | xvector only | `out\toolchain` + `out\xiom-home` (Win); `~/.xvector-toolchain` + `~/.xvector-home` (WSL) -- isolation from shared-home wipes (2026-10-10) |

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

Orientation: HEAD `c414e2a` (feat: xiom.vectors internals swap) + the
handoff commit; tag `v1.0.0-rc.1` on `530b041`; clean
tree; `git log --oneline -12` shows the recent slice commits. Lane pins:
stdlib `5468469` (fsync chain still stubs), packages `2b9b1146`
(xiom.ann extracted; xiom.vectors LIVE eco 508), compiler **v0.64.3
installed lane-local** (Windows `out\toolchain`, WSL
`~/.xvector-toolchain`; re-tests done; C-13/C-14 unchanged, verdicts
filed). **Toolchain + package homes are lane-local on purpose** (shared
homes get wiped by concurrent sessions -- incident
`REL-20261010-1835-xvector`); do not point builds at
`%LOCALAPPDATA%\xiom*` or `~/.local/share/xiom`.

Coordination bus (owner rollout 2026-10-10): the private `xiom-lang/
xiom-relays` repo is the only cross-lane channel. At session start and
before finishing any task: `git -C E:\xiom-lang\xiom-relays pull --ff-only`
then `python tools/relay.py view --lane xvector` from that repo; process
items addressed to xvector; never edit another lane's item (open a new
one); commits in the bus are pushed (it is the shared mailbox). A 3-hour
doorbell cron is armed for this session. The local bus clone is shared by
lane sessions on this machine: scope `git add` to your own item files,
re-pull before transition batches, expect interleaved commits (ops item
`REL-20261010-1709-compiler`).

Autonomous mode: arm a session goal with this objective (verbatim):
"Execute docs/PRODUCTION-PLAN.md for xiom-xvector autonomously, one
verified slice at a time, without further user prompting. Work the ordered
slice backlog: all plan slices are done and v1.0.0-rc.1 is prepared;
`xiom.wal` is adopted. Next, in order: `xiom.metrics` 0.2.0 adoption
(observability internals behind the same surface), `xiom.rate` 0.2.0
adoption (token-bucket internals), `xiom.router`/`xiom.http` helper
evaluation. Each pass re-checks the external lanes and pivots when a gate
clears (fsync -> D5/D6, net -> socket adapter, mmap -> P5, kv). Otherwise
maintenance (docs drift, dependency pins, repro re-runs).
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
`wsl.exe -d Ubuntu`); stdlib lane E:\xiom-lang\stdlib (lane HEAD d2b18dc =
release 0.64.3 registry-LIVE, waves 100-101; durability primitives still
stubs; /mnt/e/... in WSL); XIOM_RUNTIME_DIR
retired. Dot-source scripts\dev-env.ps1 (and .sh twin); scripts\build.ps1/.sh
build; scripts\run-suite.* runs the conformance suite; scripts\run-probe.*
runs probes. Green baseline: suite 171/171 x2 + sbom gate, 37 probes x2
+ bench smoke (quick) on BOTH platforms, all under the lane-local
toolchain + package home (compiler v0.64.3).

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
`probe_segment_file`, 38 checks); M-Q3 pagination (`query.pagination`
offset + after-id cursor over the (distance asc, id asc) total order;
exact tie order by id; gate `probe_pagination`, 22 checks); M-Q4
delete-by-filter (planner-driven index-candidate or scan delete,
per-point WAL + tombstones + payload/index cleanup; nothing matching ->
Ok(0); gate `probe_delete_filter`, 26 checks); M-Q5 index admin
(per-collection stats + `rebuild_index` with build/compact stats; parked
entries report without switching; gate `probe_index_admin`, 20 checks);
M-Q6 request extensions (SearchRequest mode knn/range + radius + offset/
after-id pagination; SearchBatchRequest + search_batch_with_request
ordered all-or-nothing; gate probe_search_request, 24 checks); M-G1
reference oracle (independent Float64 oracle vs the kernels + axioms +
all ranked/paged/cursor/range/Hnsw paths; deviations at Float32-ulp
scale, bit-identical Win/WSL; gate probe_reference_oracle, 22 checks);
M-S1 HTTP service skeleton (`api.http_service` byte-level HTTP/1.1
pipeline + router; strict parsing, qualified stdlib-JSON wire, honest
statuses; gate probe_http_service, 40 checks); M-S2 service
config/limits/errors (ServiceConfig + env/file loaders; enforced limits
413/400; {error,kind,status} over the full CoreError enum;
http_service_shutdown checkpoint; gate probe_service_limits, 27 checks);
M-S3 auth + rate limiting (API keys via x-api-key with constant-time
compare + scopes read/write/admin + XVECTOR_API_KEYS; token-bucket
RateLimiter with 429; ServiceState + http_service_handle_state; gate
probe_service_auth, 24 checks); M-S4 security pass (SECURITY.md; fuzz
gate 2500 inputs + targeted abuse with the JSON depth guard fixing a
found stack-overflow DoS; SBOM + unsafe gate scripts wired into both
batteries; gate probe_http_fuzz, 14 checks); M-O observability core (histograms +
counters + bounded JSON log ring; public /metrics with gauges + health
readiness; per-request instrumentation; OPERATIONS.md runbook; gate
probe_metrics, 23 checks); M-R release candidate v1.0.0-rc.1 (checklist
audit + repro re-runs + release notes + SBOM snapshot + owner handoff;
final batteries green at the tagged commit); xiom.wal first adoption
(registry install + trust pin + xiom.toml dependency; op-code alignment
gate `probe_package_wal`, 9 checks; D5 migration plan); relay-bus
onboarding (owner rollout; ack + all open items migrated; 3-hour
doorbell cron armed); XV-ORBITDB-01 fix (bus item from orbitdb: chained
persist/load of a recovered WAL reloaded EMPTY because wal_load required
first-LSN == 1; fixed in 3c36f34 -- any starting LSN >= 1, +1 steps
enforced; probe_wal_file +3 chained checks); xiom.metrics 0.2.0 adoption
(observability internals behind the same surface, /metrics byte-identical;
engine stat counters on the package; shim Counter retired after XVC-C-14;
new probe_package_metrics; repro docs/repro/xv-counter-type-shadow);
xiom.rate 0.2.0 adoption (token-bucket internals on the package behind
the same API; carry-exact refill; new probe_package_rate); compiler
v0.64.3 re-pin lane-local (re-tests done; C-13/C-14 unchanged,
release-check verdicts filed; shared-home wipe incident diagnosed + lane
isolated); xiom.http helper evaluation + adoption (status phrases on the
package behind a lane adapter; router/parser not adopted; new
probe_package_http + the 507 wire pin); xiom.vectors 0.1.0 wiring +
fidelity gate (byte-exact carve 6/6 pins verified; new
probe_package_vectors) + **internals swap EXECUTED (atomic; local
modules deleted; codec extracted; batteries green both platforms)** --
37 probes + sbom, suite 171).
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

NEXT TASK: the **`xiom.ann` porter wiring** once the package is
published (registry 404 as of 2026-10-10; watch the packages lane's
scope item `REL-20261010-1908-packages`; the wiring follows the vectors
pattern: dependency + extraction-fidelity gate + atomic swap), the
replay-loop delegation at the D-ledger store migration, then the
owner's public release + benchmark (the v1.0.0-rc.1 candidate and owner
handoff stand). Each pass: re-check
the external lanes and pivot when a gate clears (D5/D6 on the stdlib
fsync chain, socket adapter on xiom.net, P5 on stdlib mmap, xiom.kv on
C-PULSE-10). Non-gated work proceeds while the stdlib
fsync chain stays pending (v0.64.3-era: still stubs). When the M-R release
criteria are met, TELL THE OWNER (public release + benchmark setup is the
owner's action, PULSE-style). C-01/C-02/C-04 unwinds are optional
deliberate API decisions, no longer compiler-blocked.
Keep the wrap discipline: full batteries (scripts/ci.ps1 + ci.sh, suite x2
+ sbom + 37 probes x2 + bench smoke), signed commits, docs updated.
Never build against the shared toolchain homes (lane-local pins only).

Discipline: struct literals list every field; locals initialized; `Str`
params by value (XVC-C-13); numeric gates per build; watchdogs + exit
codes; check free memory before trusting a red build; suite x2 green before
any wrap; WSL spot every wrap; update
SESSION.md STATE + relay rows + docs/PRODUCTION-READINESS.md at every wrap;
commit signed at every step.
```
