<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# RELAY -> PACKAGES (from XVECTOR, 2026-10-08)

**From:** XVECTOR lane, `E:\xiom-projects\xiom-xvector` (private; owner relays).
**Toolchain:** compiler v0.64.0; **no registry packages consumed yet**
(C-PULSE-02 `source-roots` workaround in the project manifest).

**Please read:** `docs/PACKAGE-WISHLIST-XVECTOR.md` in the xvector repo.

**Proposed packages (coordinate with ORBITDB before freezing names — it is the
same problem space and we should build one shared layer, not two forks):**

| Proposed | Purpose | Evidence in xvector |
|---|---|---|
| `xiom.vectors` | dense-vector types + cosine/dot/L2 + normalization + bounded top-K + WAL codec (`[dim, f32-bits...]`) | reference implementation in `src/engine.xi`; 136-check conformance suite green x2 |
| `xiom.wal` | append-only segmented log: CRC-framed records (`crc32_ieee`), LSNs, replay/recovery with torn-tail tolerance, checkpoint + LSN continuity | `wal_writer_append_payload`/`recover_store`/`wal_writer_checkpoint_from` working in-memory; PULSE's JSONL store is a second user; `xiom-durable` is unpublished foundation types — scope check requested |
| `xiom.ann` | flat exact scan + HNSW graph (build/search, later tombstones), recall harness vs the flat oracle | xvector ROADMAP Phases 1/4; propose extraction only after our HNSW hardening (don't freeze a half-tuned graph) |

**Adoption notes for existing packages:**
- `xiom.metrics` 0.2.0 — planned for Phase 10 observability (latency/recall).
- `xiom.kv` 0.1.0 — candidate for manifest/segment metadata; **not adopted**:
  blocked on C-PULSE-10 (Linux `kv_get`) and on the stdlib fsync gap.
- `xiom-blas`/`xiom-eigen`/`xiom-openblas` — watched as drop-in accelerators
  behind the portable `xiom.vectors` API (bindings worktree); no pure-XIOM
  SIMD/vector-kernel package found in the tree — tell us if one is planned
  before we propose a second kernel package.

**Ask:** confirm/reshape the three proposed names and their scope, and flag
overlap with `xiom-durable`/`xiom-snapshot`/`xiom-kv` before publishing.
