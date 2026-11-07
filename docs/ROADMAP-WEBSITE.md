<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVECTOR -- public roadmap to production-grade Tier-X

**As of:** 2026-11-02
**Owner:** xvector lane
**Purpose:** the website lane's single source for the phase timeline, status
badges, and the honest path from the working engine to **Tier-X**
(production-grade, top-tier comparable).

**Public-safe.** No internal bus IDs, defect IDs, private commit hashes, or
unreleased claims. The internal detail lives in
[`PRODUCTION-READINESS.md`](PRODUCTION-READINESS.md),
[`TOP-TIER-PARITY.md`](TOP-TIER-PARITY.md), and
[`TOP-TIER-PARITY-MATRIX.md`](TOP-TIER-PARITY-MATRIX.md).

---

## 1. The vision in one paragraph

XVECTOR is **one engine, one on-disk format, two deployment shapes**:
**xvector-mote** (embedded package) and **xvector-lattice** (served daemon +
router/replicas/scatter-gather). The destination is **Tier-X**: a
production-grade vector database that is not judged by lines of code, but by
**capability parity** with the best reference projects on both the package and
standalone surfaces -- proven with tests, benchmarks, and operational
evidence.

"Tier-X" is a **proof gate**, not a launch date. It is reached when the v1
production gates are complete **and** the parity gate is met with external
evidence.

---

## 2. Status at a glance

| Item | Current |
|---|---|
| Project | **`v1.0.0-rc.1`** (private candidate; public release owner-gated) |
| Internal v1 readiness | **91 %** weighted (release-grade) |
| Accepted toolchain | **v0.65.7** (published 2026-11-07; Windows + WSL batteries green) |
| Verification | suite **177/177** x2, **58 probes x2** on Windows + WSL, libcheck 49/49, SBOM 49/0 |
| Product shape | mote package + lattice daemon/router/replicas/scatter-gather + read-only `/ui` |
| Next engineering | **G-3 read snapshots**, then scale tuning |
| Next product program | **Parity M0**: freeze the reference capability inventories |

**Two different percentages, never blended:**

- **91 %** = progress against our own v1 A-J plan.
- **Parity %** = matched capability units / a frozen reference's units, per
  package and standalone surface. It is not yet frozen; no top-tier
  percentage is claimed before M0.

---

## 3. What "production-grade Tier-X" means

Tier-X is reached only when **all** of these are true:

1. **v1 gates complete** with evidence (the A-J scorecard at the release
   threshold; no open P0).
2. **Package parity** >= 90 % weighted P0+P1 against the frozen package
   references (FAISS, DiskANN, sqlite-vec, and the embedded surfaces of the
   server references where they expose one).
3. **Standalone parity** >= 90 % weighted P0+P1 against the frozen server
   references (Qdrant, Milvus, Weaviate, pgvector/pgvectorscale, Vespa).
4. **P0 operations/security** present: TLS, encryption at rest, RBAC,
   backup/restore, audit, multi-tenancy boundaries, quotas.
5. **External evidence**: independent benchmark results at meaningful scale
   (10M-1B), chaos/upgrade tests, and a security review.
6. **Public release** owner-greenlit (or the owner explicitly accepts the
   remaining written exclusions).

A full `100 %` parity with every P2 unit is **not** required for Tier-X; the
owner signs the target and any exclusions. Without that signature, 100 %
means every unit matched.

---

## 4. The timeline

Dates are windows for completed phases; future phases are **gate-ordered**,
not date-promised.

| Phase | Window | Status | What it delivered / will deliver |
|---|---|---|---|
| 0. Exact engine | 2026-07/08 | **Done** | dense vectors, three metrics, Flat exact search, top-k/range oracle |
| 1. HNSW ANN | 2026-08/09 | **Done** | multi-layer HNSW, recall harness, codec, compaction |
| 2. Durability | 2026-09 | **Done** | WAL-before-ack, checkpoints, snapshots, sealed segments, crash recovery |
| 3. Payload & query surface | 2026-09 | **Done** | typed payloads, filters/planner, range, pagination, batch, delete-by-filter |
| 4. Serving & scale-out | 2026-10 | **Done** | `xvectord`, auth/limits, metrics, router v1, replicas, move/drain, L-6 scatter-gather |
| 5. Concurrency & observability | 2026-10 | **Done** | G-1 threads/sync, G-2 threaded accept loop, G-4 atomic metrics + ordered log ring |
| 6. Packaging & station UI | 2026-10 | **Done** | `xiom.vectors` 0.2.0 package, mote/lattice split, read-only `/ui` |
| 7. v1 release candidate | 2026-10 | **Done** | `v1.0.0-rc.1`, readiness 91 %, full batteries, operator docs |
| 8. Toolchain hardening | 2026-10/11 | **Current** | v0.65.x acceptance; WAL/struct-push and SIGPIPE fixes; reproducible pins |
| 9. Read snapshots & scale | Next | **Next** | G-3 MVCC/read snapshots, concurrent readers, scale tuning |
| 10. Parity M0 | Next | **Next** | freeze reference clones/units; publish the capability inventory |
| 11. Parity M1 (P0) | After M0 | **Planned** | P0 parity on both surfaces: read snapshots, TLS/RBAC/encryption, backup/PITR, index/vector/API gaps, independent benchmark harness |
| 12. Parity M2 (P1) | After M1 | **Planned** | IVF/PQ/DiskANN, int8/binary, sparse/hybrid/rerank, multi-tenancy, consensus/resharding, gRPC/SDKs, observability, object-store tiering |
| 13. Parity M3 (P2) | After M2 | **Planned** | GPU, multi-region, cloud control plane, compliance, ecosystem integrations, community |
| 14. **Tier-X gate** | After M3/M1+M2 | **Vision** | >=90 % weighted P0+P1 both surfaces + external benchmarks/audit + owner greenlight |

---

## 5. Phase details (website cards)

### Phase 0 -- Exact engine (Done)
Correctness foundation: dense vectors, cosine/dot/Euclidean, exact Flat
search, range search, bounded top-k. This remains the oracle every ANN path
is tested against.

### Phase 1 -- HNSW ANN (Done)
Sub-linear search with a multi-layer graph, recall harness, codec and
compaction. Exact Flat is still the correctness baseline.

### Phase 2 -- Durability (Done)
WAL-before-ack, atomic checkpoints, snapshots, sealed segments, torn-tail
loaders, kill/reopen recovery. Durable mode is opt-in on the server; the
embedded engine persists through checkpoints.

### Phase 3 -- Payload and query surface (Done)
Typed payload storage, equality/range/in/not filters, filter planner,
range search, offset/cursor pagination, batch upsert/search/delete,
delete-by-filter, multi-collection.

### Phase 4 -- Serving and scale-out (Done)
`xvectord` HTTP tier with auth scopes, rate limits, metrics/logs; stateless
router; async replicas; online move/drain; intra-collection hash
scatter-gather (L-6). Shards remain single-writer per home; no consensus or
automatic rebalance yet.

### Phase 5 -- Concurrency and observability (Done)
G-1 cross-thread sync, G-2 threaded accept loop (`XVECTORD_THREADS`), G-4
atomic counters + shared-state `/metrics` + wall-clock-ordered log ring.
**G-3 read snapshots are the next concurrency slice.**

### Phase 6 -- Packaging and station UI (Done)
`xiom.vectors` 0.2.0 embedded package; mote/lattice product split;
read-only web admin at `/ui` (sample scatter, inspector, hit highlighting).

### Phase 7 -- v1 release candidate (Done)
`v1.0.0-rc.1` froze the v1 scope: 177/177 suite x2, 58 probes x2, libcheck
49/49, SBOM 49/0, bench + kill matrix. Honest limits documented.

### Phase 8 -- Toolchain hardening (Done)
Latest-toolchain protocol: SHA-verified archives, lane-local pins, repros
for every fixed defect, full batteries per archive. The v0.65.7 line is
accepted with both platform batteries green; recent releases fixed the
named-struct/WAL regression and the Linux SIGPIPE-on-disconnect issue.

### Phase 9 -- Read snapshots and scale (Next)
G-3: MVCC/read snapshots so readers do not block writers; then scale
tuning (larger collections, cache behavior, shard sizing, benchmark
envelopes). This is the last major v1 concurrency gap.

### Phase 10 -- Parity M0 (Next)
Freeze the reference clones at exact tags/commits; enumerate package and
standalone capabilities; replace candidate counts with `X_pkg`/`X_srv`;
owner signs the target and exclusions. **No parity percentage is quoted
before this freeze.**

### Phase 11 -- Parity M1 / P0 (Planned)
Close the P0 units on both surfaces: read snapshots, TLS, RBAC/encryption,
backup/restore/PITR, the P0 index/vector/API gaps, a reproducible
independent benchmark harness. Exit: >=90 % weighted P0 parity + external
benchmark run.

### Phase 12 -- Parity M2 / P1 (Planned)
IVF/PQ/OPQ, DiskANN/disk index, int8/binary, sparse/hybrid/rerank,
multi-tenancy, consensus/resharding, gRPC/SDKs, observability depth,
object-store tiering. Exit: >=90 % weighted P0+P1 both surfaces +
chaos/upgrade tests.

### Phase 13 -- Parity M3 / P2 (Planned)
GPU, multi-region, cloud control plane, compliance, ecosystem integrations,
community. Exit: full `X` matched or owner-approved written exclusions.

### Phase 14 -- Tier-X gate (Vision)
The production-grade, top-tier claim: parity gate + external evidence +
security/ops + public release greenlight. Until this card is green, the
website must not say "top-tier comparable".

---

## 6. What the website should show

Recommended layout: a **vertical timeline** with phase cards and three
badges: **Done**, **Now**, **Next**. Add a final **Tier-X** card that is
visually distinct (not "done").

Use these badges/labels:

- `v1.0.0-rc.1` Â· **release-grade, 91 % internal readiness**
- **Toolchain:** v0.65.7 accepted
- **58 probes x2 Â· 177/177 suite x2 Â· Windows + Linux/WSL**
- **Now:** G-3 read snapshots + parity M0
- **Next:** P0 parity, then P1, then P2
- **Tier-X:** proof gate, not a date

Suggested page sections:

1. **Hero:** "One engine. Two shapes. One proof gate."
2. **Timeline:** Phases 0-14 with status.
3. **What is live today:** mote/lattice feature bullets.
4. **The Tier-X gate:** the six conditions from section 3.
5. **Honest limits:** the list in section 7.
6. **CTA:** read the engineering docs / release notes (owner-gated links).

---

## 7. Do not claim yet

- **"Top-tier comparable"** or "beats Qdrant/Milvus" before the Tier-X gate.
- **"100 % production-ready"**; current wording is **release-grade, 91 % v1**.
- **Read snapshots / non-blocking readers** (G-3 not done).
- **TLS / encryption at rest / RBAC / multi-tenancy / audit** as shipped.
- **IVF/PQ, DiskANN, GPU, sparse/hybrid/full-text, rerank** as shipped.
- **mmap-backed storage** (P5 pending).
- **Consensus, automatic rebalance, multi-region, cloud control plane**.
- **SDKs beyond the XIOM package**, LangChain/LlamaIndex, gRPC/GraphQL/SQL.
- **Independent billion-scale benchmark** results or third-party audits.
- **arm64** for xvector; verified platforms are Windows x64 + Linux x64.
- A public xvector GitHub release/download link before owner greenlight.

---

## 8. How progress is measured

- **v1 readiness:** weighted A-J scorecard, updated every wrap; 91 % today.
- **Package parity:** matched package units / `X_pkg` of frozen references.
- **Standalone parity:** matched standalone units / `X_srv`.
- **Priority weights:** P0=3, P1=2, P2=1; `Partial` counts 0.5 until the
  owner sets a fraction.
- **Evidence rule:** no `Have` without a test/probe/benchmark/doc.
- **No LOC KPI.**

The parity matrix is the working measurement:
[`TOP-TIER-PARITY-MATRIX.md`](TOP-TIER-PARITY-MATRIX.md).

---

## 9. Risks and dependencies

- **Release cadence:** the toolchain line (v0.65.x) must stay green; a
  regression holds the pin and the phase.
- **G-3 design:** read snapshots depend on runtime Send/Sync and a snapshot
  handle; it is design-gated, not just coding work.
- **Reference freeze:** M0 requires cloning/pinning the standalone
  references; until then, standalone parity is provisional.
- **External evidence:** independent benchmarks/audits are outside the
  engineering lane; Tier-X cannot close without them.
- **Owner gates:** public release and ann-swap greenlights are owner actions.

---

## 10. When to refresh this roadmap

- A new accepted toolchain release (update the badge/pin).
- G-3 lands (move Phase 9 to Done, Phase 10/11 sequencing).
- M0 freezes the references (replace provisional counts with `X_pkg`/`X_srv`).
- A parity milestone closes (M1/M2/M3).
- The public release is greenlit (remove the private/owner-gated caveat).
- Readiness changes by more than ~2 points or a phase changes level.

**Source of truth:** [`WEBSITE-STATUS.md`](WEBSITE-STATUS.md) for current
public facts; [`PRODUCTION-READINESS.md`](PRODUCTION-READINESS.md) for v1
measurement; [`TOP-TIER-PARITY.md`](TOP-TIER-PARITY.md) for the Tier-X
method. This roadmap is the narrative layer over those documents.
