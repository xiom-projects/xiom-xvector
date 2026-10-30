<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVECTOR -- top-tier parity program (vision + method)

**Status:** vision locked; inventory v0 (seed). The unit-level counts are
provisional until the reference clones are frozen.
**As of:** 2026-10-30
**Owner:** xvector lane, with the owner signing the target and exclusions.

Related: [`PRODUCTION-READINESS.md`](PRODUCTION-READINESS.md) (the separate
v1 readiness score), [`WEBSITE-STATUS.md`](WEBSITE-STATUS.md) (public-safe
status), [`TOP-TIER-PARITY-MATRIX.md`](TOP-TIER-PARITY-MATRIX.md) (the
working unit matrix).

---

## 1. The vision

We do **not** compete on lines of code. We compete on **capability
coverage**.

For each frozen reference release `R`:

1. Enumerate every capability `R` exposes on the **package** surface
   (embedded library / SQL extension / local mode) and on the
   **standalone** surface (server, API, CLI, operations).
2. Give each capability a stable unit ID and a priority.
3. Match each unit in our package and/or standalone surface with the
   **same semantics**, backed by a test, probe, benchmark, or doc.
4. Report parity separately:
   - `P_pkg(R) = matched package units / X_pkg(R)`
   - `P_srv(R) = matched standalone units / X_srv(R)`
   - weighted with P0/P1/P2.
5. `100 %` means **every unit in the frozen inventory is matched on the
   surfaces where the reference exposes it** (or the owner has signed a
   written exclusion).
6. **Top-tier comparable** means, at minimum:
   - `>= 90 %` weighted P0+P1 parity on **both** surfaces for the selected
     references,
   - independent benchmark evidence on the same workload classes,
   - the operational/security controls in the P0/P1 set,
   - no excluded P0 unit that a buyer in the target segment would consider
     mandatory.

This is deliberately stricter than a feature checklist: a unit that is
"present" but cannot survive the reference's semantics (e.g. filtered
search, snapshot isolation, failover) is `Partial`, not `Have`.

---

## 2. Reference set

### Cloned and pinned on this host

| Reference | Surface | Pinned commit | Path | Why it is in the set |
|---|---|---|---|---|
| **FAISS** | package | `cec5702` (2026-10-10) | `E:\repos\faiss` | index families, quantization, GPU, serialization, clustering |
| **DiskANN** | package + disk/server-ish | `177c03b` (2026-10-09) | `E:\repos\DiskANN` | Vamana/DiskANN, in-memory + disk providers, streaming updates, filtered search |
| **sqlite-vec** | package | `04d28bd` (v0.1.10-alpha.4) | `E:\repos\sqlite-vec` | embedded SQL API, float/int8/binary vectors, metadata/auxiliary/partition columns |

### Standalone contestants (clones pending)

These are the server/standalone references to freeze next. The benchmark
harnesses below already carry clients for them, but a full source clone at
a pinned tag is required before their `X` is final.

| Reference | Surface | Current evidence source | Status |
|---|---|---|---|
| Qdrant | standalone | `ann-benchmarks` client, `vector-db-benchmark` client | clone/tag pending |
| Milvus | standalone | `ann-benchmarks` client, `VectorDBBench` client | clone/tag pending |
| Weaviate | standalone | `ann-benchmarks` client, `vector-db-benchmark` client | clone/tag pending |
| pgvector / pgvectorscale | package + Postgres standalone | `ann-benchmarks` clients | clone/tag pending |
| Vespa | standalone | `ann-benchmarks` client | clone/tag pending |
| Elasticsearch / OpenSearch | standalone | `ann-benchmarks`, `vector-db-benchmark` | optional, if in target segment |

### Benchmark evidence harnesses (cloned)

| Harness | Commit | Role |
|---|---|---|
| `ann-benchmarks` | `2e081ad` | recall/latency harness + contestant list |
| `VectorDBBench` | `139f8a3` | end-to-end vector DB benchmark |
| `vector-db-benchmark` | `acedefd` | engine/workload matrix (incl. parallel/tenant cases) |

**Rule:** freeze the exact commit/tag in this table before counting `X`.
A moving reference is not a parity target.

---

## 3. The unit schema

Each row in the matrix is one capability unit:

| Field | Meaning |
|---|---|
| `ID` | stable ID, e.g. `D2.IDX.IVF_PQ` |
| `Domain` | one of the 12 domains below |
| `Capability` | one sentence, testable |
| `Ref` | `P` package, `S` standalone, `B` both |
| `Source` | which reference(s) expose it (`FAISS`, `DiskANN`, `sqlite-vec`, `Qdrant`, ...) |
| `Priority` | `P0`, `P1`, `P2` (see rule below) |
| `xvector pkg` | `Have` / `Partial` / `Missing` / `Excluded` |
| `xvector srv` | `Have` / `Partial` / `Missing` / `Excluded` |
| `Evidence` | test/probe/benchmark/doc path; required for `Have` |
| `Gap / next` | concrete missing behavior and milestone |

**Priority rule (reference-driven, not taste):**

- `P0` = present in **>= 3** of the selected top-tier references, or
  mandatory for the target segment (owner may override in writing).
- `P1` = present in exactly **2** references.
- `P2` = present in **1** reference, or niche/optional.

**Matched rule:**

- `Have` = same semantics, plus evidence.
- `Partial` = implemented for a subset of the reference semantics; counts
  as `0.5` unless the owner defines a different fraction.
- `Missing` = not implemented.
- `Excluded` = owner-approved written exclusion with a reason; it is
  removed from `X`, not silently ignored.

---

## 4. Package vs standalone

The two scores are **never blended silently**:

- **Package parity** compares our embedded package surface
  (`xiom.vectors` / `xvector-mote`) with the package references (FAISS,
  DiskANN, sqlite-vec, pgvector's extension surface where applicable).
  A server-only feature does not count.
- **Standalone parity** compares `xvectord` + router/replica/CLI/ops with
  the server references (Qdrant, Milvus, Weaviate, Vespa, pgvector-as-
  service). A package-only feature does not count.
- A `Ref=B` unit must be matched on **both** surfaces to count for both.
- The final report is a table of `P_pkg` and `P_srv` per reference plus a
  composite with owner-set reference weights. No single "top-tier %" is
  quoted without that table.

---

## 5. The 12 domains and the seed inventory

The seed inventory currently enumerates **131 candidate units** across 12
domains. **118 are seeded in the working matrix**; the backlog in that file
lists the remaining expansion slots. This is the working `X` skeleton; the
freeze pass will confirm the per-reference `X_pkg` / `X_srv` and remove
units a reference does not expose.

| ID | Domain | Candidate units (seed) | What it covers |
|---|---|---:|---|
| D1 | Data model & vector types | 10 | float32/16, int8, binary, sparse, named/multi-vector, payload schemas, partition/auxiliary/tenant columns |
| D2 | Index families | 14 | Flat, HNSW, IVF-Flat, IVF-PQ, PQ/OPQ, SQ, DiskANN/Vamana, GPU, binary, sparse, full-text, multi-vector, mmap/disk, filter-aware |
| D3 | Search & query | 14 | KNN, range, batch, pagination, score thresholds, named-vector, hybrid, rerank, recommend/discover, group-by/diversity, aggregations, scroll/export, per-query params |
| D4 | Filtering & metadata | 6 | equality/range/in/not, nested/array/geo, full-text filter, filter-aware index, payload indexes, partition pruning |
| D5 | Persistence & durability | 12 | WAL/fsync, checkpoints, snapshots, backup/restore, PITR, compaction, crash recovery, mmap segments, replication log, object-store tiering, schema migrations, import/export |
| D6 | Concurrency & consistency | 9 | thread-safe reads/writes, MVCC/read snapshots, snapshot isolation, linearizable writes, read-your-writes, optimistic versioning, transactions, graceful shutdown, backpressure |
| D7 | Distribution & scale | 11 | sharding, replication, consensus, resharding/rebalance, multi-node routing, multi-region, tenant isolation, billion-scale disk index, failover/promotion, cluster membership |
| D8 | Ingestion & lifecycle | 11 | upsert, delete, delete-by-filter, batch, streaming, tombstones/updates, TTL, collections/aliases, schema evolution, compaction policy, unload/idle |
| D9 | Observability & ops | 11 | metrics, structured logs, OTLP tracing, health/readiness, dashboards/alerts, slow-query log, stats/introspection, backup automation, rolling upgrades, config validation, CLI/admin API |
| D10 | Security & governance | 11 | API keys, RBAC/scopes, TLS, encryption at rest, audit log, secrets/rotation, rate limits, quotas, multi-tenancy, compliance, supply-chain/SBOM |
| D11 | Interfaces & ecosystem | 12 | embedded API, REST, gRPC, GraphQL, SQL, Python/Rust/Go/JS SDKs, LangChain/LlamaIndex, SQLite ext, Kafka/CDC, K8s operator/Helm, cloud control plane |
| D12 | Benchmarks & evidence | 10 | recall/latency/QPS, ANN-Benchmarks, VectorDBBench, billion-scale, independent third-party, chaos, load/soak, upgrade tests, security audit, reproducible artifacts |

The unit-level working table lives in
[`TOP-TIER-PARITY-MATRIX.md`](TOP-TIER-PARITY-MATRIX.md). The first row
set is seeded; the freeze pass fills every unit and links evidence.

---

## 6. Current honest position (do not blend denominators)

| Measure | Current value | Denominator |
|---|---|---|
| v1 production readiness | **91 %** | our own A-J v1 plan (`PRODUCTION-READINESS.md`) |
| Package parity | **not frozen** | FAISS/DiskANN/sqlite-vec units after the freeze |
| Standalone parity | **not frozen** | Qdrant/Milvus/Weaviate/Vespa units after the freeze |
| Top-tier comparable | **not yet claimed** | requires >= 90 % weighted P0+P1 both surfaces + external evidence |

Seed status snapshots (to be replaced by the matrix counts):

- **Strong:** Float32, Flat, HNSW, payload filters, range/pagination/batch,
  WAL/checkpoints/snapshots/sealed segments, crash recovery, async
  replicas, router, hash-split sharding, move/drain, metrics/logs,
  API-key scopes, rate limiting, read-only UI.
- **Partial:** SQ (SQ8 only), on-disk vs mmap, backup/restore (manual
  snapshots, no PITR), RBAC (scopes only), rate/quotas (rate only),
  resharding (move/drain only), failover (manual promotion), chaos
  (kill matrix only), benchmarks (internal only).
- **Missing:** float16, int8, binary, sparse, named/multi-vector, IVF/PQ/
  OPQ, DiskANN/disk index, GPU, hybrid/full-text, recommend/discover,
  group-by/diversity, aggregations, PITR, object-store tiering, MVCC/
  read snapshots, transactions, consensus, automatic rebalance,
  multi-region, TTL/aliases/schema evolution, streaming ingest, OTLP,
  backup automation, rolling upgrades, TLS, encryption at rest, audit,
  quotas, multi-tenancy, gRPC/GraphQL/SQL, SDKs, K8s/cloud, ANN-Benchmarks/
  VectorDBBench, billion-scale/independent benchmarks, security audit.

This is exactly why the 91 % v1 number is not a top-tier claim: the v1
plan deliberately covers a focused product, while the parity program
covers the market surface.

---

## 7. Milestones

### M0 -- Freeze the references (inventory)
- Clone/pin Qdrant, Milvus, Weaviate, pgvector/pgvectorscale, Vespa at
  exact tags; record commits/versions here.
- Harvest their package and standalone surfaces into the matrix.
- Replace the 131 candidate units with `X_pkg` and `X_srv` per reference.
- Owner signs the target and any exclusions.
- **Exit:** matrix frozen; no parity percentage is quoted before this.

### M1 -- P0 parity (credible top-tier core)
- Close the P0 units: read snapshots/MVCC, SIGPIPE-on-disconnect, TLS/
  auth/RBAC basics, backup/restore, index/vector gaps that are P0 by the
  reference rule, SDK/REST completeness, independent benchmark harness.
- Both surfaces; evidence per unit.
- **Exit:** >= 90 % weighted P0 parity on both surfaces for the selected
  references; external benchmark run published.

### M2 -- P1 parity (platform)
- IVF/PQ/OPQ, DiskANN/disk, int8/binary, sparse/hybrid, rerank,
  multi-tenancy, RBAC, resharding/consensus, gRPC/SDKs, observability,
  object-store tiering.
- **Exit:** >= 90 % weighted P0+P1 on both surfaces; chaos/upgrade tests.

### M3 -- P2 / ecosystem
- GPU, multi-region, cloud control plane, compliance, integrations,
  community, niche capabilities.
- **Exit:** full `X` matched or owner-approved exclusions; independent
  audit/benchmarks.

---

## 8. Governance

- **No LOC KPI.** LOC is context, not a target.
- **No "Have" without evidence.** A unit is only `Have` when a test,
  probe, benchmark, or documented run proves the same semantics.
- **Freeze before counting.** Reference commits/tags are part of the
  matrix; moving targets invalidate the score.
- **Separate reports.** v1 readiness, package parity, standalone parity,
  and top-tier gate are reported separately; never merge them into one
  marketing number.
- **Owner signs exclusions.** A `100 %` claim means all units matched or
  written exclusions; otherwise report the exact matched/X.
- **Update per release.** Each accepted toolchain/release updates the
  matrix and the parity delta; stale matrices are marked stale.

---

## 9. Immediate next actions

1. **Freeze the standalone references:** clone/tag Qdrant, Milvus,
   Weaviate, pgvector/pgvectorscale, Vespa; record versions in section 2.
2. **Build the full matrix:** one row per unit in
   `TOP-TIER-PARITY-MATRIX.md`; start with FAISS/DiskANN/sqlite-vec
   package units, then the standalone servers.
3. **Owner decision:** target 100 % of all units, or >= 90 % weighted
   P0+P1 with written P2 exclusions. The vision supports both; the
   difference must be explicit.
4. **Wire the matrix into the release checklist:** no parity claim in
   release notes/website without the matrix row and evidence.
5. **Keep the website honest:** "release-grade v1, 91 % v1 readiness" is
   current; "top-tier comparable" is a parity-program milestone, not a
   present-tense claim.
