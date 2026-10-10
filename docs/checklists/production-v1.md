<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Checklist -- xiom-xvector Production v1 (flagship)

Execution checklist for `docs/PRODUCTION-PLAN.md`. Every slice follows the
same pattern: implement -> probe/suite gate -> **suite x2 + probes x2
(Windows) + WSL spot** -> docs (SPEC/ARCHITECTURE/SESSION/readiness as
needed) -> signed commit. Red build = rejection.

## M-G -- Truth & measurement

- [x] G1 reference-oracle cross-check **(done 2026-10-09)**: independent
  Float64 oracle + metric identities/axioms; randomized deterministic
  vectors; `probe_reference_oracle` (22 checks: pairwise kernels 780 pairs
  x3 metrics, axioms, ranked/page/cursor/range/Hnsw vs the oracle)
- [x] G2 benchmark harness **(done 2026-10-09)**: `bench/bench_main.xi` +
  `scripts/bench.ps1/.sh` + CI smoke (W1-W7, JSON, stage diagnostics)
- [x] G3 baseline report **(done 2026-10-09)**: `docs/BENCHMARKS.md`
  (methodology + n=5000 baseline + WSL spot + fixed O(L^2) builder note)

## M-D -- On-disk durability

- [x] D1 atomic checkpoint **(done 2026-10-09)**: `wal_persist` temp+
  `io.rename`; fault-injection probe (staged-complete temp + partial temp
  both leave the previous file; 7 new checks in `probe_wal_file`)
- [x] D2 manifest file **(done 2026-10-09)**: `durability.manifest_file`
  (`xvector-manifest 1` registry; whole-file persist with atomic
  temp+rename; invalid entries refused; torn-tail-safe complete-entry
  prefix load); `engine_manifest_save` + `engine_recover_file`/`open_engine`
  (file registry governs; in-WAL manifest migration fallback);
  `probe_manifest_file` (38 checks)
- [x] D3 multi-collection runtime **(done 2026-10-09)**: named collections,
  create/select/drop/list, isolated stores/payloads/indexes (v2 config +
  v3 drop WAL records; cid-stamped data; routed recovery; whole-registry
  checkpoint + manifest save/open); `probe_collections` (41 checks);
  survives reopen
- [x] D4 segment files **(done 2026-10-09)**: `segment.segment_file`
  codec (meta + vectors + payloads + Hnsw graph; whole-file atomic
  persist; torn-tail-safe complete-record prefix load; lifecycle
  Mutable -> Sealing -> Sealed); engine `seal_segment`/`restore_segment`
  (cid/dim/metric validated; WAL re-checkpoint after restore);
  `probe_segment_file` (38 checks)
- [ ] D5 (GATED: stdlib fsync/append) WAL delta + fsync on commit;
  file-level kill harness (spawn/kill/recover) on Windows + WSL
- [ ] D6 retention policy + snapshots/export-import + restore drill;
  `probe_snapshot`; formats documented in SPEC

## M-Q -- Query surface complete

- [x] Q1 range search **(done 2026-10-09, exact-first)**: `search_range`
  engine/facade + `search_range_scan` kernel; exact on both index kinds;
  `probe_range_search` vs brute force. Request range mode folded into Q6;
  ANN widening deferred to M-P tuning.
- [x] Q2 batch ops **(done 2026-10-09)**: `upsert_many`/`search_many`/
  `delete_many` + `BatchHits`; all-or-nothing validation; `probe_batch_ops`
  (14 checks) + suite mirror
- [x] Q3 pagination **(done 2026-10-09)**: `query.pagination` -- offset
  (`search_page`) + after-id cursor (`search_after`) over the (distance
  asc, id asc) total order; exact tie order by id; exact on Flat and
  Hnsw; `probe_pagination` (22 checks: page consistency + cursor walks)
- [x] Q4 delete-by-filter **(done 2026-10-09)**: `engine_delete_filter` /
  `delete_filter` -- planner-driven (index candidates for Eq/Range/Exists/
  And, scan for In/Or/Not), per-point WAL + tombstones + payload/index
  cleanup, Ok(0) on no match; `probe_delete_filter` (26 checks)
- [x] Q5 per-collection stats + index admin **(done 2026-10-09)**:
  `collection_stats` (config + points + payloads + Hnsw nodes/tombstones +
  lsn; parked entries report without switching) and `rebuild_index`
  (before/after/reclaimed stats; Hnsw fresh graph, Flat no-op);
  `probe_index_admin` (20 checks)
- [x] Q6 `SearchRequest` extensions (mode/page/batch) + validation
  **(done 2026-10-09)**: `SearchMode.Knn | Range` + radius; knn
  `offset` / `after_id` pagination (mutually exclusive; no filters yet);
  `SearchBatchRequest` + `search_batch_with_request` (ordered,
  all-or-nothing); probe-only gate (`probe_search_request`, 24 checks;
  suite mirror untouched -- the mirror is a standalone re-implementation
  without range/pagination dispatch)

## M-S -- Server & security

- [x] S1 HTTP service skeleton **(done 2026-10-09)**: in-repo
  `api.http_service` byte-level HTTP/1.1 pipeline (parse/route/JSON/reply,
  no sockets yet -- the `xiom.net` adapter is C-PULSE-02-gated);
  `/health`, collections create/list, points get/upsert/delete, search
  (knn/range/page/batch), `/stats`; `probe_http_service` (40 checks)
- [x] S2 config (file/env), limits (size/k/batch/dim), JSON error model,
  graceful shutdown (drain+checkpoint) **(done 2026-10-09)**: ServiceConfig
  + `service_config_from_env`/`service_config_load` (key=value); enforced
  limits (413 size/batch, 400 named k/dim); `{error,kind,status}` over the
  full CoreError enum; `http_service_shutdown` WAL checkpoint;
  `probe_service_limits` (27 checks)
- [x] S3 auth: API keys, constant-time compare, scopes; rate limiting;
  auth-on-by-default in service mode; auth probe **(done 2026-10-09)**:
  `ServiceAuth` via `x-api-key` (stdlib constant-time compare; scopes
  read/write/admin; `XVECTOR_API_KEYS`), 401/403 kinds, token-bucket
  `RateLimiter` (429), `ServiceState` + `http_service_handle_state`
  (embedded default off; service adapter enables);
  `probe_service_auth` (24 checks)
- [x] S4 security pass **(done 2026-10-09)**: threat model + secure
  defaults (`docs/SECURITY.md`); HTTP fuzz + resource-exhaustion gate
  (`probe_http_fuzz`, 14 checks, 2500 inputs) with the JSON depth guard
  fixing a found stack-overflow DoS; `scripts/sbom.ps1`/`sbom.sh` SBOM +
  unsafe gate wired into both batteries; no-unsafe audit statement

## M-O -- Observability & operability

- [x] O1 metrics surface **(done 2026-10-09)**: `observability.metrics`
  (dependency-free; `xiom.metrics` adoption stays Phase 10) -- counters
  (requests/errors/search/upsert/auth_failures/rate_limited), latency
  histograms (global + search; 1/5/10/50/100/500/1000 ms + `+Inf`,
  p50/p95/p99), live gauges (collections/points/lsn); `probe_metrics`
  (23 checks)
- [x] O2 `/metrics` + `/health` (live/ready) + structured logs + slow-query
  log **(done 2026-10-09)**: public `GET /metrics` (prometheus text;
  counters + histograms + gauges), `/health` carries `ready:true`, bounded
  JSON-line `LogRing` (method/path/status/ms/slow, sanitized, eviction
  count) wired through `http_service_handle_state`; signals asserted by
  `probe_metrics`
- [x] O3 `docs/OPERATIONS.md` runbook **(done 2026-10-09)**: start/stop +
  shutdown checkpoint, config reference, monitoring + alerts,
  backup/restore drill, failure-domain table, upgrade/migration notes,
  quick diagnostics

## M-P -- Performance & scale

- [ ] P1 concurrency design doc (writer/reader model, consistency notes)
- [ ] P2 memory budget + seal/compaction thresholds; measured
- [ ] P3 SIMD/BLAS seam behind the `xiom.vectors` contract; benchmark delta
  recorded
- [ ] P4 IVF/PQ prototype (v1.1 track) with recall/latency curve
- [ ] P5 (stdlib-dependent) mmap/disk segments; tiered storage

## M-R -- Release candidate & handoff

- [ ] R1 release checklist filled; `VERSION` = `1.0.0-rc`; changelog;
  build-info stamp
- [ ] R2 CI matrix green (Windows + WSL); reproducible artifacts
- [ ] R3 benchmark report + security checklist + SBOM committed
- [ ] R4 owner handoff note (repo/runners/rulesets/benchmark); **tell the
  owner -- public release is the owner's action**
