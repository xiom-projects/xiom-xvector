<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Package wishlist from the XVECTOR lane

Proposals and adoption notes from the xiom-xvector lane (vector database).
Checked against the packages-lane tree (`E:\xiom-packages\packages\packages`,
~380 packages) so nothing here duplicates an existing name. Format:
`| Proposed name | Purpose | Why not stdlib | Deps | Evidence |`.

Registry consumption note (C-PULSE-02, still open on v0.64.0): installing a
package is not enough -- the compiler needs each package's `src/` in
`xiom.toml` `[project].source-roots`. XVECTOR has none yet; the first
adoption below will wire the first source-root.

## Proposed packages

| Proposed name | Purpose | Why not stdlib | Deps | Evidence |
|---|---|---|---|---|
| `xiom.vectors` | Shared dense-vector primitives for XIOM vector engines: `Vector` (Vec[Float32] + dim), distance metrics (cosine/dot/L2), normalization, bounded top-K heap, and the WAL codec (`[dim, f32-bits...]`) with recovery replay. The portable pure-XIOM baseline under any SIMD/BLAS binding. | Domain layer that changes with index/quantization research (IVF/PQ, fusion scoring); stdlib keeps a minimal surface; two XIOM products need the same types. | stdlib (`xiom.math`, `xiom.num.float`) | Duplication between **xvector** and **orbitdb** (both implement vector math + metrics + top-K); xvector's `src\engine.xi` has a complete reference implementation (dedup `vector_dot`/`cosine_distance`/`euclidean_distance`/`VectorIndex`/`TopKHeap`) with 136 conformance checks; coordinate with orbitdb before extracting. |
| `xiom.wal` | Shared write-ahead log: append-only segment files, CRC-framed records (`xiom.hash.crc32_ieee`), LSN assignment, replay/recovery with torn-tail tolerance, checkpoint/truncation, fsync hooks. | Durability is a systems concern reused by every engine (xvector, orbitdb, PULSE's JSONL store); stdlib correctly excludes file-format policy. | stdlib (`xiom.io`, `xiom.hash`, `xiom.os` once fd syscalls land) | xvector ROADMAP Phase 2 implements an in-memory WAL inline (`src\engine.xi`: `wal_writer_append_payload`, `recover_store`, `wal_writer_checkpoint_from`); PULSE ships an append-only JSONL event store with torn-line healing; both would consume one format. Note: `xiom-durable` is incubating/unpublished and covers foundation types, not a WAL -- coordinate scope with the packages lane. |
| `xiom.ann` | Approximate nearest-neighbour indexes: flat exact scan, HNSW graph (build/search/tombstones), recall harness against the exact oracle. | Index parameters and algorithms evolve fast; stdlib should not freeze an ANN API. | `xiom.vectors` | xvector ROADMAP Phases 1/4 (HNSW is implemented in-memory; hardened recall/tuning pending); orbitdb needs the same index layer; extract after xvector's HNSW hardening lands (avoid freezing a half-tuned graph). |

## Adoption notes (existing registry packages)

| Package | Status for XVECTOR | Evidence | Blocked by |
|---|---|---|---|
| `xiom.metrics` 0.2.0 | **Planned** for Phase 10 observability (latency/recall histograms). | PULSE adopted it 2026-10-07 (labeled counters + latency preset + exposition); XVECTOR currently has an inline `Counter` only. | nothing intrinsic; adopt when the first metric surface lands (Phase 10), wire `source-roots` per C-PULSE-02 |
| `xiom.kv` 0.1.0 | **Candidate** segment metadata / manifest store; **not adopted now**. | PULSE: `kv_get` returns address-like Str on WSL Linux v0.64.0 (C-PULSE-10; Windows green); packages-lane probe `probe_kv_get_str.xi` green on Windows. XVECTOR additionally needs fsync before any KV store can back a durable manifest. | C-PULSE-10 (Linux `kv_get`) + the stdlib fsync gap (`STDLIB-WISHLIST-XVECTOR.md`) |
| `xiom-blas` / `xiom-eigen` / `xiom-openblas` | **Watch** for the Phase 10 SIMD/kernel path; the portable `xiom.vectors` API stays the contract, bindings are drop-in accelerators. | Packages lane FFI/bindings status (bindings worktree); xvector `distance/` is the future call-site seam. | not scheduled (Phase 9/10); needs the bindings-lane worktree |
| `xiom.simd`-class (no exact name found) | If a pure-XIOM SIMD/vector intrinsic package appears, XVECTOR will adopt it for distance kernels; if not, `xiom.ann`/`xiom.vectors` kernels stay scalar. | `xiom-blas`/`xiom-openblas` are bindings, not pure-XIOM kernels; no `xiom-simd` in the tree. | future; coordinate with packages lane before proposing a second kernel package |

## Bindings lane reply (2026-10-08, relayed via packages)

The bindings lane answered the kernel questions above:

- `xiom-blas` / `xiom-eigen` / `xiom-openblas` are **pre-rostered incubating
  placeholders in the bindings worktree** -- stub code, no tests, no promised
  timeline. When built they are **opt-in FFI accelerators that mirror the
  portable `xiom.vectors` contract, never define it** (matches our design:
  `xiom.vectors` is the contract, bindings are drop-in accelerators).
- The bindings lane plans **no pure-XIOM SIMD kernel package** -- that is
  native/stdlib territory; if an `xiom.simd`-class package lands there, the
  bindings libs become accelerators behind it.
- The bindings lane has **no storage-format stake**; `xiom.wal` name/scope
  coordination (ORBITDB vs XVECTOR) is the native lane's call.
- The bindings pilot is gated on the **eco-v0.1.89 publish confirmation**;
  blas-class work is Phase 2+, unscheduled.

XVECTOR consequence: nothing to adopt or block on today; the portable
`xiom.vectors` API remains the only contract we depend on, and the `xiom.wal`
coordination stays with the native/packages lanes (ORBITDB is the second
user).

## Packages lane reply (2026-10-08)

- **Names frozen:** `xiom.vectors`, `xiom.wal`, `xiom.ann`. XVECTOR owns the
  `xiom.vectors` reference implementation (the conformance suite is now
  **156 checks**, all green x2 in separate units); extraction happens via the
  **porter flow after HNSW hardening / WAL stabilization**.
- **Correction (important):** `xiom.durable` DOES carry `src/wal/*` + `src/txn/*`
  (unpublished) -- do **not** build a competing WAL under durable;
  `xiom.wal` is the **single home** for the WAL.
- **Users:** ORBITDB is the second user for `xiom.vectors` + `xiom.wal`;
  PULSE's JSONL event store is the third WAL user.
- **Kernels:** no pure-XIOM SIMD kernel is planned (native/stdlib territory);
  if one lands, consume it as the portable path -- coordinate before
  proposing a second kernel package.
- **Adoption:** `xiom.metrics` 0.2.0 fine at Phase 10; `xiom.kv` still gated
  on C-PULSE-10 + fsync. New package names get ops scope + allowlist at
  build-green (as `sqlite` did).
