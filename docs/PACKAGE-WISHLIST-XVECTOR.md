<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Package wishlist from the XVECTOR lane

Proposals and adoption notes from the xiom-xvector lane (vector database).
Checked against the packages-lane tree (`E:\xiom-packages\packages\packages`,
528 package dirs) on 2026-10-09, packages lane HEAD `b52028b9`. Format:
`| Proposed name | Purpose | Why not stdlib | Deps | Evidence |`.

Registry consumption note (C-PULSE-02, filed on v0.64.0): installing a
package is not enough -- the compiler needs each package's `src/` in
`xiom.toml` `[project].source-roots`. XVECTOR has none yet; the first
adoption below will wire the first source-root (re-check C-PULSE-02 status
before that).

## Packages lane status (2026-10-09) -- wishlist deltas

- HEAD `b52028b9`; **36 eco releases**; `xiom.http` 0.1.4 published
  (`eco-v0.1.120`); the lane repinned to compiler **v0.64.2** (its matrix:
  m228/m229/m231/m239 resolved, B-01/B-08 fixed, B-10/B-05 open, io rows
  re-tested).
- **`xiom.wal` 0.1.0 is IN THE TREE** (`packages/xiom-wal`, tests 21/21,
  revision `137a8200`; `docs/PACKAGE_STATUS.md`: "new name: pending ops
  scope + native-lane allowlist append"). Scope: `xiom.durable`'s record
  vocabulary + ORBITDB's crash-proven disk segment -- one line per record
  (`lsn|op|key|value|timestamp[|payload]`), torn-tail healing before append,
  replay with malformed-line skip, temp+rename truncate; `wal_flush` is an
  honest no-op until the stdlib fsync row lands (the same gate as our M2).
- **`xiom.btree` 0.1.0 is in the tree** (`packages/xiom-btree`, tests 22/22,
  revision `c78fe78a`; same ops-allowlist gate). In-memory `Int -> Int`
  B-tree extracted from ORBITDB -- watch for future xvector metadata/index
  use (our id -> slot map and payload key index are bespoke today).
- The packages lane's stated remaining gate for both: **ops scope + native-lane
  allowlist append before publish**.
- XVECTOR consequence: `xiom.wal` is the **single home** -- XVECTOR aligns
  its codec (our value payload `[dim, f32-bits...]` fits the record payload
  field) and consumes the package when published; our local
  `durability.wal` + `wal_file` stay until then. No competing WAL.

## Proposed packages (still to extract)

| Proposed name | Purpose | Why not stdlib | Deps | Evidence |
|---|---|---|---|---|
| `xiom.vectors` | Shared dense-vector primitives for XIOM vector engines: `Vector` (Vec[Float32] + dim), distance metrics (cosine/dot/L2), normalization, bounded top-K heap, and the WAL value codec (`[dim, f32-bits...]`) with recovery replay. The portable pure-XIOM baseline under any SIMD/BLAS binding. | Domain layer that changes with index/quantization research (IVF/PQ, fusion scoring); stdlib keeps a minimal surface; two XIOM products need the same types. | stdlib (`xiom.math`, `xiom.num.float`) | Duplication between **xvector** and **orbitdb** (both implement vector math + metrics + top-K); xvector's reference implementation now sits behind the facade/extracted tree with a **169-check suite** + 18 probes (all green x2 Windows + WSL on v0.64.2); the porter extraction gate ("after HNSW hardening") is **met** (multi-layer HNSW, tombstones, compaction, codec, update re-linking, recall harness all landed 2026-10-08/09). Awaiting owner greenlight + porter scheduling. |
| `xiom.ann` | Approximate nearest-neighbour indexes: flat exact scan, HNSW graph (build/search/tombstones), recall harness against the exact oracle. | Index parameters and algorithms evolve fast; stdlib should not freeze an ANN API. | `xiom.vectors` | xvector's HNSW is hardened in-memory (recall vs the flat oracle: n=200 300/300 at ef=64, n=800 200/200; tombstones + compaction + strict codec + build-work/latency metrics; gates `probe_hnsw_recall` / `probe_engine_hnsw` / `probe_hnsw_codec`); extraction after `xiom.vectors` (avoid freezing a half-tuned graph -- now satisfied, so extraction can follow the vectors extraction). |

## Adoption notes (existing registry packages)

| Package | Status for XVECTOR | Evidence | Blocked by |
|---|---|---|---|
| `xiom.metrics` 0.2.0 | **Planned** for Phase 10 observability (latency/recall histograms). | PULSE adopted it 2026-10-07 (labeled counters + latency preset + exposition); XVECTOR currently has an inline `Counter` only. | nothing intrinsic; adopt when the first metric surface lands (Phase 10), wire `source-roots` per C-PULSE-02 |
| `xiom.kv` 0.1.0 | **Candidate** segment metadata / manifest store; **not adopted now**. | PULSE: `kv_get` returned address-like Str on WSL Linux v0.64.0 (C-PULSE-10; Windows green); packages lane repinned v0.64.2 (io rows re-tested); XVECTOR additionally needs fsync before any KV store can back a durable manifest. | C-PULSE-10 (Linux `kv_get`) + the stdlib fsync gap (`STDLIB-WISHLIST-XVECTOR.md`) |
| `xiom.btree` 0.1.0 | **Watch** (in-tree; see status above). | Ordered Int->Int map with range scans; could back future multi-segment metadata; our current maps are specialised. | ops scope + allowlist before publish |
| `xiom-blas` / `xiom-eigen` / `xiom-openblas` | **GATED** -- bindings relay 2026-10-09: verified incubating placeholders (tests unknown, no timeline); when built they mirror the `xiom.vectors` contract, never define it; no SIMD kernel package from that lane; pilot complete through batch 22, so **accelerators are the sole unscheduled sector**. The portable `xiom.vectors` API stays the contract. | Packages lane FFI/bindings status (bindings worktree); xvector `distance/` is the future call-site seam. | gated on the bindings lane scheduling (no date) |
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

**Addendum (2026-10-09, inbound relay):** the accelerator row **stays
GATED** -- `xiom-blas`/`xiom-eigen`/`xiom-openblas` are verified incubating
placeholders (tests unknown, no timeline); when built they mirror the
`xiom.vectors` contract, never define it. No SIMD kernel package from that
lane; the bindings pilot is complete through batch 22, so accelerators are
the sole unscheduled sector. XVECTOR's SIMD path (M-P3) therefore stays
seam-first with pure-XIOM kernels. **Follow-up (2026-10-09):** the bindings
durable-DB sector closed (`xiom.sqlite`/`xiom.libpq`/`xiom.odbc` live and
signed); the bindings lane will pick up **accelerators once the
`xiom.vectors` extraction lands** (owner greenlight still pending on our
side).

## Packages lane reply (2026-10-08)

(Historical; superseded in part by the 2026-10-09 status above.)

- **Names frozen:** `xiom.vectors`, `xiom.wal`, `xiom.ann`. XVECTOR owns the
  `xiom.vectors` reference implementation (the conformance suite was then
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
