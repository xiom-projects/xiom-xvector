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

- [ ] quickstart doc (`docs/MOTE-QUICKSTART.md`): open a home in-process,
  create collection, upsert, search, reopen; embedding via `xiom.vectors`
- [ ] embedded round-trip probe in `tests/probes/` (open -> upsert ->
  search -> reopen; NO sockets) + both battery lists
- [ ] optional `mote` CLI stub (open/search/bench) -- only if it earns
  its keep; gate: the same round-trip via CLI exits 0
- Gate: probe x2 both platforms; suite x2; docs

## L-2 -- collection move primitive (the rebalancing unit)

- [ ] offline primitive: freeze (flush/checkpoint) -> copy collection
  dir + manifest entry -> attach -> verify; CLI wrapper
- [ ] `probe_collection_move`: move between homes, search/stats bit-exact
  after the flip; kill during copy leaves both homes consistent (no
  half-attached registry); re-open both homes served AND embedded (P2
  format-identity check)
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
  (frontier/sequence); fallback = snapshot + tail replay
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
  oversampling measurement, pagination semantics
- Gate: probes x2 both platforms + suite x2; BENCHMARKS note

## G-2 -- in-process concurrency (parallel track)

- [ ] per `docs/G-PHASE-PLAN.md` (`XVECTORD_THREADS` flag; coarse mutex;
  its own gate list). Orthogonal to T2; unblocked by the compiler fixes.

## Cross-cutting

- [ ] SESSION section 0/1 + READINESS updated per slice
- [ ] every platform blocker bus-routed the moment it bites
- [ ] P1-P6 invariant checks stay explicit: format identity (a
  mote-written home opens served and vice versa) is probed at L-2 and
  re-checked at L-3+
