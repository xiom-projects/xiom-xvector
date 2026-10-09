<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom-xvector -- Production Plan (v1.0 flagship)

**Purpose:** the execution plan that takes xiom-xvector from a hardened
single-node engine (70 % weighted readiness, suite 169/169 x2 + 18 probes x2
on compiler v0.64.2) to a **production-grade, benchmarkable, releasable
vector database** that serves as the XIOM ecosystem's flagship.

**Companions:** `docs/requirements/production-v1.md` (intake),
`docs/checklists/production-v1.md` (step-by-step checklist),
`docs/PRODUCTION-READINESS.md` (scorecard), `docs/REL*-*.md` (lane relays).

---

## 0. Execution rules (unchanged lane discipline)

1. **One slice at a time.** A slice = one capability + its gates + docs.
2. **Verification contract per slice:** implement; add/extend a probe (and
   suite mirrors where the suite covers it); run suite **x2** + all probes
   **x2** on Windows; WSL spot (full WSL battery at wraps); `ci.ps1` +
   `ci.sh` green; signed conventional commits; docs updated in the same
   step (SPEC/ARCHITECTURE/SESSION/readiness as applicable).
3. **Red = rejection.** Numeric gates per build; rebuild + re-verify.
4. **Externally gated work is not idle work.** While the stdlib fsync chain
   is pending, work the non-gated slices; re-check the lanes each wrap.
5. **Owner gates the public release.** The lane reports when the release
   candidate is ready (R-milestone) and never pushes.

---

## 1. Target architecture (v1.0)

```mermaid
flowchart TB
  subgraph Surfaces
    EMB["Embedded XIOM app<br/>(xiom.vector.engine facade)"]
    CLI["xvector CLI<br/>(bench + admin)"]
    SRV["HTTP JSON service<br/>(xiom.http + auth/limits)"]
  end

  subgraph Engine["Engine (single node)"]
    REG["Collection registry<br/>(multi-collection, manifest-backed)"]
    PLAN["Query planner<br/>filter pre/post + candidates"]
    SRCH["Search service<br/>knn / filtered / range / batch / page"]
    IDX["Indexes<br/>Flat exact | HNSW | (IVF/PQ v1.1)"]
    PAY["Payload store<br/>typed values + sorted key index"]
  end

  subgraph Storage["Storage"]
    SEG["Segments<br/>mutable -> sealed -> compacting"]
    WALF["WAL<br/>in-memory + file checkpoint/delta"]
    MAN["Manifest<br/>collections + segments + LSN"]
    SNAP["Snapshots / export-import"]
  end

  subgraph Platform
    STD["stdlib<br/>io / os / hash / num / contracts"]
    PKG["packages<br/>xiom.wal - xiom.vectors - xiom.ann<br/>xiom.metrics - xiom.http"]
    BIND["bindings (optional)<br/>SIMD / BLAS behind contract"]
  end

  EMB --> REG
  CLI --> REG
  SRV --> REG
  REG --> PLAN --> SRCH --> IDX
  SRCH --> PAY
  REG --> SEG
  SEG --> MAN
  SEG --> WALF
  WALF --> MAN
  SNAP --> SEG
  IDX --> BIND
  SEG --> STD
  WALF --> PKG
  SRV --> PKG
```

**Durability model:** WAL-before-ack; whole-file checkpoints with atomic
temp+rename today; delta append + `fsync` the moment the stdlib rows land;
manifest + segment files versioned and roundtripped; snapshots for backup.

**Index tiering:** exact Flat (oracle + small collections), HNSW (default
ANN), IVF/PQ (v1.1 scale tier). Segment-level immutable indexes with
fan-out + merge.

---

## 2. Capability target vs modern databases (v1.0)

| Capability | v1.0 target | Notes |
|---|---|---|
| Collections | multi, named, per-collection config | FR-1 |
| Metrics | cosine / dot / L2 | done |
| Exact search | Flat KNN + range oracle | range surface pending (Q1) |
| ANN | HNSW (tunable `m`/`ef_construction`/`ef_search`, tombstone-safe) | done, hardened |
| Filtering | typed AST, sorted index, pre/post planner, compound intersect | done (E 100 %) |
| Payloads | typed + `with_payload` hydration + updates/deletes | done |
| Batch / pagination | batch upsert/search, offset/after paging | Q2/Q3 |
| Delete-by-filter | selective delete with WAL + index upkeep | Q4 |
| Durability | WAL + atomic checkpoints + manifest + segments; fsync delta when stdlib lands | M-D |
| Crash tests | automated kill-matrix (prefix-exact + fsync path) | M-D5 |
| Server | HTTP JSON + auth + limits + graceful shutdown | M-S |
| Observability | metrics + health + structured logs | M-O |
| Backup | snapshot/export-import | M-D6 |
| Security | authn, validation, limits, fuzz/soak, SBOM | M-S4 |
| Performance | in-memory 1M-scale; SIMD seam; measured p99/QPS | M-P |
| Scale-out | **v2** (sharding/replication); IVF/PQ v1.1 | non-goal v1.0 |
| Hybrid search | **v1.1+** | non-goal v1.0 |

---

## 3. Milestones and slices (ordered)

### M-G -- Truth & measurement (start now; feeds everything)

Goal: every later number is measured, not assumed.

- **G1 reference-oracle cross-check** -- an independent in-repo oracle
  (Float64 reference math + metric identities/axioms: symmetry, triangle
  bounds, self-distance, normalization; randomized vectors, deterministic
  seeds) vs the engine kernels. Probe `probe_reference_oracle`.
- **G2 benchmark harness** (`bench/`) -- deterministic workloads: ingest,
  KNN (per metric/ef), filtered (selective/majority), range, batch, mixed
  soak; metrics: build time, QPS, p50/p95/p99, recall@k vs the exact
  oracle, bytes/vector proxy, recovery time. JSON + markdown report.
  `scripts/bench.ps1` / `.sh` twins.
- **G3 baseline report** -- `docs/BENCHMARKS.md` with the first numbers +
  methodology + how to reproduce; protocol doc for the owner's benchmark
  (CLI flags in, JSON out).

Exit: oracle probe green both platforms; one-command bench reproducible;
baseline committed.

### M-D -- On-disk durability (in progress; last slice stdlib-gated)

Goal: a kill never costs an acknowledged write on the available path.

- **D1 atomic checkpoint** -- `wal_persist` writes `path.tmp` then
  `io.rename` (available today); fault-injection probe: kill/interrupt
  between write and rename keeps the previous consistent file.
- **D2 manifest file** -- collection registry (name/dim/metric/index/params)
  persisted whole-file + atomic rename; load on open; migration fallback
  for the in-WAL manifest.
- **D3 multi-collection runtime + APIs** -- named collections in the
  engine, create/drop/list, per-collection isolation of stores/payloads/
  indexes; manifest-backed (D2). Probe `probe_collections`.
- **D4 segment files** -- sealed segments (vectors + payloads + HNSW codec)
  written whole-file + atomic rename; load-on-open; segment lifecycle wired
  to seal thresholds (P2 owns tuning). Probe `probe_segments_file`.
- **D5 WAL delta + fsync + file-level kill test** *(gated: stdlib fsync /
  append-bytes)* -- append-only delta with `fsync` on commit; harness that
  spawns a child writer, kills it mid-append, and proves recovery has every
  acknowledged record; runs on Windows + WSL.
- **D6 retention + snapshots** -- checkpoint policy (compact + swap;
  truncate when stdlib lands), export/import snapshot format, restore drill.
  Probe `probe_snapshot`.

Exit: kill-matrix green; recovery time measured; formats versioned and
documented (SPEC); snapshots restore bit-exact stores.

### M-Q -- Query surface complete

Goal: the single-node query surface a modern DB is expected to have.

- **Q1 range search -- DONE 2026-10-09 (exact-first)** -- `search_range`
  engine/facade + `search_range_scan` kernel; exact on both index kinds
  (inclusive radius, distance-sorted, limit-bounded); gate
  `probe_range_search`. ANN widening deferred to M-P tuning; request range
  mode folded into Q6.
- **Q2 batch ops -- DONE 2026-10-09**: `upsert_many` / `delete_many` /
  `search_many` + `BatchHits`; all-or-nothing validation per call; gate
  `probe_batch_ops`. (Records are WAL-appended per point; an amortized
  batch-record format is a D5-era option, not required by the current
  semantics.)
- **Q3 pagination** -- stable `offset`/`after_id` paging over sorted hits
  with distance tie-breaking documented; probe for page consistency.
- **Q4 delete-by-filter** -- planner-driven selective delete (index plan or
  scan), WAL-durable, graph tombstones; probe with index/payload cleanup.
- **Q5 per-collection stats + index admin** -- size/live counts, index
  kind/params, build/compact stats, `rebuild_index`; probe.
- **Q6 request surface extensions** -- `SearchRequest` carries
  `mode` (knn/range), pagination, batch; metric/validation unchanged.

Exit: probes for every path; suite mirrors where applicable; capability
matrix rows green.

### M-S -- Server & security

Goal: the service surface the ecosystem and benchmarks consume.

- **S1 HTTP service skeleton** -- adopt `xiom.http` (+`xiom.router`?) once
  source-roots wiring is proven (C-PULSE-02); endpoints: `/health`,
  `/collections`, `/collections/{id}/points` (upsert/get/delete, batch),
  `/search` (knn/filtered/range/batch/page), `/stats`. In-repo fallback
  module behind the same facade if the package proves too young.
- **S2 config + limits + errors** -- config file/env, request size/`k`/
  batch/dim limits, JSON error model mapped from `CoreError`, graceful
  shutdown (drain + checkpoint).
- **S3 auth** -- API keys (header, constant-time compare, scopes:
  read/write/admin), disabled-by-default only in embedded mode; rate
  limiting via `xiom.rate` if suitable, else minimal token bucket.
- **S4 security pass** -- threat model doc (asset/trust boundaries),
  HTTP input fuzzing + codec fuzz gates, resource-exhaustion tests,
  dependency pinning + SBOM, `unsafe` audit statement, secure defaults,
  docs/SECURITY.md.

Exit: service probe (start -> CRUD -> search -> shutdown) + abuse suite;
auth on by default; SECURITY.md committed.

### M-O -- Observability & operability

- **O1 metrics adoption** -- `xiom.metrics` wiring: counters (ops, errors,
  points, lsn), gauges (collections, segments, memory proxy), histograms
  (latency per op, recall proxy on demand).
- **O2 surfaces** -- `/metrics` + `/health` (liveness/readiness), structured
  logs (JSON lines) + slow-query log; probe asserts signals.
- **O3 runbook & failure modes** -- docs/OPERATIONS.md: start/stop,
  backup/restore drill, upgrade/migration, known failure domains
  (ARCHITECTURE 7 extended).

Exit: metrics probe; docs complete; ops drill passes.

### M-P -- Performance & scale

- **P1 concurrency design** -- design doc first (XIOM runtime reality):
  target model = process-level single-writer + read-only snapshots, or
  cooperative readers if the runtime permits; explicit consistency notes.
- **P2 memory budget + seal/compaction thresholds** -- bounded memory,
  segment sizing, compaction policy; measured.
- **P3 SIMD/BLAS seam** -- distance kernels behind the `xiom.vectors`
  contract; bindings accelerate when available; benchmark deltas recorded.
- **P4 IVF/PQ prototype** (v1.1 track) -- quantized storage, recall/latency
  curve vs HNSW.
- **P5 mmap/disk segments** (stdlib-dependent) -- tiered storage.

Exit: 1M-vector in-memory workload within published latency/QPS targets;
roadmap to 10M with measured extrapolation.

### M-R -- Release candidate & owner handoff

- **R1** release checklist completion (`docs/RELEASE-CHECKLIST.md`), version
  `1.0.0-rc`, changelog, build-info stamp.
- **R2** CI matrix green (Windows + WSL); reproducible artifacts.
- **R3** benchmark report + methodology; security checklist + SBOM.
- **R4** owner handoff package: setup steps (repo public, runners,
  rulesets, publish flow) mirroring PULSE; **the lane tells the owner it is
  ready before any public action**.

Exit: owner performs the public release; the owner's benchmark can drive
the DB through the documented protocol.

### M-v2 (programme after v1.0)

Distribution (sharding/replication/consistency), hybrid dense+sparse,
deep quantization + tiered storage, client SDKs.

---

## 4. Immediate slice backlog (first 12, ordered)

| # | Slice | Milestone | Gate |
|---|---|---|---|
| 1 | Atomic checkpoint (temp+rename) | D1 | `probe_wal_file` extension + suite x2 + probes x2 |
| 2 | Range search -- **DONE 2026-10-09** (exact-first; ANN widening -> M-P) | Q1 | `probe_range_search` vs brute force |
| 3 | Batch ops -- **DONE 2026-10-09** | Q2 | `probe_batch_ops` (14 checks) |
| 4 | Benchmark harness + baseline | G2/G3 | bench script green; `docs/BENCHMARKS.md` |
| 5 | Manifest file | D2 | `probe_manifest_file` |
| 6 | Multi-collection | D3/FR-1 | `probe_collections` |
| 7 | Pagination | Q3 | `probe_pagination` |
| 8 | Delete-by-filter | Q4 | `probe_delete_filter` |
| 9 | Reference oracle | G1 | `probe_reference_oracle` |
| 10 | HTTP skeleton + health | S1 | `probe_http_service` |
| 11 | Config/limits/errors | S2 | service abuse probe |
| 12 | Auth | S3 | auth probe (reject/accept, scopes) |

Gated items (D5 fsync chain, P5 mmap, truncate-based retention) are picked
up the moment the stdlib lane lands the primitives; re-check every pass.

---

## 5. Benchmark programme (benchmark-ready for the owner)

- **Harness:** `bench/` runner with deterministic seeds; workloads:
  W1 ingest N vectors (dim configurable), W2 KNN (metric × ef sweep),
  W3 filtered (selective + majority), W4 range, W5 batch, W6 mixed soak,
  W7 kill/recover timing. Output: JSON + markdown tables.
- **Metrics:** QPS, p50/p95/p99, recall@k vs exact oracle on a fixed
  sample, build time, bytes/vector, recovery time.
- **Datasets:** synthetic (LCG) built-in; importers for fvecs / JSONL /
  CSV so the owner's benchmark can feed real data (SIFT1M-class).
- **Protocol for external benches:** stable CLI (`xvector-bench --data ...
  --queries ... --json out.json`) + later the HTTP service; documented in
  `docs/BENCHMARKS.md` with methodology and hardware notes.
- **Honesty rule:** every published number names the workload, dataset,
  parameters, platform, compiler/stdlib versions.

## 6. Security programme

- **Auth & transport:** API keys (scopes, constant-time compare); TLS
  documented per deployment (bindings/stdlib dependent); secure defaults.
- **Validation:** every boundary (HTTP, facade) validates dims/k/batch/
  filter shapes via contracts; malformed inputs rejected with typed errors.
- **Resource safety:** request size, connection, batch, and memory caps;
  slow-query logging; no unbounded scans without limits.
- **Robustness:** fuzz gates (codecs, HTTP), soak, kill-matrix; every
  `Some`/`Ok` invariant checked in probes.
- **Supply chain:** pinned stdlib/packages, SBOM, signed commits,
  no secrets in-repo, release artifacts stamped.
- **XIOM safety story:** product code has no user-level `unsafe`;
  contracts encode invariants; document the guarantee in SECURITY.md.

## 7. Ecosystem integration map

| Ecosystem piece | How the flagship uses it | Lane action |
|---|---|---|
| compiler contracts | invariants on entry points; per-build numeric gates | relay findings; keep probes pinned |
| stdlib | io/os/hash/num; the durability primitives gate M-D5 | wishlist relays per pass |
| `xiom.wal` | single WAL home; codec alignment; crash probes contributed | adopt on publish (ops allowlist) |
| `xiom.vectors` / `xiom.ann` | porter extraction of this lane's reference implementation | on owner greenlight |
| `xiom.metrics` | O1 observability | adopt Phase 10 (now) |
| `xiom.http` / `xiom.router` / `xiom.rate` | server surface | adopt at S1/S3; fallback in-repo |
| bindings (blas/eigen) | optional SIMD acceleration behind the contract | watch; never required |

## 8. Risks and external gates

| Risk / gate | Impact | Mitigation |
|---|---|---|
| stdlib fsync/fd/append still stubs on 0.64.3 | D5 (true durability), truncate retention, KV/manifest backends | atomic checkpoint path ships now; re-check each pass; relay pressure; `xiom.wal` shares the gate |
| `xiom.http`/`xiom.metrics` maturity | S1/O1 may need in-repo fallback | facade-first design; adopt when the package proves itself |
| XIOM runtime concurrency model | P1 limits throughput story | design first; process-level model; publish honest numbers |
| compiler regressions on new archives | red builds | per-build numeric gates; re-test at every archive before pinning |
| benchmark fairness | credibility | publish methodology + raw JSON; deterministic seeds |
| single-lane bandwidth | long timeline | strict slice cadence; owner gates release only |
| security surface of a young HTTP stack | exposure | secure defaults, auth on, threat model, fuzz gates before release |

## 9. Definition of "public release ready" (what the lane delivers)

1. Suite + probes green x2 on Windows and WSL through `ci.ps1`/`ci.sh`.
2. Kill-matrix + snapshot/restore evidence committed.
3. Benchmark report (`docs/BENCHMARKS.md`) with methodology + raw JSON.
4. Security checklist + SBOM + `docs/SECURITY.md`.
5. Docs complete (README/quickstart/API/OPERATIONS/ARCHITECTURE) and
   release checklist filled; `VERSION` = `1.0.0-rc`.
6. Release candidate tagged; owner handoff note (repo/runners/rulesets/
   benchmark setup) -- **the lane stops and tells the owner**.

## 10. Cadence and reporting

- Work proceeds autonomously slice-by-slice under the lane's goal loop;
  each slice is committed signed with its probes/docs.
- Every wrap: SESSION.md STATE refreshed, readiness re-scored, lanes
  re-checked, relays updated.
- The lane reports to the owner at: (a) each milestone exit,
  (b) any new external gate, (c) the release-ready gate (R4).
