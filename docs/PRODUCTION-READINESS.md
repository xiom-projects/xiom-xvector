<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVECTOR -- Production-Readiness Tracker

**How far is xiom-xvector from a production-grade vector database?**
This is the honest, evidence-based scorecard. It is recomputed at every lane
wrap and every number must point at evidence (tests, probes, docs) or name
the missing work.

- **As of:** 2026-10-08 (post Phase 3 payload filtering + payload durability)
- **Overall:** **53 %** (weighted; see method)
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
| B | Exact search & query engine | 10 | 90 | release-grade | range-search surface, post-filter planner |
| C | ANN index (HNSW hardening) | 14 | 25 | scaffold | graph quality/tuning, recall harness, tombstones |
| D | Persistence & durability | 20 | 55 | buildable | stdlib fsync gap, file-backed segments, durable manifest |
| E | Metadata & filtering | 8 | 90 | release-grade | sorted key index, pre/post planner |
| F | API & query surface | 8 | 60 | buildable | SearchRequest wire, batch ops, with_payload hydrate |
| G | Concurrency & scalability | 10 | 10 | none | everything (single-threaded engine today) |
| H | Observability & operability | 5 | 20 | scaffold | metrics surface, health, latency/recall histograms |
| I | Testing & verification | 9 | 72 | buildable | soak, fuzz, kill-recovery test, reference cross-check |
| J | Ecosystem & release engineering | 8 | 35 | scaffold | CI, version stamp, porter extraction (three waves extracted), release |

**Overall today:** 0.08x95 + 0.10x90 + 0.14x25 + 0.20x55 + 0.08x90 +
0.08x60 + 0.10x10 + 0.05x20 + 0.09x72 + 0.08x35 = **54.38 -> 54 %**.

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
top-K bounded heap, exact f32<->bits codec, 165-check suite.
Remaining: reference cross-check (numpy-style oracle) under fuzz; NaN/Inf
documented policy in distance kernels.

### B. Exact search & query engine -- 90 %
Done: flat exact KNN, k-bounded sorted results, filtered exact search
(pre-filter), SearchHits public shape, error paths.
Remaining: range-search surface, post-filter planner, `SearchRequest`-driven
search, batch search.

### C. ANN index -- 25 %
Done: in-memory HNSW from the bootstrap (simplified), AnnParams validation.
Remaining: graph build quality, ef tuning, search recall harness vs flat
oracle, tombstone/delete handling, memory accounting, persistence of the
graph.

### D. Persistence & durability -- 55 %
Done: WAL-before-ack for upserts AND metadata, vector + payload codecs,
replay, delete/torn-tail handling, compacted checkpoint, chained reopen,
LSN monotonicity (probes x2 + 9 suite tests).
Remaining (in order): stdlib fsync/fd-write/append-bytes (blocker doc:
`docs/STDLIB-WISHLIST-XVECTOR.md`), file-backed segment files, durable
manifest (`ManifestUpdate` persistence), crash-kill test harness, WAL
retention/pruning policy.

### E. Metadata & filtering -- 90 %
Done: typed Eq/Range/In/Exists + combinators + no-payload semantics, engine
integration, durable metadata, filtered probe.
Remaining: sorted key index (O(log n)), pre/post-filter planner, multi-key
indexes.

### F. API & query surface -- 60 %
Done: facade (create/upsert/search/delete/get + payloads + filtered search),
Result[..] error discipline, SearchHits shape documented.
Remaining: SearchRequest wire type, `with_payload` hydration, batch ops,
pagination, version endpoint for the future service.

### G. Concurrency & scalability -- 10 %
Done: nothing beyond a single-threaded engine.
Remaining: concurrent readers, write serialization model, segment growth /
compaction, memory budget, multi-collection, benchmark harness.

### H. Observability & operability -- 20 %
Done: inline counters (upserts/deletes), LSN metrics.
Remaining: `xiom.metrics` adoption (Phase 10), /health + /metrics surface per
the OPS pattern, latency/recall histograms, structured logs.

### I. Testing & verification -- 65 %
Done: 165-check conformance suite (x2 Windows + WSL), 6 probes, build-time
watchdog, rebuild-on-red discipline, per-build numeric gates.
Remaining: soak (long-running upsert/search), fuzz (codec + filters),
kill-recovery acceptance script, reference oracle cross-check, CI wiring.

### J. Ecosystem & release engineering -- 20 %
Done: `.ps1`/`.sh` twins, `xiom.toml`, relay docs + wishlists, porter plan for
`xiom.vectors`/`xiom.wal`/`xiom.ann`, version/hash recording.
Remaining: CI matrix (SHA-pinned actions), build-info/version stamp,
GitHub release convention, rulesets on greenlight, staging E2E (parked until
the owner greenlights public release).

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

## Update rule

Recompute at every wrap: adjust phase scores, recompute the weighted overall,
append a change-log line with the commit and the evidence used. Never raise a
score without naming evidence; never hide a regression -- a red suite or a
new blocker moves the number down.
