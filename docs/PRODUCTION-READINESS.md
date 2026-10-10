<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVECTOR -- Production-Readiness Tracker

**How far is xiom-xvector from a production-grade vector database?**
This is the honest, evidence-based scorecard. It is recomputed at every lane
wrap and every number must point at evidence (tests, probes, docs) or name
the missing work. **Programme:** `docs/PRODUCTION-PLAN.md` (v1.0 milestones
M-G/M-D/M-Q/M-S/M-O/M-P/M-R + slice backlog) and
`docs/requirements/production-v1.md`.

- **As of:** 2026-10-09 (v1.0.0-rc.1 candidate)
- **Overall:** **80 %** (weighted; see method)
- **Level scale:** 0 none - 25 scaffold - 50 buildable - 75 hardened core -
  90 release-grade - 100 production.

## Method

Ten phases, weights sum to 100. Phase score = verified criteria / criteria
(judgment, itemised as "remaining" below). Overall = sum(weight x score).
A phase reaches 100 only when its exit criteria are met **with evidence**
(green suites x2 on Windows + WSL, probes, soak where applicable) -- not when
the code merely exists. Blockers are named; blocked work still scores.

| # | Phase | Weight | Score | Level | Blockers |
|---|-------|-------:|------:|-------|----------|
| A | Core data model & vector math | 8 | 95 | release-grade | none (fuzz/reference cross-check tracked in I) |
| B | Exact search & query engine | 10 | 97 | release-grade | ANN-widened range (M-P) |
| C | ANN index (HNSW hardening) | 14 | 98 | release-grade | file-backed persistence |
| D | Persistence & durability | 20 | 73 | buildable | stdlib fsync/append gap, delta log, multi-segment read path, file-level kill test, retention |
| E | Metadata & filtering | 8 | 100 | production | -- |
| F | API & query surface | 8 | 89 | buildable | version endpoint |
| G | Concurrency & scalability | 10 | 25 | buildable | concurrent readers, write serialization, segment growth, memory budget |
| H | Observability & operability | 5 | 70 | buildable | xiom.metrics adoption (Phase 10), dashboards/alert wiring |
| I | Testing & verification | 9 | 94 | release-grade | CI runners |
| J | Ecosystem & release engineering | 8 | 56 | buildable | runners activation, rulesets, staging E2E, porter extraction |

**Overall today:** 0.08x95 + 0.10x97 + 0.14x98 + 0.20x73 + 0.08x100 +
0.08x89 + 0.10x25 + 0.05x70 + 0.09x94 + 0.08x56 = **79.68 -> 80 %**.

## What 100 % means (definition of production grade)

1. No acknowledged write can be lost (fsync'd WAL + replay + durable manifest,
   verified by kill-recovery tests).
2. Every query path is self-verifying per build (the XVC-C-05/06 class means a
   binary is only trusted after its numeric assertions pass).
3. HNSW recall is measured against the exact oracle at target recall/latency.
4. Filtered search is planned (pre/post by selectivity) and correct under
   concurrency.
5. Operable: metrics/health, structured logs, documented failure modes,
   upgrade/migration story.
6. Released: CI matrix green, reproducible artifacts with build-info, branch/tag
   protection, SHA-pinned actions, staging E2E -- owner-greenlit.
7. Docs match code (this file, ROADMAP, SPEC, ARCHITECTURE, SESSION) and the
   relay docs are current.

## Phase detail -- remaining work per phase

### A. Core data model & vector math -- 95 %
Done: Vector/VectorIndex types, 3 distance metrics, magnitude/normalize,
top-K bounded heap, exact f32<->bits codec, 168-check suite.
Remaining: reference cross-check (numpy-style oracle) under fuzz; NaN/Inf
documented policy in distance kernels.

### B. Exact search & query engine -- 97 %
Done: flat exact KNN, k-bounded sorted results, filtered exact search
(pre-filter scan + selectivity-based post plan with fallback), **filtered
search on ANN collections** (HNSW fetch + matching subset with exact flat
fallback when under-filled; k-fill guarantee kept), **exact range search**
(kernel `search_range_scan` + `engine_search_range` + facade
`search_range`: inclusive radius, distance-sorted, limit-bounded, exact on
both index kinds; gate `probe_range_search` -- 72 radius x limit combos vs a
brute-force scan), SearchHits public shape, error paths.
Remaining: ANN-widened range (M-P tuning).

### C. ANN index -- 98 %
Done: multi-layer HNSW graph (`index/hnsw.xi`: flat per-(node, layer)
adjacency rows, deterministic geometric levels, greedy descent + layer-0
beam honouring `ef`, metric-agnostic, user-id results; **O(log n) sorted
id -> position map** with duplicate rejection), tombstone deletes (never
returned, routers kept, revive on re-insert), tombstone compaction
(`hnsw_compact` rebuilds from live nodes; engine `compact_index`), **engine
wiring** (`VectorEngine.graph/index_kind/ann`, `set_index` Flat/Hnsw,
upsert/delete upkeep, `engine_search` routing with `ef = ann.ef_search`,
filtered search stays exact, recover + re-apply), **strict word codec**
(`hnsw_encode`/`hnsw_decode` v2, map rebuilt on decode), **beam
construction honouring `ef_construction`** with diversified pruning,
recall harness vs the flat oracle (n=200: 300/300 at ef=64, 296/300 at
ef=8; n=800: 200/200; after-delete 300/300; compacted 200/200; engine-level
recall 200/200 incl. ef_construction=32; gates `probe_hnsw_recall`,
`probe_engine_hnsw`, `probe_hnsw_codec`), AnnParams validation.
Remaining: file-backed graph segments (stdlib I/O pending). Latency proxies
(build work + per-ef visited/recall table) are in the harness; updates
re-link edges for the new vector (recall 200/200 after 60 in-place
updates); the WSL segfault found while wiring the map (XVC-C-09) is worked
around and pinned as a repro for the compiler lane.

### D. Persistence & durability -- 73 %
Done: WAL-before-ack for upserts AND metadata, vector + payload codecs,
replay, delete/torn-tail handling, compacted checkpoint, chained reopen,
LSN monotonicity, **in-WAL collection manifest** (dim/metric/index
kind/params survive recover and checkpoints; malformed/legacy fall back),
**kill-recovery acceptance** (prefix exactness at the WAL model level:
recover(prefix) + apply(record) == recover(prefix + record), incl. the
compacted checkpoint log, empty log and corrupt-final-record cases),
**whole-file WAL persistence** (`durability.wal_file`: `wal_persist` text
checkpoint + `wal_load` byte-level torn-tail-safe prefix load; kill/reopen
equality, overwrite persistence, 9-point truncation sweep, missing/
garbage/empty cases; gate `probe_wal_file`), **atomic checkpoint swap**
(M-D1: `<path>.tmp` -> `io.rename`; 7 fault-injection checks -- no temp
remains, staged-complete and partial temps leave the previous checkpoint
intact, completed persist advances the file), the **durable collection
registry file** (M-D2: `durability.manifest_file` -- `xvector-manifest 1`
text registry, one line per collection `name dim mc kc m efc efs`;
whole-file persist with atomic temp+rename; invalid entries refused with
the target untouched; torn-tail-safe byte-level load with a
complete-entry prefix; gate `probe_manifest_file`, 38 checks), the
**multi-collection registry** (M-D3: named collections with per-
collection stores/payloads/indexes; WAL v2 config + v3 drop records with
cid-stamped data; routed recovery + whole-registry checkpoint; whole-
registry `save_manifest`/`open_engine` with file-wins by name; gate
`probe_collections`, 41 checks), and **sealed segment files** (M-D4:
`segment.segment_file` -- vectors + payloads + Hnsw graph codec;
whole-file atomic persist; torn-tail-safe complete-record prefix load;
lifecycle Mutable -> Sealing -> Sealed; engine `seal_segment`/
`restore_segment` with cid/dim/metric validation and WAL re-checkpoint
via shared `engine_checkpoint_from`; gate `probe_segment_file`,
38 checks).
Remaining (in order): stdlib fsync/fd-write/append-bytes (blocker doc:
`docs/STDLIB-WISHLIST-XVECTOR.md`), delta append log, multi-segment
collection read path, file-level crash-kill test, WAL
retention/pruning policy.

### E. Metadata & filtering -- 100 %
Done: typed Eq/Range/In/Exists + combinators + no-payload semantics, engine
integration, durable metadata, filtered probe, sorted key index
(parallel-vector rows; exists/count/Eq/Range with semantic float compare;
gate `probe_payload_index`), selectivity planner (exact counts for
Eq/Range/Exists; pre/post choice + fallback; gate `probe_filter_plan`),
compound upper bounds (And/Or/Not planning), the index-driven candidate
plan, and **multi-key intersections** (And of indexable clauses).
Remaining: none (composite `In` intersections are a possible future
stretch).

### F. API & query surface -- 73 %
Done: facade (create/upsert/search/delete/get + payloads + filtered search +
exact range), batch ops (`upsert_many`/`delete_many`/`search_many`,
all-or-nothing validation; gate `probe_batch_ops`), Result[..] error
discipline, SearchHits/BatchHits shapes documented, SearchRequest wire
(real types) driving `search_with_request`, `with_payload` hydration
(`HydratedHits`/`SearchHit`; C-08 fixed in v0.64.2, suite flags asserted),
and the multi-collection registry surface (M-D3: `create_named_collection`/
`select_collection`/`drop_collection`/`list_collections`/
`collection_count` + whole-registry `save_manifest`; gate
`probe_collections`), and pagination (M-Q3: `search_page` offset +
`search_after` after-id cursor over the (distance asc, id asc) total
order; gate `probe_pagination`), and selective delete-by-filter (M-Q4:
`delete_filter` -- planner-driven index candidates or scan, WAL-durable
per point, tombstones + payload/index cleanup; gate
`probe_delete_filter`), and per-collection stats + the admin rebuild
(M-Q5: `collection_stats` / `rebuild_index`; gate `probe_index_admin`),
and the request surface extensions (M-Q6: `SearchRequest` mode
knn/range, radius, offset/after-id pagination; `SearchBatchRequest` +
`search_batch_with_request`; gate `probe_search_request`, 24 checks).
Remaining: version endpoint for the future service.

### G. Concurrency & scalability -- 25 %
Done: multi-collection registry (M-D3: named collections with per-
collection stores/payloads/index configs, create/select/drop/list, routed
recovery + whole-registry manifest; gate `probe_collections`) and the
benchmark harness + baseline (`docs/BENCHMARKS.md`; bench smoke in both
batteries). The engine is still single-threaded and each call targets one
active collection.
Remaining: concurrent readers, write serialization model, segment growth /
compaction policy, memory budget, scale tuning beyond the baseline.

### H. Observability & operability -- 70 %
Done: inline counters + LSN metrics (engine), and the full M-O core:
`observability.metrics` (fixed-bucket latency histograms with
`_sum`/`_count`/p50/p95/p99; the service counter bundle; a bounded,
sanitized JSON log ring with slow-query flag), the public prometheus-style
`GET /metrics` (counters + histograms + live gauges
collections/points_active/lsn), `/health` readiness, per-request
instrumentation through `http_service_handle_state`, and
`docs/OPERATIONS.md` (runbook + failure domains + backup drill). Gate
`probe_metrics` (23 checks).
Remaining: `xiom.metrics` adoption (Phase 10), dashboards/alert wiring in
the deployment, recall-proxy metrics on demand.

### I. Testing & verification -- 94 %
Done: 171-check conformance suite (x2 Windows + WSL), 31 probes, build-time
watchdog, rebuild-on-red discipline, per-build numeric gates, per-build
compiler-workaround pins (XVC-C-04 shape matrix, C-01 bind semantics), a
deterministic fuzz gate (`probe_fuzz_codecs`), a mixed-workload soak
(`probe_soak_mixed`), the kill-recovery acceptance
(`probe_kill_recovery`), the file-WAL gate
(`probe_wal_file`: roundtrip, kill/reopen, truncation sweep, atomic swap,
**1200-record scale guard**), the **benchmark harness + baseline**
(`docs/BENCHMARKS.md`; bench smoke wired into both CI batteries), the
**reference-oracle cross-check** (`probe_reference_oracle`: independent
Float64 oracle vs the kernels + axioms + all ranked/paged/cursor/range/
Hnsw search paths; deviations at Float32-ulp scale, bit-identical
Windows/WSL), the **HTTP service gate** (`probe_http_service`: framing,
routing, wire shapes, honest statuses), the **HTTP fuzz + abuse gate**
(`probe_http_fuzz`: 2500 deterministic inputs all well-formed; targeted
resource-exhaustion cases), and
the **v0.64.2 re-test**: all XVECTOR compiler findings verified fixed
(C-03/06/07/08 + C-10; C-11/C-12 in-context; C-09 repro) with the C-07/C-08
workarounds reverted; the suite asserts trailing-field flags again.
Remaining: CI runner activation.

### J. Ecosystem & release engineering -- 56 %
Done: `.ps1`/`.sh` twins, `xiom.toml`, relay docs + wishlists, porter plan,
version/hash recording, the acyclic porter-ready tree, **release-prep
drafts**: `scripts/ci.ps1` + `scripts/ci.sh` (full pre-release battery with
aggregated exit codes, both verified green), `VERSION` (0.1.0-dev), a
SHA-pinned `.github/workflows/ci.yml` draft,
`docs/RELEASE-CHECKLIST.md` (owner-gated flow), and the **security release
artifacts**: `docs/SECURITY.md` (threat model + secure defaults) and the
**SBOM + unsafe gate** (`scripts/sbom.ps1`/`sbom.sh` -> `out/sbom.json`;
wired into both batteries), the **operations runbook**
(`docs/OPERATIONS.md`: start/stop, config, monitoring/alerts,
backup/restore drill, failure domains, migration, diagnostics), and the
**release candidate package** (`docs/RELEASE-NOTES-v1.0.0-rc.1.md`,
`docs/sbom-v1.0.0-rc.1.json`, `docs/OWNER-HANDOFF.md`, an audited
`docs/RELEASE-CHECKLIST.md`, annotated tag `v1.0.0-rc.1`).
Remaining: self-hosted runners activation, branch rulesets on greenlight,
staging E2E (parked until the owner greenlights public release), porter
extraction with the packages lane.

## Milestones

| Milestone | Meaning | Status |
|---|---|---|
| M1 Durable in-memory core | WAL + recovery + payloads, green suites + probes | **Met 2026-10-08** |
| M2 Crash-safe on disk | file-backed WAL segments, fsync, durable manifest, kill tests | In progress: whole-file WAL checkpoint + atomic swap (M-D1); durable registry file (M-D2); multi-collection routed recovery + whole-registry manifest (M-D3); sealed segment files with engine seal/restore (M-D4); fsync/append delta, multi-segment reads, file-level kill test, retention blocked on stdlib fsync/append |
| M3 Indexed at scale | HNSW hardening + recall harness, sorted payload index + planner, concurrency | In progress: HNSW hardening (recall harness, tombstones, compaction, codec) + payload index + planner + multi-collection registry + benchmark harness landed; concurrency/serialization and scale tuning pending |
| M4 Operable & released | observability, soak/fuzz green, CI + release stamp, staging E2E | Not started (release gate is owner's) |

## Change log

- **2026-10-08:** created. Phase 3 payload filtering (90 %) and payload
  durability landed (D raised to 55, E to 90, I to 65); suite 126 -> 165
  checks; XVC-C-05/06/07 build-rejection discipline adopted. Overall ~42
  (recomputed bootstrap baseline: scaffold-phase engine) -> 53 %.
- **2026-10-08 (later):** first module extracted (payload/filter layer,
  `src/payload/*`; engine imports it) -- J 20 -> 25, porter prep advanced;
  suite 165/165 x2 and all probes green after extraction.
- **2026-10-08 (fourth pass):** second extraction wave -- types
  (dense_vector/metric/neighbor), storage/vector_store (+ vector codec),
  query/search_service are real modules; engine.xi keeps WAL/recovery/
  engine/API only. J 25 -> 30; suite 165/165 + all probes green.
- **2026-10-08 (fifth pass):** third extraction wave -- durability
  (wal/recovery/write_ahead_events) extracted; engine.xi is now
  facade + engine orchestration only. J 30 -> 35; suite 165/165 x2
  (Win+WSL) and Windows probes x2 green.
- **2026-10-08 (sixth pass):** compiler re-pinned to **v0.64.1**; six of
  seven XVECTOR findings fixed (XVC-C-01..06), C-07 open. Regression
  green: suite 165/165 x2 (Win+WSL), 5 probes x2, WSL matrix 9/9.
  I 65 -> 70 (numeric gates now stable across builds).
- **2026-10-08 (seventh pass):** FloatVal workaround unwound -- float
  payload gates restored in suite (166 checks) + probes. I 70 -> 72;
  overall 54 %.
- **2026-10-08 (handoff):** re-verified full green on compiler v0.64.1 +
  stdlib **0.64.2** (`4dd8844`): suite 166/166 x2 (Win+WSL), probes green;
  fsync/fd-write still stubbed on 0.64.2 (M2 unchanged). No score change.
- **2026-10-08 (eighth pass):** final extraction wave -- `src/core/shim.xi`
  (CoreError/Counter/ids/predicates) + `src/engine/core.xi` (VectorEngine +
  engine_*); `engine.xi` is the facade only (acyclic: shim <- core <-
  facade). Consumers import `xiom.vector.engine.core` for engine_* symbols.
  J 35 -> 40; overall 55 %. Evidence: engine-import probe x2; suite 166/166
  x2 (Win+WSL); all 7 probes x2 (Win); WSL spot (import + vector_store)
  bit-identical.
- **2026-10-08 (ninth pass):** Phase 3 refinement -- `SearchRequest` rewritten
  against the real types (with setter), `HydratedHits`/`SearchHit` +
  `hydrate_hits`, `engine_search_request` (metric validation, filtered/plain
  dispatch, optional hydration), facade `search_with_request`; new probe
  `probe_search_request` and 3 suite mirrors (168 checks). New compiler
  finding **XVC-C-08** (trailing scalar after a Vec-bearing field misreads;
  silent wrong hydration flags) filed with repro
  `docs/repro/xv-trailing-field-vec/`; hydration flags gated in the
  real-module probe only (green 8/8 fresh builds). F 60 -> 70; overall 56 %.
  Evidence: suite 168/168 x2 (Win+WSL), all 8 probes x2 (Win) + WSL spot.
- **2026-10-08 (tenth pass):** Phase 3 refinement -- sorted payload key index
  (rows sorted by field/kind/num/text/id in parallel vectors; maintained on
  put/overwrite/remove; `payload_store_index_len/_exists/_field_count/_eq/
  _range`; new probe `probe_payload_index`, 31 checks, stress 6/6 fresh
  builds). E 90 -> 95; overall 55.98 -> 56 %. Evidence: suite 168/168 x2
  (Win+WSL), all 9 probes x2 (Win) + WSL spot. Stdlib re-check: fd/fsync/
  append-bytes still stubs (M2 stays parked).
- **2026-10-08 (eleventh pass):** Phase 3 refinement -- selectivity-based
  pre/post-filter planner (`query/filter_plan.xi`: exact counts for
  Eq/Range/Exists incl. allocation-free `index_count_eq/_range`; post only
  for known count >= k and majority; post path with scan fallback inside
  `search_knn_filtered`; new probe `probe_filter_plan`, 16 checks incl.
  equivalence vs a scan reference + fallback case, stress 6/6 fresh builds).
  B 90 -> 92, E 95 -> 97; overall 56.34 -> 56 %. Evidence: suite 168/168 x2
  (Win+WSL), all 10 probes x2 (Win) + WSL spot.
- **2026-10-08 (twelfth pass):** Phase 4 start -- HNSW stub replaced by a
  working layer-0 graph (`index/hnsw.xi`: flat parallel arrays dodging the
  AUDIT T001 shape; exact-kNN bidirectional build with farthest-edge
  pruning; best-first beam honouring `ef`; metric-agnostic; user-id
  results) + recall harness vs the flat oracle (new probe
  `probe_hnsw_recall`: recall@10 300/300 at ef=64, 299/300 at ef=8, cosine
  100/100, reachability 200/200, stress 6/6 fresh builds; gates >= 0.85 /
  0.50 / 0.60). C 25 -> 45; overall 56.34 -> 59 %. Evidence: suite 168/168
  x2 (Win+WSL), all 11 probes x2 (Win) + WSL spot (recall bit-identical).
- **2026-10-08 (thirteenth pass):** Phase 4 -- multi-layer HNSW (fixed
  8-layer capacity, per-(node, layer) flat adjacency rows, deterministic
  geometric level assignment honouring `ml`, greedy descent above layer 0 +
  layer-0 beam; the level-assignment LCG low-bit bug found by the harness
  and fixed with high-bit testing). Harness extended: level histogram, top
  level, avg_visited, and an n=800 dataset (recall@10 200/200 at ef=64,
  avg visited 288/800; n=200 300/300 at ef=64 AND ef=8; cosine 100/100;
  stress 6/6 fresh builds). C 45 -> 55; overall 60.54 -> 61 %. Evidence:
  suite 168/168 x2 (Win+WSL), all 11 probes x2 (Win) + WSL spot.
- **2026-10-08 (fourteenth pass):** Phase 4 -- HNSW tombstone deletes
  (`hnsw_delete` marks routers that are never returned; idempotent;
  `hnsw_live_count`; re-insert updates the vector in place and revives) --
  the prerequisite for engine wiring. Harness extended: after-delete recall
  300/300 stray42=0, revive -> live 200, delete-all -> live 0 and empty
  search; stress 6/6 fresh builds. C 55 -> 62; overall 61.52 -> 62 %.
  Evidence: suite 168/168 x2 (Win+WSL), all 11 probes x2 (Win) + WSL spot.
- **2026-10-08 (fifteenth pass):** Phase 4 -- engine HNSW wiring
  (`VectorEngine.graph/index_kind/ann`; `set_index` Flat/Hnsw with graph
  rebuild from the store; upsert feeds `hnsw_insert_ref`; delete tombstones
  the graph; `engine_search`/request plain path route through `hnsw_search`
  with `ef = ann.ef_search`; filtered search stays the exact flat scan;
  index choice in-memory, re-applied after `engine_recover`). New gate
  `probe_engine_hnsw` (13 checks: engine recall 200/200, delete/revive,
  filtered exact, Flat bit-identical, invalid params, recover + re-apply;
  stress 6/6 fresh builds). C 62 -> 75; overall 61.52 -> 63 %. Evidence:
  suite 168/168 x2 (Win+WSL), all 12 probes x2 (Win) + WSL spot.
- **2026-10-08 (sixteenth pass):** Phase 4 -- HNSW tombstone compaction
  (`hnsw_compact` rebuilds the graph from live nodes only; engine
  `compact_index` returns the reclaimed count, Flat -> 0). Harness:
  compact-all -> empty; 50 tombstones -> size/live 150 with recall 200/200
  and stray_deleted=0; engine-level reclaim + post-compact recall;
  recover expectations updated (store 149). Both gates stress 6/6 fresh
  builds. C 75 -> 80; overall 63.34 -> 64 %. Evidence: suite 168/168 x2
  (Win+WSL), all 12 probes x2 (Win) + WSL spot.
- **2026-10-08 (seventeenth pass):** Phase 4 -- HNSW graph codec
  (`hnsw_encode`/`hnsw_decode`: deterministic word stream, strict decode;
  new gate `probe_hnsw_codec`: 100-node structural roundtrip with search
  bit-identical, tombstones, empty graph, six rejection cases, decoded
  graph mutable; stress 6/6 fresh builds). C 80 -> 85; overall 64.04 ->
  65 %. Evidence: suite 168/168 x2 (Win+WSL), all 13 probes x2 (Win) + WSL
  spot.
- **2026-10-08 (eighteenth pass):** Phase 4 -- beam construction honouring
  `ef_construction` (descent + per-layer beam `search_layer_build`) and
  diversified pruning (`select_diverse` for new-node selection and full-block
  pruning); `ef_construction` on the graph (setter; AnnParams-seeded by
  `set_index`), codec v2 carries it. Harness re-verified under beam build
  (n=200 300/300 ef=64, 296/300 ef=8; n=800 200/200; deletes/compaction
  hold; engine ef_construction=32 build recall holds); three HNSW probes
  stress 6/6 each. C 85 -> 90; overall 64.74 -> 65 %. Evidence: suite
  168/168 x2 (Win+WSL), all 13 probes x2 (Win) + WSL spot.
- **2026-10-08 (nineteenth pass):** Phase 4 -- HNSW sorted id -> position
  map (`id_keys`/`id_vals`, O(log n) find, duplicates rejected, codec
  rebuilds it, compaction rebuilds it). Found **XVC-C-09** while wiring it:
  the compiled `engine_set_index` segfaulted on WSL while Windows stayed
  green; worked around (local graph + single field assign), repro pinned at
  `bca8b7f` (`docs/repro/xv-wsl-nested-field/`). C 90 -> 95; overall 65.44
  -> 66 %. Evidence: suite 168/168 x2 (Win+WSL), all 13 probes x2 (Win) +
  WSL spot (engine/recall/codec probes green post-workaround); three HNSW
  probes stress 6/6 each.
- **2026-10-08 (twentieth pass):** slice 5 -- compiler-workaround pins and
  unwind-candidate evaluation: new per-build pin `probe_result_shapes.xi`
  gates the whole XVC-C-04 matrix (incl. the real engine path) on every
  build (8/8 Windows + 2/2 WSL fresh builds); `probe_bind_semantics` pins
  C-01 (8/8 + 2/2). Decision: keep the SearchHits wrapper and the suite's
  direct dispatch (C-08/C-09 family still open; revisit at the next
  archive). I 72 -> 75; overall 66.14 -> 66 %. Evidence: suite 168/168 x2
  (Win+WSL), all 14 probes x2 (Win) + WSL spot.
- **2026-10-08 (twenty-first pass):** HNSW+filter integration --
  `hnsw_search_filtered` (ANN fetch `ef_search` wide + matching subset;
  exact flat filtered fallback when under-filled) behind
  `engine_search_filtered` and the request-driven filtered branch. Gate:
  majority filter k-filled 8/8 with recall 80/80 vs the exact oracle;
  1-/3-match filters fall back bit-identically; zero-match empty; stress
  6/6. B 92 -> 95; overall 66.41 -> 67 %. Evidence: suite 168/168 x2
  (Win+WSL), all 14 probes x2 (Win) + WSL spot.
- **2026-10-08 (twenty-second pass):** fuzz gate + decoder hardening --
  `probe_fuzz_codecs.xi` (deterministic random/mutated/truncated streams
  into payload codec, graph codec and WAL replay incl. chained
  checkpoint). It found **XVC-C-10**: `hnsw_decode`'s inline pad loop
  segfaulted at `m >= 512` (Win + WSL); fixed via `pad_adj_slots` + strict
  bounds (`m <= 512`, `count <= words.len()`), repro pinned at `e0b1f7f`
  (`docs/repro/xv-decode-pad-loop/`). I 72 -> 78; overall 66.71 -> 67 %.
  Evidence: suite 168/168 x2 (Win+WSL), all 15 probes x2 (Win) + WSL spot
  (fuzz/codec/pad-loop).
- **2026-10-08 (twenty-third pass):** mixed-workload soak --
  `probe_soak_mixed.xi` (400-point Hnsw collection, 600 deterministic ops:
  311 upserts / 115 searches / 63 filtered / 61 payload sets / 50 deletes;
  per-op bookkeeping invariants, periodic compaction, final + chained
  recovery; ~2.5s; stress 4/4). Found and fixed an LCG low-bit degeneracy
  in the generator (residue 8 unreachable -> the payload branch never ran).
  I 78 -> 80; overall 66.98 -> 67 %. Evidence: suite 168/168 x2 (Win+WSL),
  all 16 probes x2 (Win) + WSL spot (soak/fuzz).
- **2026-10-08 (twenty-fourth pass):** latency metrics + release-prep
  drafts -- `hnsw_build_ops` build-work proxy (n=200: 62,129 ops) and a
  per-ef visited/recall table (ef=8: 97/100 @ 63 visited; ef=128: 100/100
  @ 196); `scripts/ci.ps1` + `scripts/ci.sh` pre-release batteries (both
  green end-to-end), `VERSION` 0.1.0-dev, SHA-pinned CI workflow draft,
  release checklist. C 95 -> 97, J 40 -> 48; overall 67.16 -> 68 %.
  Evidence: full batteries via the new scripts (suite x2 + 16 probes x2 on
  Windows and WSL).
- **2026-10-08 (fix pass):** `index_add` now updates an existing id in
  place -- previously an upsert of an existing id kept the OLD vector in
  the flat store while the HNSW graph updated, so compaction reverted
  updates and recovery kept the first insert. Regression gate in
  `probe_vector_store` (new-vector bits visible via get_point + search,
  recovery keeps the latest). No score change; both full batteries green
  (suite x2 + 16 probes x2, Windows + WSL).
- **2026-10-08 (twenty-fifth pass):** E stretch -- store id -> slot map
  (O(log n) get/add/remove; swap-remove updates the moved slot), compound
  upper-bound planning (And/Or/Not), and the index-driven candidate plan
  (exact Eq/Range/Exists candidates through the map). Planner probe
  extended to 20 checks (plan codes, bounds, bit-identical index
  equivalence). E 97 -> 99; overall 68.08 -> 68 %. Evidence: full
  batteries via ci.ps1 / ci.sh (suite x2 + 16 probes x2, Windows + WSL),
  ALL GATES GREEN.
- **2026-10-09 (twenty-sixth pass):** in-WAL collection manifest --
  create_collection/set_index log dim/metric/index kind/AnnParams;
  engine_recover restores the full config (including rebuilding the Hnsw
  graph) without a manual set_index, checkpoints carry the manifest
  forward, and legacy/malformed logs keep the Flat fallback. Gate:
  `probe_engine_hnsw` (recover-without-set_index, chained config, legacy +
  malformed fallbacks). D 55 -> 58; overall 68.24 -> 69 %. Evidence: full
  batteries via ci.ps1 / ci.sh (suite x2 + 16 probes x2, Windows + WSL),
  ALL GATES GREEN.
- **2026-10-09 (twenty-seventh pass):** HNSW update re-linking --
  re-inserting an existing id refreshes the node's edges for the new vector
  (per-layer beam through the old structure + diversified replacement);
  connect factored into beam_select/apply_layer_edges (construction
  behavior-identical). Gate: recall@10 200/200 after 60 in-place updates vs
  the   flat oracle; size/live unchanged. C 97 -> 98; overall 68.84 -> 69 %.
  Evidence: full batteries via ci.ps1 / ci.sh, ALL GATES GREEN.
- **2026-10-09 (twenty-eighth pass):** kill-recovery acceptance --
  `probe_kill_recovery.xi` proves prefix exactness at the WAL model level
  (every prefix of a 46-record log; recover(prefix) + apply(record) ==
  recover(prefix + record)), on the compacted checkpoint log (28 records),
  plus full-recovery equality, empty log, and corrupt-final-record cases.
  Both batteries now run 17 probes. D 58 -> 60, I 80 -> 82; overall
  68.98 -> 70 %. Evidence: full batteries via ci.ps1 / ci.sh (suite x2 +
  17 probes x2, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (twenty-ninth pass):** multi-key intersections -- the index
  plan serves And of indexable clauses via per-clause candidate
  intersection; answerable compounds route to the index when the upper
  bound is selective or < k. Planner probe now 23 checks. E 99 -> 100
  (phase complete); overall 69.56 -> 70 %. Evidence: full batteries via
  ci.ps1 / ci.sh, ALL GATES GREEN.
- **2026-10-09 (thirtieth pass):** file-backed WAL -- new
  `durability.wal_file` (`wal_persist` whole-file text checkpoint +
  `wal_load` byte-level torn-tail-safe prefix load) on the stdlib
  whole-file APIs; probe `probe_wal_file` (roundtrip vs the live WAL,
  kill/reopen incl. Hnsw config, overwrite persistence, 9-point
  truncation sweep with per-cut prefix checks, record-boundary cuts,
  missing/garbage/empty). Both batteries now 18 probes. Found **XVC-C-11**
  (`io.read_file` content lost in some units) and **XVC-C-12**
  (`io.read_file_bytes` aborts at <= 8 bytes); workarounds: byte-wise
  parsing (never Str) + `file_size < 25` guard; repro
  `docs/repro/xv-stdlib-file-read-defects/`. D 60 -> 63, I 82 -> 83;
  overall 69.64 -> 70 %. Evidence: full batteries via ci.ps1 / ci.sh
  (suite 168/168 x2 + 18 probes x2, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (thirty-first pass):** v0.64.2 re-test + workaround reverts
  -- compiler v0.64.2 (tag `c51170a6`) installed Windows + WSL; every repro
  bundle re-run and the full batteries green. **C-03** (suite W004 count 0)
  and **C-06** (pinned FloatVal probe) stay fixed; **C-07 FIXED** --
  `Str::from_utf8(&Vec[UInt8])` valid again, payload codec + suite mirror
  reverted to the `&` spelling; **C-08 FIXED** -- trailing-scalar repro
  exit 0, all 14 variants green, suite hydration mirror restored and
  asserting the trailing flags (168 -> 169 checks); **C-10 FIXED** (inline
  pad shape no longer segfaults; hygiene kept); **C-11/C-12 re-tested
  green in a copy of the original failing unit** (defense in depth kept);
  **C-09 repro green on WSL + Windows** (pattern kept; weaker re-test).
  I 83 -> 84; overall 70.33 -> 70 %. Evidence: suite 169/169 x2 + 18 probes
  x2, Windows + WSL, ALL GATES GREEN.
- **2026-10-09 (thirty-fourth pass):** M-D1 atomic WAL checkpoint --
  `wal_persist` writes `<path>.tmp` and swaps via `io.rename` (platform
  replace semantics on Windows + WSL); `probe_wal_file` +7 fault-injection
  checks (no temp left behind; staged-complete temp and partial temp both
  leave the previous checkpoint intact; completed persist advances the
  file). D 63 -> 65; overall 70.42 -> 70.82 -> 71 %. Evidence: full
  batteries (suite 169/169 x2 + 18 probes x2, Windows + WSL), ALL GATES
  GREEN.
- **2026-10-09 (thirty-sixth pass):** M-Q1 exact range search --
  `search_range_scan` kernel + `engine_search_range` + facade
  `search_range`: every point within `radius` (inclusive), distance-sorted
  ascending, bounded by `limit`; exact on both index kinds (ANN widening is
  M-P tuning); dim mismatch / limit 0 / negative radius rejected. Probe
  `probe_range_search` (72 radius x limit combos vs a local brute-force
  scan, inclusive-boundary, radius-0, KNN-equivalence, Hnsw routing, reopen
  checks); suite mirror test added (169 -> 170). B 95 -> 97; overall
  70.82 -> 71.02 -> 71 %. Evidence: full batteries (suite 170/170 x2 + 19
  probes x2, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (thirty-seventh pass):** M-Q2 batch ops -- `upsert_many` /
  `delete_many` / `search_many` + `BatchHits`: all-or-nothing validation
  per call (bad dimension/length/empty leaves the engine untouched), delete
  counts actual removals (missing ids skipped), search returns one set per
  query in order. Probe `probe_batch_ops` (14 checks incl. recover
  equality, duplicate-id collapse, Hnsw batch path); suite mirror test
  added (170 -> 171). F 70 -> 73; overall 71.02 -> 71.26 -> 71 %. Evidence:
  full batteries (suite 171/171 x2 + 20 probes x2, Windows + WSL), ALL
  GATES GREEN.
- **2026-10-09 (thirty-eighth pass):** M-G benchmark harness + baseline --
  `bench/bench_main.xi` (deterministic W1-W7 workloads, integer JSON,
  group-calibrated sampling, hard-capped budgets, `XV_BENCH_STAGE`
  diagnostics) + `scripts/bench.ps1/.sh`; **bench smoke wired into both CI
  batteries**; baseline committed in `docs/BENCHMARKS.md`. Found and fixed
  the **O(L^2) `wal_persist` string builder** (linear `append_bytes`; the
  builder drove multi-GB paging during bring-up); `probe_wal_file` +4
  scale checks (1200 records). Native `--icon` embedding wired
  (`scripts/build.ps1` + `images/xvector-icon.ico`). I 84 -> 86; overall
  71.26 -> 71.44 -> 71 %. Evidence: full batteries (suite 171/171 x2 + 20
  probes x2 + bench smoke, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (thirty-ninth pass):** M-D2 manifest file -- new
  `durability.manifest_file` (`xvector-manifest 1` text registry: one line
  per collection `name dim mc kc m efc efs`; whole-file persist with atomic
  temp+rename; invalid entries refused with the target untouched;
  torn-tail-safe byte-level load with a complete-entry prefix; names 1..64
  chars of `[A-Za-z0-9_.-]`). Engine: `engine_manifest_save` +
  `engine_recover_file` (facade `save_manifest`/`open_engine`) -- the file
  registry governs and the in-WAL manifest is the migration fallback
  (shared private `engine_recover_with`). Stable metric/kind codes moved to
  the leaf modules; wal_file byte helpers shared (`parse_int_at`,
  `append_bytes`). New compiler finding **XVC-C-13** (`&Str` params
  mislower to i64; repro `docs/repro/xv-str-ref-param/`, relay Addendum 9).
  Probe `probe_manifest_file` (38 checks; both batteries now 21 probes).
  D 65 -> 68; overall 71.44 -> 72.04 -> 72 %. Evidence: full batteries
  (suite 171/171 x2 + 21 probes x2 + bench smoke, Windows + WSL), ALL GATES
  GREEN.
- **2026-10-09 (fortieth pass):** M-D3 multi-collection registry -- named
  collections (create/select/drop/list; facade + engine), per-collection
  isolation of stores/payloads/index configs, WAL ManifestUpdate v2 config
  + v3 drop records with cid-stamped data records, routed multi-collection
  recovery (D3 strict mode; legacy logs route to the single collection),
  whole-registry checkpoint, whole-registry `save_manifest` + file-wins
  `open_engine`, legacy `create_collection` -> "default". Gate
  `probe_collections` (41 checks; batteries now 22 probes). F 73 -> 75,
  G 10 -> 25; overall 72.04 -> 73.70 -> 74 %. Evidence: full batteries
  (suite 171/171 x2 + 22 probes x2 + bench smoke, Windows + WSL), ALL
  GATES GREEN; no regression across the recovery rewrite.
- **2026-10-09 (forty-first pass):** M-D4 sealed segment files -- new
  `segment.segment_file` codec (meta + vector + payload + optional Hnsw
  graph records; whole-file atomic persist; torn-tail-safe complete-record
  prefix load; 41-byte size guard), `segment_state_from_code`, engine
  `engine_seal_segment` (real lifecycle Mutable -> Sealing -> Sealed) and
  `engine_restore_segment` (cid/dim/metric validated; WAL re-checkpoint via
  the shared `engine_checkpoint_from`, LSN-continuous), facade
  `seal_segment`/`restore_segment`. Gate `probe_segment_file` (38 checks;
  batteries now 23 probes). D 68 -> 73; overall 73.70 -> 74.70 -> 75 %.
  Evidence: full batteries (suite 171/171 x2 + 23 probes x2 + bench smoke,
  Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (forty-second pass):** M-Q3 pagination -- new
  `query.pagination` (offset + after-id kernels over the (distance
  ascending, id ascending) total order; bounded collector with the id
  tie-break), engine/facade `search_page` / `search_after` (missing
  cursor -> `Err(NotFound)`; exact on Flat AND Hnsw). Gate
  `probe_pagination` (22 checks; batteries now 24 probes): page
  reconstruction without gaps/dupes, exact tie clusters id-ascending,
  cursor walks across tie boundaries, refusals, Flat/Hnsw bit-parity,
  pages after recovery, deleted cursors. F 75 -> 78; overall 74.70 ->
  74.94 -> 75 %. Evidence: full batteries (suite 171/171 x2 + 24 probes
  x2 + bench smoke, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (forty-third pass):** M-Q4 delete-by-filter --
  `engine_delete_filter` / `delete_filter`: planner-driven selective
  delete (index candidates for Eq/Range/Exists/And-of-those, each
  verified; live-store scan for In/Or/Not), ids collected before
  mutation and applied ascending through the gated single-delete path
  (per-point WAL, graph tombstones, payload + index cleanup); nothing
  matching -> Ok(0). Gate `probe_delete_filter` (26 checks; batteries
  now 25 probes). F 78 -> 80; overall 74.94 -> 75.10 -> 75 %. Evidence:
  full batteries (suite 171/171 x2 + 25 probes x2 + bench smoke, Windows
  + WSL), ALL GATES GREEN.
- **2026-10-09 (forty-fourth pass):** M-Q5 index admin --
  `engine_collection_stats` / `collection_stats` (per-collection config,
  live points, payloads, Hnsw nodes + tombstones, shared WAL lsn; active
  from the live fields, parked from registry entries) and
  `engine_rebuild_index` / `rebuild_index` (admin rebuild with
  kind/points/nodes_before/nodes_after/reclaimed stats; Hnsw fresh graph
  over live nodes, Flat no-op; compact_index stays the Int wrapper). Gate
  `probe_index_admin` (20 checks; batteries now 26 probes). F 80 -> 82;
  overall 75.10 -> 75.26 -> 75 %. Evidence: full batteries (suite 171/171
  x2 + 26 probes x2 + bench smoke, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (forty-fifth pass):** M-Q6 request surface extensions --
  `SearchRequest` gains mode (knn/range), radius (top_k = inclusive-radius
  limit), and knn offset/after-id pagination (mutually exclusive; filters
  stay Knn-only; cursor keeps `Err(NotFound)`); `SearchBatchRequest` +
  `HydratedBatch` + `search_batch_with_request` (ordered, all-or-nothing);
  dimension/top_k/metric validation unchanged. Gate `probe_search_request`
  extended 10 -> 24 checks (probe-only; the suite mirror is a standalone
  re-implementation and stays untouched). F 82 -> 84; overall 75.26 ->
  75.42 -> 75 %. Evidence: full batteries (suite 171/171 x2 + 26 probes x2
  + bench smoke, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (forty-sixth pass):** M-G1 reference oracle --
  `probe_reference_oracle` (22 checks): an independent Float64 oracle
  cross-checks the three kernels pairwise (780 seeded pairs each;
  per-build deviations at Float32-ulp scale -- cosine 1.70e-07, dot
  9.83e-07, euclidean 5.06e-07, bit-identical Windows/WSL), the metric
  axioms (exact symmetry; self-distance l2==0 / cosine~0 / dot==-|v|^2;
  euclidean triangle inequality; cosine [0,2] + exact x2 scale
  invariance; zero-vector guard == 1.0), and the ranked/page/cursor/range/
  Hnsw paths vs the oracle ranking (top-5 rank exact per metric,
  inclusive-range subset at a midpoint radius, engine-distance boundary
  inclusion, Hnsw recall@5 == 5/5 + distance fidelity). Batteries now 27
  probes. I 86 -> 92; overall 75.42 -> 75.96 -> 76 %. Evidence: full
  batteries (suite 171/171 x2 + 27 probes x2 + bench smoke, Windows +
  WSL), ALL GATES GREEN.
- **2026-10-09 (forty-seventh pass):** M-S1 HTTP service skeleton -- new
  `api.http_service` (transport-agnostic HTTP/1.1 byte pipeline:
  strict parse -> router -> stdlib-JSON wire -> byte-exact responses; no
  sockets until the `xiom.net` proof). Endpoints: `/health`,
  `/collections`, points get/upsert/delete, `/search` (knn/range/page/
  batch), `/stats`. Uses QUALIFIED stdlib JSON calls (`json.json_*`): the
  parent `xiom.serialize` helpers misresolve in this unit (BUG 25 #1,
  documented in the json module header) and unqualified calls silently
  built empty strings -- pinned as lane discipline. Two real parser bugs
  found by the probe and fixed (method never stored; last header line
  dropped). Gate `probe_http_service` (40 checks; batteries now 28
  probes). F 84 -> 86, H 20 -> 28; overall 75.96 -> 76.52 -> 77 %.
  Evidence: full batteries (suite 171/171 x2 + 28 probes x2 + bench
  smoke, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (forty-eighth pass):** M-S2 service config/limits/errors --
  `ServiceConfig` (max_request_bytes 65536 / max_top_k 1000 / max_batch
  256 / max_dim 1024) with env (`XVECTOR_MAX_*`; malformed ignored) and
  key=value file loaders (comments; unknown keys ignored; a malformed line
  sets valid=false while good lines still apply); `http_service_handle_cfg`
  enforces limits (request size and batch counts -> 413 too_large
  before/at routing; named top_k/dim -> 400; exact boundaries accepted);
  every error is `{error,kind,status}` with stable kinds and
  `core_err_response` maps the full CoreError enum;
  `http_service_shutdown` = drain + whole-file WAL checkpoint (false on
  unwritable paths). Gate `probe_service_limits` (27 checks; batteries now
  29 probes). F 86 -> 88; overall 76.52 -> 76.68 -> 77 %. Evidence: full
  batteries (suite 171/171 x2 + 29 probes x2 + bench smoke, Windows +
  WSL), ALL GATES GREEN.
- **2026-10-09 (forty-ninth pass):** M-S3 service auth + rate limiting --
  `ApiScope` (read < write < admin) + `ServiceAuth` (keys 8..128 of
  `[A-Za-z0-9_.-]`, duplicates rejected, first key enables; embedded
  default off), constant-time lookups via
  `xiom.crypto.mac.constant_time_eq`, `XVECTOR_API_KEYS` env loader, route
  scope map (`/health` public; POST /collections Admin; points
  POST/DELETE Write; else Read), 401 unauthorized / 403 forbidden kinds;
  token-bucket `RateLimiter` (capacity + refill/sec, explicit clock) with
  429 rate_limited; `ServiceState` + `http_service_handle_state`
  (auth-off == handle_cfg). Gate `probe_service_auth` (24 checks;
  batteries now 30 probes). F 88 -> 89; overall 76.68 -> 76.76 -> 77 %.
  Evidence: full batteries (suite 171/171 x2 + 30 probes x2 + bench
  smoke, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (fiftieth pass):** M-S4 security pass -- `docs/SECURITY.md`
  (assets, trust boundaries, secure-defaults table, threat/control
  matrix, dependency + SBOM statement, no-unsafe audit, honest
  out-of-scope list). `probe_http_fuzz` (14 checks): 1200 seeded mutations
  + 1300 random streams all well-formed; targeted abuse (lying
  Content-Length, 2000-header flood, 30 KB header, 60 KB unbalanced JSON,
  8000-deep nesting, NUL bytes, 500-segment path, 300-burst) bounded.
  **Found + fixed a remote stack-exhaustion DoS:** stdlib `json_parse`
  recurses per nesting level and ~60 KB of `[` (inside the body limit)
  crashed with an access violation; the HTTP edge now pre-scans bodies
  with `json_depth_ok(body, 64)` and rejects deeper payloads with 400
  (stdlib row filed in `docs/STDLIB-WISHLIST-XVECTOR.md`).
  `scripts/sbom.ps1`/`sbom.sh` emit `out/sbom.json` (compiler, stdlib
  pin, per-module sha256, unsafe=0) and fail on any `unsafe` in src/;
  both batteries run the SBOM + unsafe gate. Lane re-check at the wrap:
  stdlib advanced `ed6d46c` -> `d2b18dc` (waves 100-101) but
  fsync/fdatasync/truncate/append remain stubs -- D5/D6/P5 stay gated.
  I 92 -> 94, J 48 -> 52; overall 76.76 -> 77.26 -> 77 %. Evidence: full
  batteries (suite 171/171 x2 + sbom + 31 probes x2 + bench smoke,
  Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (fifty-first pass):** M-O observability core -- new
  `observability.metrics` (fixed-bucket latency histograms with
  `_sum`/`_count`/p50/p95/p99; the requests/errors/search/upsert/
  auth_failures/rate_limited counters; a bounded, sanitized JSON log ring
  with slow-query flag), public `GET /metrics` (prometheus text + live
  gauges collections/points_active/lsn), `/health` `ready:true`,
  per-request instrumentation in `http_service_handle_state`, and
  `docs/OPERATIONS.md` (runbook + failure domains + backup drill). Found
  + worked around the XVC-C-09 family again: nested-field mutation
  through a `&mut` param (`st.metrics.counter`) silently does not
  persist -- copy-out + single write-back. Gate `probe_metrics` (23
  checks; batteries now 32 probes). H 28 -> 70, J 52 -> 54; overall
  77.26 -> 79.52 -> 80 %. Evidence: full batteries (suite 171/171 x2 +
  sbom + 32 probes x2 + bench smoke, Windows + WSL), ALL GATES GREEN.
- **2026-10-09 (fifty-second pass):** M-R release candidate v1.0.0-rc.1 --
  `VERSION` bump, release notes, SBOM snapshot
  (`docs/sbom-v1.0.0-rc.1.json`; 44 modules, unsafe=0), the PULSE-style
  owner handoff (`docs/OWNER-HANDOFF.md`: repo public, runners, rulesets,
  publish flow, benchmark protocol, gated-pivot table, evidence index),
  and the audited `docs/RELEASE-CHECKLIST.md` (all primary repro bundles
  re-run at v0.64.2: 9 green, `contract-trap-exit0` exit 1 = the fixed
  symptom, XVC-C-13 red by design). Final batteries at the candidate
  commit `5226226` on **Windows and WSL**: suite 171/171 x2 + sbom + 32
  probes x2 + bench smoke, ALL GATES GREEN; annotated tag `v1.0.0-rc.1`
  (no GPG key available; DCO sign-off on every commit). J 54 -> 56;
  overall 79.52 -> 79.68 -> 80 %. The owner has been told; the public
  release + benchmark remain the owner's actions.

## Update rule

Recompute at every wrap: adjust phase scores, recompute the weighted overall,
append a change-log line with the commit and the evidence used. Never raise a
score without naming evidence; never hide a regression -- a red suite or a
new blocker moves the number down.
