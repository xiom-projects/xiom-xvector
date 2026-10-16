<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Checklist -- lattice v1 (mote / lattice scale-out)

Execution checklist for `docs/PRODUCT-ARCHITECTURE.md` (plan) and
`docs/PRODUCT-LAYERS.md` (naming decision). Pattern for every slice:
implement -> probe/suite gates -> **suite x2 + probes x2 (Windows) + WSL
spot** -> docs (SESSION/readiness/OPERATIONS as needed) -> signed commit.
Consumer lane; repo private; findings bus-routed.

## L-0 -- naming + plan (DONE)

- [x] naming decision recorded (owner-picked 2026-10-16):
  `xvector-mote` (embedded) / `xvector-lattice` (scale-out) --
  `docs/PRODUCT-LAYERS.md`
- [x] architecture plan + this checklist (2026-10-16) --
  `docs/PRODUCT-ARCHITECTURE.md`

## L-1 -- mote polish (embedded tier)

- [x] quickstart doc (`docs/MOTE-QUICKSTART.md`): open a home in-process,
  create collection, upsert, search, reopen; embedding via `xiom.vectors`
  **(done 2026-10-16)**
- [x] embedded round-trip probe in `tests/probes/`
  (`probe_mote_embedded`, the 46th probe; in both battery lists)
  **(done 2026-10-16)** -- it immediately caught the **cid-collision
  regression**: creating a collection after a reopen reused a recovered
  cid, so the next recovery's last-wins manifest merge silently dropped
  the earlier collection; fixed in `engine_recover_registry`
  (`eng.next_collection = max(cid)+1`), suite 177/177 x2 after the fix
- [ ] `mote` CLI stub (open/search/bench) -- optional, only if it earns
  its keep; gate: the same round-trip via CLI exits 0
- Gate: probe x2 both platforms; suite x2; docs. **WSL legs HELD
  2026-10-16 on the stdlib wave-146 POSIX build break**
  (`REL-20261016-1143-xvector`: runtime `TCP_NODELAY` missing
  `<netinet/tcp.h>`), re-run when stdlib fixes it.

## L-2 -- collection move primitive (the rebalancing unit)

- [ ] offline primitive: freeze (flush/checkpoint) -> copy collection
  dir + manifest entry -> attach -> verify; CLI wrapper
- [ ] `probe_collection_move`: move between homes, search/stats bit-exact
  after the flip; kill during copy leaves both homes consistent (no
  half-attached registry); re-open both homes served AND embedded (P2
  format-identity check)
- Reference (study 04): redb savepoints as the freeze model (snapshot of
  root + allocator state); bbolt's exclusive-open lock as the fail-fast
  guard. Hardening candidates: checksummed manifest entry + a
  `recovery_required` bit so a half-attached registry is caught on open;
  checkpoint salt rotation (sqlite) to prevent old/new frame mixing.
- Gate: probe x2 + suite x2 + WSL spot; `docs/OPERATIONS.md` move section

## L-3 -- router v1 (stateless)

- [ ] mapping file schema + loader (versioned JSON:
  `{version, shards[], collections{}}`; refuse start on malformed)
- [ ] router service: forward by collection; `/health`, `/version`,
  aggregate `/stats` (admin scope); shards keep their own endpoints
- [ ] stale-mapping behavior: on shard 404, re-read mapping + retry once
- [ ] `probe_router_2shards`: create/upsert/get/search/delete/stats
  through the router == direct to the owning shard; unknown collection ->
  404; mapping-version surfacing
- [ ] routing fuzz (bad paths/collection names/mapping edge cases)
- Gate: probes x2 + suite x2 + WSL spot; docs

## L-4 -- replica v1 (async catch-up, manual promotion)

- [ ] design: pin the catch-up shape against actual WAL records
  (frontier/sequence); fallback = snapshot + tail replay. Reference
  (study 04): sqlite's reader-frontier snapshot (readers pin the last
  valid frame; torn tail = longest valid prefix) is the model; zstd
  `e_flush`/`e_end` frame directives for progressive ship
  **(poll/WSAPoll readiness already exists: `xiom.os.event.poll`)**
- [ ] follower mode (read-only; applies WAL; lag metric + `/stats` field)
- [ ] manual promotion runbook: stop writer -> replay to frontier ->
  flip mapping (version bump)
- [ ] kill matrix with replica: acked writes survive writer kill AFTER
  promotion; lag returns to 0 under steady state
- Gate: kill matrix both platforms + probes x2; `docs/OPERATIONS.md`

## L-5 -- drain / rebalance + cluster ops

- [ ] admin: `POST /cluster/move`, drain node (move its collections off;
  no new placement), mapping version bump
- [ ] `probe_move_under_load`: no acked write lost; the client-visible
  retry window bounded and documented
- [ ] cluster templates sketch (systemd/docker; edge proxy for TLS) +
  OPERATIONS cluster section
- Gate: probe x2 + suite x2; docs

## L-6 -- intra-collection scatter-gather (phase B)

- [ ] design decision recorded: range vs hash sharding (rationale)
- [ ] router fan-out + k-way ranked merge (distance asc, id asc) +
  `offset`/`after_id` applied AFTER the merge; oversampling knob
- [ ] strict mode default; partial mode opt-in with `"partial": true`
- [ ] `probe_scatter_gather`: Flat exactness vs single-node ground truth
  (equal result sets), HNSW recall bound vs the gate, filtered pushdown
  oversampling measurement, pagination semantics. **The gate must name
  the recall definition per arm** (reference study 04): VectorDBBench
  uses ID-set recall; ann-benchmarks uses distance-threshold recall
  (epsilon ~1e-3, can credit wrong IDs inside the band)
- Gate: probes x2 both platforms + suite x2; BENCHMARKS note

## G-2 -- in-process concurrency (parallel track)

- [ ] per `docs/G-PHASE-PLAN.md` (`XVECTORD_THREADS` flag; coarse mutex;
  its own gate list). Orthogonal to T2; unblocked by the compiler fixes.

## Cross-cutting

- [ ] **Homes/replicas on shared/network filesystems are unsupported**
  (ops rule; sqlite documents WAL as unsafe on network FS -- reference
  study 04): local disks only, document in OPERATIONS at L-5
- [ ] **mote registry publication (when the package is ready):**
  coordinate with the **packages lane via the relay bus** (item + sha256
  + swap/verification gates, owner-gated) -- never a unilateral publish
- [ ] **lattice releases:** the **ops-owned GitHub Actions release set**
  (tag + assets + checksums); this lane supplies version + artifacts +
  gate evidence per release
- [ ] SESSION section 0/1 + READINESS updated per slice
- [ ] every platform blocker bus-routed the moment it bites
- [ ] P1-P6 invariant checks stay explicit: format identity (a
  mote-written home opens served and vice versa) is probed at L-2 and
  re-checked at L-3+

## Reference

`docs/REFERENCE-STUDY-04-LATTICE.md` (2026-10-16): bbolt (open-lock
modes + batch coalescing), redb (publish-last header, savepoints,
recovery ladder), sqlite/sqlite-vec (reader-frontier snapshot, salt
rotation, embedded UX), ann-benchmarks + VectorDBBench (gate
methodology), zstd (stream frames). Port-candidate table + traps inside.
