<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom-xvector v1.0.0-rc.1 -- release notes

**Status:** release candidate, prepared 2026-10-09 and refreshed 2026-10-19.
The repository stays private and the public GitHub release is the owner's
action; nothing in this document authorizes a push. The candidate is pinned
to compiler v0.64.7 on both platforms; a v0.64.8 cut is GO upstream but was
still in its stdlib gate at refresh time, so if it lands before the tag the
candidate is re-pinned and the batteries are re-run first.

## What this is

`xiom.xvector` is a production-grade XIOM vector database: dense-vector
storage with exact Flat search and a hardened HNSW index, opt-in SQ8
quantization, WAL-backed durability with a durable collection registry and
sealed segment files, a typed payload/filter surface, multi-collection
routing, and a transport-agnostic HTTP service with config, limits, auth,
rate limiting, observability, and security gates. It ships in two shapes of
one engine and one on-disk format: **xvector-mote** (embedded library /
registry package) and **xvector-lattice** (served daemon + stateless router
+ replicas + move/drain). Both tiers run the same `src/` tree.

## Highlights since the programme kickoff (v0.1.0-dev)

- **Durability (M-D / D5-D7).** Atomic WAL checkpoints (temp+rename), a
  durable collection registry file, multi-collection registries with routed
  recovery and whole-registry checkpointing, and sealed segment files with
  engine seal/restore + WAL re-checkpoint. D5 adds the opt-in delta segment
  with fsync-on-ack (`XVECTORD_WAL`), D6 the bounded checkpoint swap with
  crash-safe ordering and segment rotation, D7 seal auto-roll and the
  multi-segment read path (roll/union queries over active + sealed,
  tombstone shadowing, bit-exact compaction). A durable reopen-then-write
  loss found during L-4 was fixed: the segment file is the durable frontier,
  not `max(file, in-memory)`. Kill-recovery prefix exactness and torn-tail
  loaders are gated by probes.
- **Query surface (M-Q + Q-a).** Exact range search, batch upsert/search/
  delete, stable offset and after-id pagination over the (distance, id)
  total order, planner-driven delete-by-filter, per-collection stats + admin
  rebuild, and SearchRequest extensions (knn/range modes, pagination,
  batches). Q-a1 added SQ8 scalar quantization (trained per-dimension
  ranges, truncation codec, FAISS-pattern query tables, sqlite-vec-pattern
  two-tier rescore) and Q-a2a the segment codec v2 with an opt-in SQ
  section (`has_sq/sq/codes`) and torn-section drop. Rescore is bit-identical
  to exact on the gated queries; documented error bounds are pinned.
  Q-a2b (two-tier rescore on sealed scans) remains queued.
- **Index + planner.** Exact Flat search, a hardened HNSW (multi-layer,
  tombstones, codec, recall harness, compaction), a sorted payload key index
  with pre/post filtering and a planner, and a Float64 reference oracle that
  cross-checks kernels and ranked/paged/cursor/range/HNSW paths (Float32-ulp
  deviations, bit-identical across platforms).
- **Service + operations (M-S/M-O).** A byte-level HTTP/1.1 server
  (`xvectord`: `/health`, `/collections`, points CRUD, `/search`, `/stats`,
  `/metrics`), config + limits + the `{error,kind,status}` envelope, API-key
  auth (constant-time, read/write/admin scopes) + token-bucket rate limiting,
  a 2500-input fuzz gate, a JSON depth guard that fixed a found remote
  stack-exhaustion DoS, the bounded JSON log ring, SBOM/unsafe gates in CI,
  `docs/OPERATIONS.md`, and the required security review in `docs/SECURITY.md`.
- **Scale-out (L-1..L-5).** L-1 mote embedded/polish; L-2 the collection
  move primitive (`export_collection` / `attach_segment` with an integrity
  footer); L-3 the stateless router v1 (versioned mapping file + strict
  loader, collection routing, retry-on-404 stale-mapping recovery, cluster
  endpoints); L-4 file-ship async replicas (catch-up + manual promotion;
  `replica_lag` in `/stats`); L-5 online `POST /cluster/move` + drain,
  compaction-aware and gated under load. L-6 (intra-collection scatter-
  gather, phase B) remains queued.
- **Concurrency (G-1).** Real `xiom.thread.spawn[T]` + `JoinHandle.join`
  acceptance and a cross-thread producer/consumer leg over module-level
  `SyncMutex`/`AtomicInt` globals are green on Windows + WSL; the previous
  Int-handle workaround is retired. G-2b (threaded accept loop,
  `XVECTORD_THREADS`) is **not in this candidate** -- it is blocked on the
  compiler defect below; the shipped engine and service are single-writer /
  single-threaded.
- **Packages + carve safety.** The registry tier is consumed and gated:
  `xiom.wal` 0.1.0, `xiom.metrics` 0.2.0, `xiom.rate` 0.2.0,
  `xiom.http` 0.1.9, `xiom.vectors` 0.2.0 (the MOTE package), `xiom.ann`
  0.2.0, `xiom.orbitdb` 0.2.1, and `xiom.pulse` 0.3.1 (exact identity,
  HookCtx, fallback seam, HEAD trim). `xiom.vectors` 0.2.0 was published on
  2026-10-18 (eco-v0.1.198; sha256 `130427a5...`; carve of this repo with
  the lattice transport excluded). The source tree vendors the package
  surface internally as `src/primitives.xi` (`xiom.vector.primitives`) so a
  carve cannot self-import; `scripts/libcheck.ps1` / `libcheck.sh` type-check
  every `src/` module in package mode and enforce the internal-import rule in
  both CI scripts.

## Verification evidence (at this candidate)

- **Toolchain:** XIOM Compiler v0.64.7 pinned and sha256-verified on both
  platforms (Windows `16a436c4`, Linux `153f0cc9`); stdlib tree `15495aa`
  (release pin `stdlib-v0.64.7` = `1271dd5`); packages checkout `ca41d483`.
  WSL legs target `wsl -d Ubuntu`.
- **Full batteries:** conformance suite **177/177 x2**, **53 probes x2**,
  SBOM/unsafe gate (**47 modules, unsafe = 0**), the library type-check gate
  (**47/47**), bench smoke, and the kill matrix. Windows full battery was
  ALL GATES GREEN on v0.64.7 (stdlib `15495aa`, packages `0574c0d6`,
  `4df7086`); the WSL full battery was green on the same v0.64.7 candidate
  (stdlib `6727526`, packages `2e7c5524`), and every subsequent slice
  re-ran the suite, library gate, and affected probes on both platforms
  (package adoptions: pulse 0.3.1, vectors 0.2.0; library gate;
  XVC-C-20 repro).
- **Benchmark report:** `docs/BENCHMARKS.md` (methodology + committed
  baseline; the reference oracle pins kernel fidelity at Float32-ulp scale).
- **Security checklist:** `docs/SECURITY.md` (threat model, secure defaults,
  no-unsafe audit) + `docs/sbom-v1.0.0-rc.1.json` (refreshed: 47 modules,
  unsafe = 0, compiler v0.64.7).
- **Repro bundles:** `docs/repro/` -- XVC-C-13, C-14, C-16, C-17, and C-18
  are verified fixed on v0.64.6/.7; C-15 and the phantom controls stay
  green. Two findings remain relevant: **XVC-C-19** (v0.64.7 hangs on
  module-level function-call / allocating `var` initializers; shipped code
  avoids the shape; `docs/repro/xv-global-init-hang/`) and **XVC-C-20**
  (module-level `VectorEngine` global lost mutations through `&mut`; fixed
  on compiler main `56d362a31`, no v0.64.7 re-cut yet;
  `docs/repro/xv-global-engine-mutation/`).
- **Bus:** results, findings, and consumer test-backs are filed on the
  private `xiom-lang/xiom-relays` bus (see SESSION section 0 for the ids).

## Known limitations (honest)

- **Single-threaded engine/service in this candidate.** G-2b (threaded
  accept loop) is blocked on XVC-C-20: the compiler fix is on main but not
  in the v0.64.7 archive, so sharing the engine across worker threads cannot
  be verified. The accept loop remains sequential; concurrency claims beyond
  the G-1 primitives are not made.
- **XVC-C-19 compiler hang** on module-level call/allocating initializers.
  Lane policy forbids that shape; module-level globals are scalar/null
  literals or compiler-tested zero intrinsics only.
- **No TLS and no encryption at rest.** TLS/proxying is deployment-side;
  there is no built-in encryption for WAL/manifest/segments.
- **Q-a2b is not in the candidate:** SQ8 is gated for training/scan/rescore
  and segment artifacts, but the sealed-scan two-tier rescore is still
  queued. Approximate results carry the documented error bounds; exact Flat
  remains the correctness baseline.
- **L-6 phase B is not in the candidate:** L-3/L-4/L-5 cover routing,
  replicas, move/drain; intra-collection scatter-gather follows. Shards stay
  single-writer per home; consistency is the engine's (WAL-before-ack,
  atomic manifest switch, tombstone shadowing).
- **Durability is opt-in:** `XVECTORD_WAL` enables fsync-on-ack/checkpoint/
  seal; without it the server runs in-memory (no durability claim).
- **Package ownership:** MOTE publishes through the packages lane; the
  lattice release set is ops-owned. `xiom.ann` remains owner-gated for the
  swap; `xiom.vectors` is published and consumed.

## Upgrade / compatibility

On-disk formats are versioned: `xvector-wal 1` (manifest families v1/v2/v3),
`xvector-manifest 1`, and `xvector-segment 1` (v2 adds the optional SQ
sections `q`/`c`; v1 output stays byte-identical when SQ is not armed).
Loaders accept older records and reject unknown headers as invalid. No
breaking API changes relative to the v1.0 programme documents; the consumer
vector surface stays `xiom.vectors`, and `xiom.vector.primitives` is
package-internal (not a consumer API). The `XVECTORD_*` environment knobs
(port/bind/WAL/manifest/checkpoint/seal/limits) are documented in
`docs/OPERATIONS.md`.

## Release ownership

- **mote:** registry package `xiom.vectors` (release through the packages
  lane; published 0.2.0 on 2026-10-18).
- **lattice:** standalone `xvectord` + router/replica/move operations; the
  GitHub Actions release set is ops-owned.
- **rc.1 GitHub release:** owner-gated while the repository is private. The
  release artifacts are this note, the refreshed SBOM snapshot, and the
  archived battery logs (`out/` is lane-local; the committed evidence is in
  SESSION section 0 and the probe/suite scripts).

## Next (post-rc.1 queue)

1. Re-pin to the v0.64.8 archive when it ships; re-run the C-20 repro
   (expect count 1 / second create Err) and the full batteries.
2. Re-open G-2b (threaded accept loop, coarse engine mutex, graceful joins)
   on that archive, then Q-a2b and L-6 phase B.
3. Continue scale tuning and the release-notes/artefact refresh at each
   archive pass.
