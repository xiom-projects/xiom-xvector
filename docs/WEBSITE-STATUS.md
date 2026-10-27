<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVECTOR -- status brief for the website lane

**As of:** 2026-10-27 (after the v0.65.1 acceptance pass)
**Owner:** xvector lane
**Purpose:** one public-safe source for the website copy, feature matrix, install
pins, and "do not claim" boundaries. Internal evidence is labelled; do not paste
the internal-only sections into public pages.

**Source of truth:** [`PRODUCTION-READINESS.md`](PRODUCTION-READINESS.md) (scores
and evidence), [`RELEASE-NOTES-v1.0.0-rc.1.md`](RELEASE-NOTES-v1.0.0-rc.1.md)
(what the candidate contains), [`OPERATIONS.md`](OPERATIONS.md) (deployment and
limits), [`PRODUCT-LAYERS.md`](PRODUCT-LAYERS.md) (mote/lattice naming),
[`SESSION.md`](../SESSION.md) section 25 (latest engineering pass).

---

## 1. Headline

**xiom-vector is a production-grade vector database for the XIOM ecosystem:**
exact Flat and HNSW search, the three distance metrics, typed payload filters,
WAL-backed durability, sealed segments and snapshots, and a served HTTP tier --
in one engine and one on-disk format.

**Current project status:** `v1.0.0-rc.1` (release candidate, private repository;
public release is owner-gated), internal readiness **91 %**, accepted toolchain
**compiler v0.65.1 + stdlib-v0.65.1**.

Two shapes of the same engine:

- **xvector-mote** -- embedded library / registry package (`xiom.vectors 0.2.0`);
  no socket, no daemon.
- **xvector-lattice** -- served daemon `xvectord` plus stateless router,
  replicas, move/drain, and intra-collection scatter-gather.

Same `src/` tree, same on-disk format, same numeric results. Develop embedded,
deploy served, no migration.

---

## 2. Facts the website must get right

| Item | Current value | Notes |
|---|---|---|
| Project version | **`v1.0.0-rc.1`** | Local candidate tag `530b041`; repository is private |
| Accepted compiler | **v0.65.1** | Released 2026-10-26; GitHub release `40388025015` |
| Standard library | **stdlib-v0.65.1** | Tag commit `9dc69b3` |
| Latest stable compiler | **v0.65.1** | v0.64.9 is **withdrawn**; v0.65.0 is superseded |
| Rollback pins | v0.64.8 + stdlib `750384f` | Kept for rollback; do not advertise as latest |
| Internal readiness | **91 %** (weighted) | "Release-grade"; not "100 % production" |
| Verified platforms | **Windows x64 + Linux x64** | Full batteries on both; WSL is the Linux test host |
| Release ownership | mote = registry package; lattice = ops-owned release set | xvector GitHub release is owner-gated while the repo is private |

**Do not confuse the two version lines on the site:** `v1.0.0-rc.1` is the
xiom-vector project. `v0.65.1` is the XIOM compiler/toolchain that builds it.
Do not label the xvector product "v0.65.1".

---

## 3. What is live and verified

### Embedded (xvector-mote)

- Exact Flat search with cosine, dot-product, and Euclidean metrics.
- Hardened HNSW ANN: multi-layer graph, tombstones, codec, recall harness,
  compaction.
- Typed payload storage and filtering, sorted key index, pre/post planner.
- Range search, stable offset and after-id pagination, batch upsert/search/
  delete, delete-by-filter.
- Multi-collection registry and routed recovery.
- WAL-backed durability: fsync-on-ack delta segment, atomic checkpoints,
  durable manifest, kill-recovery replay, torn-tail loaders.
- Sealed segments with roll/union reads, tombstone shadowing, bit-exact
  compaction; snapshots.
- Opt-in SQ8 quantization with exact f32 rescore; sealed Flat rescore is
  bit-identical to exact on the gated queries.
- Registry package surface: `xiom.vectors 0.2.0`.

### Served (xvector-lattice)

- `xvectord`: byte-level HTTP/1.1 server -- `/health`, `/collections`, points
  CRUD, `/search`, `/stats`, `/metrics`, `/ui`.
- API-key auth with read/write/admin scopes, request limits, token-bucket rate
  limiting, strict error envelope, JSON depth guard.
- Observability: Prometheus text metrics, atomic counters under threads,
  histograms, bounded wall-clock-ordered JSON log ring.
- Durable modes via `XVECTORD_WAL` (delta segment + checkpoint/seal policies);
  without it the daemon is in-memory (no durability claim).
- Stateless router v1: versioned mapping file, strict loader, retry-on-404
  stale-mapping recovery, cluster health/stats.
- Async replicas (file-ship catch-up, manual promotion, `replica_lag`).
- Online collection move + drain, compaction-aware, gated under load.
- Intra-collection scatter-gather (L-6 phase B): hash-split collections,
  fan-out writes, exact merged reads, partial-failure reporting. **Post-rc.1**
  (current main); the `v1.0.0-rc.1` tag predates it.
- Read-only web admin at `/ui`: sampled 2D vector scatter, point inspector,
  search hit highlighting. Canvas 2D; no editor yet.

### Verification evidence (internal; use numbers only if owner approves)

- Conformance suite **177/177**, x2 on Windows and x2 on WSL.
- **58 probes x2** on Windows and x2 on WSL; bench smoke + durability kill
  matrix.
- Library type-check **49/49**; SBOM **49 modules, `unsafe` = 0**.
- v0.65.1 acceptance: release-mode enum-payload read (1615/1243), second
  PQ-train return (C-22), 16 GB Job Object build (C-21/1531), HTTP/L-6
  regressions (1640/1702), and L-6 scatter-gather all green.
- Correctness guard: a binary is trusted only after its own numeric assertions
  pass (the XVC-C-05/06 class); the Float64 reference oracle cross-checks
  ranked/paged/cursor/range/HNSW paths.

---

## 4. Honest limitations -- do not overclaim

| Area | Public-safe statement |
|---|---|
| Readiness | **"Release-grade, 91 % internal readiness"**, not "100 % production-ready". |
| Concurrency | Threaded path is flag-gated (`XVECTORD_THREADS`, default sequential); engine calls serialize on one coarse mutex; **G-3 read snapshots are future work**. Do not claim multi-writer or non-blocking readers. |
| Security | **No built-in TLS and no encryption at rest.** Deploy behind TLS/proxy and encrypt storage at the deployment layer. Auth and rate limiting are built in. |
| Admin UI | Read-only MVP, active-store sample only (sealed segments not included), Canvas 2D, no editor. |
| IVF/PQ | **Not shipped.** P4 is experimental; the nested-codebook arm is being re-run. Do not advertise IVF/PQ. |
| mmap / P5 | Pending (memory-mapped disk segments are future work). Do not claim mmap-backed storage. |
| Platforms | Windows x64 and Linux x64 are verified. **Do not claim arm64** for xvector. No GPU/SIMD-accelerated binding is shipped. |
| Durability | Opt-in (`XVECTORD_WAL`). Without it, the daemon is in-memory. |
| Scale | Router/replicas/move-drain and scatter-gather are live, but shards are single-writer per home. Do not claim linear scalability or multi-writer shards. |
| Release state | Repository private; public GitHub release is **owner-gated**. Do not publish a public download link before the owner greenlights it. |

### rc.1 tag vs current main

The `v1.0.0-rc.1` tag is the frozen candidate. **Current main is ahead** and
includes post-rc.1 work (G-4 observability, L-6 phase B, v0.65.1 acceptance).
If a page describes "the rc.1 artifact", say that these slices are post-rc.1.
If it describes "current main", they are included.

---

## 5. Website changes to make now

1. **Remove the v0.64.9 HELD banner.** v0.65.1 is the accepted production
   toolchain (released 2026-10-26). v0.64.9 stays withdrawn; v0.65.0 is
   superseded.
2. **Update install pins** on download/install pages:
   - compiler: `--version v0.65.1`
   - stdlib: `stdlib-v0.65.1`
   - rollback: `v0.64.8` + stdlib `750384f`
   - Do not present v0.64.9 or v0.65.0 as current.
3. **Keep the product version distinct:** xvector is `v1.0.0-rc.1`; the
   toolchain is v0.65.1.
4. **Refresh the feature matrix** to include: L-6 intra-collection
   scatter-gather (post-rc.1), router/replicas/move-drain, auth scopes + rate
   limiting, `/metrics` + ordered log ring, read-only `/ui`.
5. **Use the honest status wording:** "release-grade, 91 % internal
   readiness", not "full production". Put TLS/encryption-at-rest and
   read-snapshot limitations in the operations/security notes.
6. **Link to the current public artifacts only after owner greenlight:**
   release notes, docs, and the v0.65.1 toolchain release. The xvector GitHub
   release remains owner-gated.
7. **Fix the "latest stable" label:** v0.65.1 is latest stable; v0.64.9 is
   withdrawn; v0.64.8 is rollback-only.

---

## 6. Suggested public copy

### Hero

> **xiom-vector** -- a durable vector database for the XIOM ecosystem.
> Exact Flat and HNSW search, typed filters, WAL-backed durability, and a
> served HTTP tier in one engine and one on-disk format.

### Subhead

> Develop embedded with **xvector-mote**. Deploy scale-out with
> **xvector-lattice**. Same engine, same format, same results -- no migration.

### Status badge (only if the owner wants the readiness metric public)

> `v1.0.0-rc.1` · release-grade · 91 % internal readiness

### Three feature bullets

- **Search the way you need.** Exact Flat or HNSW ANN, cosine/dot/Euclidean,
  filtered search, range queries, stable pagination, and batch operations.
- **Durable by design.** WAL-before-ack, atomic checkpoints, sealed segments,
  snapshots, and kill-recovery gates; opt in to fsync-on-ack for the served
  tier.
- **One engine, two shapes.** Embed the library or run `xvectord` with a
  stateless router, replicas, move/drain, and intra-collection scatter-gather.

### Short paragraph for a product page

> xiom-vector is the vector database layer of the XIOM ecosystem. It combines
> exact and approximate search with typed payload filtering, a durable
> write-ahead log, sealed segment files, and a transport-agnostic HTTP service
> with authentication, rate limiting, and metrics. The same engine runs
> embedded as xvector-mote and served as xvector-lattice, so an application can
> start in-process and scale out without changing its data format or query
> semantics.

---

## 7. Do not publish

- Internal lane names, relay item IDs (`REL-...`), private-repository hashes, or
  the internal defect register (`XVC-...`).
- Exact readiness sub-scores unless the owner approves; the 91 % headline is
  the agreed summary.
- Claims of 100 % production readiness, multi-writer shards, non-blocking read
  snapshots, TLS/encryption at rest, IVF/PQ, mmap storage, GPU/SIMD kernels, or
  arm64 support.
- A public xvector GitHub release link before the owner greenlights it.
- Customer logos, benchmarks, or SLAs that are not in `docs/BENCHMARKS.md` and
  approved by the owner.

---

## 8. When to refresh this brief

Refresh and re-relay when any of these happen:

- G-3 read snapshots lands (concurrency claim changes).
- P4 IVF/PQ ships (feature matrix changes).
- P5 mmap lands or the kernel binding ships.
- A new compiler/stdlib release is accepted (pins and release status).
- The owner greenlights the public xvector GitHub release (remove the
  "private/owner-gated" caveat and add links).
- Readiness moves by more than ~2 points or a phase changes level.

**Contact:** xvector lane via the relay bus (`to: xvector`).

---

## 9. Change log of this brief

- **2026-10-27** -- created after the v0.65.1 acceptance pass. Project
  `v1.0.0-rc.1`, compiler v0.65.1, stdlib-v0.65.1, readiness 91 %, full
  Windows + WSL batteries green; G-3/P4/P5 still outstanding.
