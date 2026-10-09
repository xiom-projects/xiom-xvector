<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Checklist -- xiom-xvector Production v1 (flagship)

Execution checklist for `docs/PRODUCTION-PLAN.md`. Every slice follows the
same pattern: implement -> probe/suite gate -> **suite x2 + probes x2
(Windows) + WSL spot** -> docs (SPEC/ARCHITECTURE/SESSION/readiness as
needed) -> signed commit. Red build = rejection.

## M-G -- Truth & measurement

- [ ] G1 reference-oracle cross-check: independent Float64 oracle + metric
  identities/axioms; randomized deterministic vectors; `probe_reference_oracle`
- [x] G2 benchmark harness **(done 2026-10-09)**: `bench/bench_main.xi` +
  `scripts/bench.ps1/.sh` + CI smoke (W1-W7, JSON, stage diagnostics)
- [x] G3 baseline report **(done 2026-10-09)**: `docs/BENCHMARKS.md`
  (methodology + n=5000 baseline + WSL spot + fixed O(L^2) builder note)

## M-D -- On-disk durability

- [x] D1 atomic checkpoint **(done 2026-10-09)**: `wal_persist` temp+
  `io.rename`; fault-injection probe (staged-complete temp + partial temp
  both leave the previous file; 7 new checks in `probe_wal_file`)
- [ ] D2 manifest file: registry persisted whole-file + rename; load on
  open; in-WAL manifest migration fallback; `probe_manifest_file`
- [ ] D3 multi-collection runtime: named collections, create/drop/list,
  isolated stores/payloads/indexes; `probe_collections`; survives reopen
- [ ] D4 segment files: sealed segments (vectors+payloads+graph codec)
  whole-file + rename; load-on-open; `probe_segments_file`
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
- [ ] Q3 pagination: stable offset/after-id paging + tie-break documented;
  `probe_pagination` (page consistency)
- [ ] Q4 delete-by-filter: planner-driven selective delete + WAL + tombstone
  upkeep; `probe_delete_filter`
- [ ] Q5 per-collection stats + index admin (`rebuild_index`, build/compact
  stats); `probe_index_admin`
- [ ] Q6 `SearchRequest` extensions (mode/page/batch) + validation; suite
  mirrors updated

## M-S -- Server & security

- [ ] S1 HTTP service skeleton (adopt `xiom.http` or facade-compatible
  fallback): `/health`, collections/points CRUD+batch, search (knn/
  filtered/range/page), `/stats`; `probe_http_service`
- [ ] S2 config (file/env), limits (size/k/batch/dim), JSON error model,
  graceful shutdown (drain+checkpoint); abuse probe
- [ ] S3 auth: API keys, constant-time compare, scopes; rate limiting;
  auth-on-by-default in service mode; auth probe
- [ ] S4 security pass: threat model, HTTP fuzz gate, resource-exhaustion
  tests, dependency pins + SBOM, `docs/SECURITY.md`, unsafe audit statement

## M-O -- Observability & operability

- [ ] O1 `xiom.metrics` adoption: counters/gauges/histograms (ops, errors,
  latency, lsn, sizes); metrics probe
- [ ] O2 `/metrics` + `/health` (live/ready) + structured logs + slow-query
  log; signals asserted by probe
- [ ] O3 `docs/OPERATIONS.md` runbook: start/stop, backup/restore drill,
  upgrade/migration, failure modes

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
