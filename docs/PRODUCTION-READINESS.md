<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVECTOR -- Production-Readiness Tracker

**How far is xiom-xvector from a production-grade vector database?**
This is the honest, evidence-based scorecard. It is recomputed at every lane
wrap and every number must point at evidence (tests, probes, docs) or name
the missing work.

- **As of:** 2026-10-09 (post multi-key intersections; E complete)
- **Overall:** **70 %** (weighted; see method)
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
| B | Exact search & query engine | 10 | 95 | release-grade | range-search surface, batch search |
| C | ANN index (HNSW hardening) | 14 | 98 | release-grade | file-backed persistence |
| D | Persistence & durability | 20 | 60 | buildable | stdlib fsync gap, file-backed segments, manifest file, file-level kill test |
| E | Metadata & filtering | 8 | 100 | production | -- |
| F | API & query surface | 8 | 70 | buildable | batch ops, pagination |
| G | Concurrency & scalability | 10 | 10 | none | everything (single-threaded engine today) |
| H | Observability & operability | 5 | 20 | scaffold | metrics surface, health, latency/recall histograms |
| I | Testing & verification | 9 | 82 | release-grade | reference oracle, CI runners |
| J | Ecosystem & release engineering | 8 | 48 | buildable | runners activation, rulesets, staging E2E, porter extraction |

**Overall today:** 0.08x95 + 0.10x95 + 0.14x98 + 0.20x60 + 0.08x100 +
0.08x70 + 0.10x10 + 0.05x20 + 0.09x82 + 0.08x48 = **69.64 -> 70 %**.

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

### B. Exact search & query engine -- 95 %
Done: flat exact KNN, k-bounded sorted results, filtered exact search
(pre-filter scan + selectivity-based post plan with fallback), **filtered
search on ANN collections** (HNSW fetch + matching subset with exact flat
fallback when under-filled; k-fill guarantee kept), SearchHits public
shape, error paths.
Remaining: range-search surface, batch search.

### C. ANN index -- 95 %
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

### D. Persistence & durability -- 60 %
Done: WAL-before-ack for upserts AND metadata, vector + payload codecs,
replay, delete/torn-tail handling, compacted checkpoint, chained reopen,
LSN monotonicity, **in-WAL collection manifest** (dim/metric/index
kind/params survive recover and checkpoints; malformed/legacy fall back),
**kill-recovery acceptance** (prefix exactness at the WAL model level:
recover(prefix) + apply(record) == recover(prefix + record), incl. the
compacted checkpoint log, empty log and corrupt-final-record cases).
Remaining (in order): stdlib fsync/fd-write/append-bytes (blocker doc:
`docs/STDLIB-WISHLIST-XVECTOR.md`), file-backed segment files, file-backed
manifest, file-level crash-kill test, WAL retention/pruning policy.

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

### I. Testing & verification -- 82 %
Done: 168-check conformance suite (x2 Windows + WSL), 17 probes, build-time
watchdog, rebuild-on-red discipline, per-build numeric gates, per-build
compiler-workaround pins (XVC-C-04 shape matrix, C-01 bind semantics), a
deterministic fuzz gate (`probe_fuzz_codecs`), a mixed-workload soak
(`probe_soak_mixed`) and the kill-recovery acceptance
(`probe_kill_recovery`).
Remaining: reference oracle cross-check, CI runner activation.

### J. Ecosystem & release engineering -- 48 %
Done: `.ps1`/`.sh` twins, `xiom.toml`, relay docs + wishlists, porter plan,
version/hash recording, the acyclic porter-ready tree, **release-prep
drafts**: `scripts/ci.ps1` + `scripts/ci.sh` (full pre-release battery with
aggregated exit codes, both verified green), `VERSION` (0.1.0-dev), a
SHA-pinned `.github/workflows/ci.yml` draft, and
`docs/RELEASE-CHECKLIST.md` (owner-gated flow).
Remaining: self-hosted runners activation, branch rulesets on greenlight,
staging E2E (parked until the owner greenlights public release), porter
extraction with the packages lane.

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

## Update rule

Recompute at every wrap: adjust phase scores, recompute the weighted overall,
append a change-log line with the commit and the evidence used. Never raise a
score without naming evidence; never hide a regression -- a red suite or a
new blocker moves the number down.
