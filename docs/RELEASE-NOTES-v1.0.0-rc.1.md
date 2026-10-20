<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom-xvector v1.0.0-rc.1 -- release notes

**Status:** release candidate, prepared 2026-10-09 and refreshed 2026-10-19.
The repository stays private and the public GitHub release is the owner's
action; nothing in this document authorizes a push. The candidate is pinned
to compiler v0.64.8 on both platforms (released 2026-10-19T17:49Z; v0.64.7
kept as rollback). The v0.64.8 re-pin re-ran the XVC-C-19/C-20 repros and
the full batteries before this note; the stdlib registry publish for 0.64.8
is blocked upstream (`publisher_not_mapped`), but the compiler archive is
live and self-contained.

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
  Q-a2b (two-tier rescore on sealed scans) landed: sealed Flat segments with
  SQ codes are read through the quantized coarse scan + exact f32 rescore
  (`probe_sq_sealed`), bit-identical to the pre-seal exact top-k on the gate.
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
- **Station web admin (read-only MVP).** `xvectord` serves `/ui`: a
  dependency-free page with a seeded random 2D projection of an active-store
  sample (`GET /collections/{n}/sample`, bounded 1..2000, deterministic
  stride), point inspection, and `/search` hit highlighting. Static
  same-origin page; API auth/scopes still apply. Canvas 2D today;
  three.js/WebGL, a payload-aware editor, and an HNSW graph view are
  follow-ups (`docs/UI.md`; `probe_ui`).
- **Performance seam (P3).** Distance/dot/magnitude kernels route through
  `src/index/kernels.xi` behind the `xiom.vectors` contract: scalar default,
  selectable unrolled-same-order backend, bit-identical across all metrics
  (`probe_kernels`, 57th). The hot flat/HNSW/range/pagination/SQ paths
  branch once per scan, keeping the scalar path at the pre-seam baseline
  (flat 62us/op, HNSW ef32 281us/op when unloaded). No Float32 accelerated
  binding is available yet -- OpenBLAS 0.1.1 is Float64/native -- so a
  binding plugs in as a third kernel kind; the seam is ready for it.
- **Scale-out (L-1..L-5).** L-1 mote embedded/polish; L-2 the collection
  move primitive (`export_collection` / `attach_segment` with an integrity
  footer); L-3 the stateless router v1 (versioned mapping file + strict
  loader, collection routing, retry-on-404 stale-mapping recovery, cluster
  endpoints); L-4 file-ship async replicas (catch-up + manual promotion;
  `replica_lag` in `/stats`); L-5 online `POST /cluster/move` + drain,
  compaction-aware and gated under load. L-6 (intra-collection scatter-
  gather, phase B) remains queued.
- **Concurrency (G-1 + G-2b).** Real `xiom.thread.spawn[T]` +
  `JoinHandle.join` acceptance and a cross-thread producer/consumer leg over
  module-level `SyncMutex`/`AtomicInt` globals are green on Windows + WSL;
  the previous Int-handle workaround is retired. **G-2b is in this
  candidate**: `XVECTORD_THREADS` enables the threaded accept loop (accept
  in one thread, per-connection workers, bounded in-flight, all engine calls
  under one coarse mutex, graceful `JoinHandle` joins; the default remains
  the sequential path). A new concurrency probe (4 clients x 8 deterministic
  ops -> exact 32 points; worker-served quit; shutdown join) is green x2 on
  both platforms. XVC-C-19 and XVC-C-20 are verified fixed on v0.64.8.
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

- **Toolchain:** XIOM Compiler v0.64.8 pinned and sha256-verified on both
  platforms (Windows `c31d9c46`, Linux `a8c003c0`; v0.64.7 kept as
  rollback); stdlib tree `8b1ddd7` (release pin tag `stdlib-v0.64.8` =
  `0bf5b75`, asset sha256 `6ea77968...`; registry publish blocked upstream
  `publisher_not_mapped`); packages checkout `ca41d483`. WSL legs target
  `wsl -d Ubuntu`.
- **Full batteries:** Windows **ALL GATES GREEN** at the v0.64.8 pin
  (suite 177/177 x2, 57 probes x2, SBOM 48/0, libcheck 48/48, bench smoke,
  kill matrix); WSL suite 177/177 x2 + `probe_ui` / `probe_concurrency` /
  `probe_kernels` / service family x2 are green on the UI/P3 tree; WSL long
  sweeps were environment-interrupted by repeated VM restarts, so the full
  WSL sweep + libcheck are queued for a quiet window. The new 55th probe is
  the station-UI gate; the 54th is the G-2b concurrency gate; the 56th is
  sealed SQ; the 57th is the P3 kernel seam; the service family and `probe_http_fuzz` are
  unchanged and green x2. Quick bench on v0.64.8: flat 62us/op (~16.1k qps
  at the quick group size), HNSW ef=32 recall 1.000 / 281us/op (~3.6k qps),
  recovery 1.0 s.
- **Benchmark report:** `docs/BENCHMARKS.md` (methodology + committed
  baseline; the reference oracle pins kernel fidelity at Float32-ulp scale).
- **Security checklist:** `docs/SECURITY.md` (threat model, secure defaults,
  no-unsafe audit) + `docs/sbom-v1.0.0-rc.1.json` (refreshed: 47 modules,
  unsafe = 0, compiler v0.64.8).
- **Repro bundles:** `docs/repro/` -- XVC-C-13, C-14, C-16, C-17, C-18 are
  verified fixed on v0.64.6/.7; C-15 and the phantom controls stay green.
  **XVC-C-19** (module-level initializer hang) and **XVC-C-20** (module-level
  aggregate global mutation loss) were verified fixed on v0.64.8 on both
  platforms; the repros stay as regression gates. No XVECTOR compiler
  findings remain open.
- **Bus:** results, findings, and consumer test-backs are filed on the
  private `xiom-lang/xiom-relays` bus (see SESSION section 0 for the ids).

## Known limitations (honest)

- **Concurrency is correct-first.** The threaded path is flag-gated
  (`XVECTORD_THREADS`; default sequential) and all engine calls serialize on
  one coarse mutex. G-3 read snapshots and G-4 metrics-under-concurrency are
  future work; scale tuning continues. XVC-C-19/C-20 are verified fixed on
  v0.64.8; the repros stay as regression gates.
- **No TLS and no encryption at rest.** TLS/proxying is deployment-side;
  there is no built-in encryption for WAL/manifest/segments.
- **The web admin is read-only and active-store-scoped.** `/ui` samples the
  active store (sealed segments are not included yet), uses Canvas 2D with a
  random projection, and has no editor. It is a browser client of the API,
  not a privileged backdoor: API keys/scopes still apply.
- **Q-a2b is in the candidate:** SQ8 is opt-in on sealed segments (armed by
  the roll when trainable) and the sealed Flat read path uses the quantized
  coarse scan + exact rescore; filtered sealed queries stay exact. Exact
  Flat remains the correctness baseline; the Q-a2b gate pins bit-identical
  top-k on a rolled segment.
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

1. M-P (P3 SIMD seam / P4 IVF-PQ); L-6 phase B after.
2. Keep the repros and the latest-tree protocol running at each archive;
   the v0.64.8 stdlib registry publish is blocked upstream
   (`publisher_not_mapped`) -- the compiler archive is live and re-pinned.
3. Continue scale tuning and the release-notes/artefact refresh at each
   archive pass.
