<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVECTOR -- Production-Readiness Tracker

**How far is xiom-xvector from a production-grade vector database?**
This is the honest, evidence-based scorecard. It is recomputed at every lane
wrap and every number must point at evidence (tests, probes, docs) or name
the missing work.

- **As of:** 2026-10-08 (post HNSW beam construction + diversified pruning)
- **Overall:** **65 %** (weighted; see method)
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
| B | Exact search & query engine | 10 | 92 | release-grade | range-search surface, batch search |
| C | ANN index (HNSW hardening) | 14 | 90 | release-grade | id map, file-backed persistence, latency metrics |
| D | Persistence & durability | 20 | 55 | buildable | stdlib fsync gap, file-backed segments, durable manifest |
| E | Metadata & filtering | 8 | 97 | release-grade | multi-key indexes |
| F | API & query surface | 8 | 70 | buildable | batch ops, pagination |
| G | Concurrency & scalability | 10 | 10 | none | everything (single-threaded engine today) |
| H | Observability & operability | 5 | 20 | scaffold | metrics surface, health, latency/recall histograms |
| I | Testing & verification | 9 | 72 | buildable | soak, fuzz, kill-recovery test, reference cross-check |
| J | Ecosystem & release engineering | 8 | 40 | buildable | CI, version stamp, porter extraction (tree final; extraction pending), release |

**Overall today:** 0.08x95 + 0.10x92 + 0.14x90 + 0.20x55 + 0.08x97 +
0.08x70 + 0.10x10 + 0.05x20 + 0.09x72 + 0.08x40 = **65.44 -> 65 %**.

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

### B. Exact search & query engine -- 92 %
Done: flat exact KNN, k-bounded sorted results, filtered exact search
(pre-filter scan + selectivity-based post plan with fallback), SearchHits
public shape, error paths.
Remaining: range-search surface, batch search.

### C. ANN index -- 90 %
Done: multi-layer HNSW graph (`index/hnsw.xi`: flat per-(node, layer)
adjacency rows, deterministic geometric levels, greedy descent + layer-0
beam honouring `ef`, metric-agnostic, user-id results), tombstone deletes
(never returned, routers kept, revive on re-insert), tombstone compaction
(`hnsw_compact` rebuilds from live nodes; engine `compact_index`), **engine
wiring** (`VectorEngine.graph/index_kind/ann`, `set_index` Flat/Hnsw,
upsert/delete upkeep, `engine_search` routing with `ef = ann.ef_search`,
filtered search stays exact, recover + re-apply), **strict word codec**
(`hnsw_encode`/`hnsw_decode` v2), **beam construction honouring
`ef_construction`** with diversified pruning (`select_diverse`;
`hnsw_set_ef_construction`; AnnParams seeded by `set_index`), recall
harness vs the flat oracle (n=200: 300/300 at ef=64, 296/300 at ef=8; n=800:
200/200; after-delete 300/300 stray42=0; compacted 200/200
stray_deleted=0; engine-level recall 200/200 incl. an ef_construction=32
build; gates `probe_hnsw_recall`, `probe_engine_hnsw`, `probe_hnsw_codec`),
AnnParams validation.
Remaining: id -> position map, file-backed graph segments (stdlib I/O
pending), harness latency metrics.

### D. Persistence & durability -- 55 %
Done: WAL-before-ack for upserts AND metadata, vector + payload codecs,
replay, delete/torn-tail handling, compacted checkpoint, chained reopen,
LSN monotonicity (probes x2 + 9 suite tests).
Remaining (in order): stdlib fsync/fd-write/append-bytes (blocker doc:
`docs/STDLIB-WISHLIST-XVECTOR.md`), file-backed segment files, durable
manifest (`ManifestUpdate` persistence), crash-kill test harness, WAL
retention/pruning policy.

### E. Metadata & filtering -- 97 %
Done: typed Eq/Range/In/Exists + combinators + no-payload semantics, engine
integration, durable metadata, filtered probe, sorted key index
(parallel-vector rows; exists/count/Eq/Range with semantic float compare;
gate `probe_payload_index`), selectivity planner (exact counts for
Eq/Range/Exists; pre/post choice + fallback; gate `probe_filter_plan`).
Remaining: multi-key indexes (index-driven candidate iteration).

### F. API & query surface -- 70 %
Done: facade (create/upsert/search/delete/get + payloads + filtered search),
Result[..] error discipline, SearchHits shape documented, SearchRequest wire
(real types) driving `search_with_request`, `with_payload` hydration
(`HydratedHits`/`SearchHit`; XVC-C-08-gated in the real-module probe).
Remaining: batch ops, pagination, version endpoint for the future service.

### G. Concurrency & scalability -- 10 %
Done: nothing beyond a single-threaded engine.
Remaining: concurrent readers, write serialization model, segment growth /
compaction, memory budget, multi-collection, benchmark harness.

### H. Observability & operability -- 20 %
Done: inline counters (upserts/deletes), LSN metrics.
Remaining: `xiom.metrics` adoption (Phase 10), /health + /metrics surface per
the OPS pattern, latency/recall histograms, structured logs.

### I. Testing & verification -- 72 %
Done: 168-check conformance suite (x2 Windows + WSL), 13 probes, build-time
watchdog, rebuild-on-red discipline, per-build numeric gates.
Remaining: soak (long-running upsert/search), fuzz (codec + filters),
kill-recovery acceptance script, reference oracle cross-check, CI wiring.

### J. Ecosystem & release engineering -- 40 %
Done: `.ps1`/`.sh` twins, `xiom.toml`, relay docs + wishlists, porter plan for
`xiom.vectors`/`xiom.wal`/`xiom.ann`, version/hash recording, and the final
extraction wave: the acyclic porter-ready tree (`core/shim` <- `engine/core`
<- `engine` facade; payload/types/storage/query/durability modules already
real).
Remaining: CI matrix (SHA-pinned actions), build-info/version stamp,
GitHub release convention, rulesets on greenlight, staging E2E (parked until
the owner greenlights public release), porter extraction with the packages
lane.

## Milestones

| Milestone | Meaning | Status |
|---|---|---|
| M1 Durable in-memory core | WAL + recovery + payloads, green suites + probes | **Met 2026-10-08** |
| M2 Crash-safe on disk | file-backed WAL segments, fsync, durable manifest, kill tests | Blocked on stdlib fsync; ready to start |
| M3 Indexed at scale | HNSW hardening + recall harness, sorted payload index + planner, concurrency | Not started |
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

## Update rule

Recompute at every wrap: adjust phase scores, recompute the weighted overall,
append a change-log line with the commit and the evidence used. Never raise a
score without naming evidence; never hide a regression -- a red suite or a
new blocker moves the number down.
