# XIOM XVECTOR -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Project:** `E:\xiom-projects\xiom-xvector` -- production-grade vector
database engine for XIOM (dense vectors, metrics, flat + HNSW ANN,
collections, segments, WAL-backed durable writes; the working tree is the
`src/engine.xi` facade over `src/engine/core.xi` + the extracted modules).
**Written:** 2026-10-07 (bootstrap by the PULSE lane).
**Latest pass:** 2026-10-23 (91st: **G-4 metrics-under-concurrency
COMPLETE** on v0.64.8 + stdlib `750384f` -- atomic service counters,
shared-state `/metrics` in `XVECTORD_THREADS` mode, wall-clock-ordered
`ts` log ring; full Windows battery + WSL spot green. v0.64.9 remains
withdrawn; the v0.65.0 gate is open; see §24).
**Last updated:** 2026-10-16 (83 continuation passes: bootstrap -> Phase 2
durability -> Phase 3 payload filtering -> payload durability -> 4 extraction
waves -> v0.64.1 re-test -> FloatVal unwind -> final extraction wave ->
SearchRequest wire + with_payload hydration [XVC-C-08 found] -> sorted
payload key index -> selectivity pre/post filter planner -> HNSW layer-0
graph + recall harness -> multi-layer HNSW -> HNSW tombstone deletes ->
engine HNSW wiring -> HNSW tombstone compaction -> HNSW graph codec ->
beam construction + diversified pruning -> HNSW id map [XVC-C-09 found] ->
shape pins + unwind decision -> HNSW+filter integration -> fuzz gate +
decoder hardening [XVC-C-10 found] -> mixed-workload soak -> latency metrics
+ release-prep drafts -> upsert fix + index-driven candidates -> durable
collection manifest -> HNSW update re-linking -> kill-recovery acceptance ->
multi-key intersections -> file-backed WAL whole-file checkpoint [XVC-C-11/C-12
found] -> v0.64.2 re-test: C-03/C-06/C-07/C-08 verified fixed, C-07/C-08
workarounds reverted, C-10..C-12 re-tested green -> wishlist refresh
(stdlib 0.64.3 re-check; xiom.wal/xiom.btree in-tree; relays updated) ->
production programme kickoff: requirements + v1.0 plan + checklist ->
M-D1 atomic WAL checkpoint (temp + io.rename; kill injection) ->
consumer handshakes (PULSE + ORBITDB integration files; bindings relay) ->
M-Q1 exact range search (kernel + engine + facade + probe) ->
M-Q2 batch ops (upsert_many / delete_many / search_many + BatchHits) ->
M-G bench harness + baseline [wal_persist O(L^2) fixed; native --icon] ->
M-D2 manifest file [collection registry file, atomic rename, torn-tail-safe
load, file-wins open with in-WAL migration fallback; XVC-C-13 found] ->
M-D3 multi-collection registry [named create/select/drop/list, per-
collection isolation, routed recovery (v2/v3 manifest records), whole-
registry manifest save; probe_collections]) -> M-D4 sealed segment files
[segment_file codec (vectors + payloads + Hnsw graph, atomic persist,
torn-tail load), engine seal/restore with WAL re-checkpoint; lifecycle
Mutable -> Sealing -> Sealed]) -> M-Q3 pagination [search_page (offset) +
search_after (after-id cursor) over the (distance asc, id asc) total
order; probe_pagination]) -> M-Q4 delete-by-filter [planner-driven
selective delete (index candidates or scan), per-point WAL, tombstones +
payload/index cleanup; probe_delete_filter]) -> M-Q5 index admin
[per-collection stats + admin rebuild_index (before/after/reclaimed);
probe_index_admin]) -> M-Q6 request extensions [SearchRequest mode
(knn/range) + offset/after-id pagination; SearchBatchRequest +
search_batch_with_request; probe_search_request extended]) -> M-G1
reference oracle [independent Float64 oracle vs kernels + axioms + all
ranked/paged/cursor/range/Hnsw paths; probe_reference_oracle]) -> M-S1
HTTP service skeleton [api.http_service byte-level HTTP/1.1 pipeline +
router; probe_http_service]) -> M-S2 service config/limits/errors
[ServiceConfig + env/file loaders; enforced limits; {error,kind,status};
shutdown checkpoint; probe_service_limits]) -> M-S3 auth + rate limiting
[API keys (constant-time, scopes read/write/admin, XVECTOR_API_KEYS);
token-bucket RateLimiter; ServiceState; probe_service_auth]) -> M-S4
security pass [fuzz gate (2500 inputs) + JSON depth guard (found+fixed a
stdlib stack-overflow); SBOM + unsafe gate scripts; SECURITY.md;
probe_http_fuzz]) -> M-O observability [metrics module (histograms +
counters + JSON log ring), /metrics + health readiness, runbook;
probe_metrics]) -> M-R release candidate [checklist audit + repro re-runs +
release notes + SBOM snapshot + owner handoff; v1.0.0-rc.1; final
batteries green at the tagged commit]) -> xiom.wal first adoption
[registry install + trust pin + xiom.toml dependency; op-code alignment
gate; D5 migration plan] -> xiom.metrics 0.2.0 adoption (observability
internals package-backed behind the same surface; engine stat counters
unified on the package; shim Counter retired after XVC-C-14;
probe_package_metrics added; bus item -7 verified + closed) -> xiom.rate
0.2.0 adoption (token-bucket internals on the package behind the same
API; carry-exact refill; probe_package_rate added; 35 probes) ->
compiler v0.64.3 re-pin + lane-local isolation (shared-home wipe incident
diagnosed + filed; out/toolchain + out/xiom-home; XVC-C-13/C-14 re-tested
unchanged; release-check verdicts filed; both batteries green isolated) ->
xiom.http helper evaluation + adoption (status phrases on the package
behind a lane adapter; router/parser evaluated, not adopted;
probe_package_http; 36 probes) -> xiom.vectors 0.1.0 wiring + fidelity
gate (byte-exact carve verified, 6/6 pins; probe_package_vectors;
atomic all-surfaces swap planned -- XVC-C-14 constraint; 37 probes) ->
xiom.vectors internals swap EXECUTED (atomic: 11 src + 27 probe imports
onto the package; five local modules deleted; codec extracted from
vector_store; batteries green both platforms) -> reference study area
opened per owner grant (`E:\repos`; sqlite-vec/faiss/DiskANN cloned,
MIT-verified; study rules + backlog in 2) -> reference study 01 FAISS
HNSW recon (`docs/REFERENCE-STUDY-01-FAISS.md`) -> P-a APPLIED (63rd pass):
generous HNSW level 0 (`m0 = 2*m` + FAISS `prune_headroom` 0.2; codec v3
carries `m0`, v2 still decodes; adjacency rows stride `m0`; fill arm
measured and NOT adopted), hard-corpus control gate 285/300 vs 275/300
legacy; costs recorded (build +13%, W3 p50 +28..40%, recovery +27%) ->
reference study 02 quantization recon
(`docs/REFERENCE-STUDY-02-QUANTIZATION.md`: SQ8 trained ranges + the
two-tier rescore pattern as first candidate Q-a; PQ deferred pending
deterministic training; explicit error-bound story required before any
adoption) -> reference study 03 DiskANN layout recon
(`docs/REFERENCE-STUDY-03-DISKANN.md`: sector-packed fixed-size records
(4096 B, no node split), co-located f32 + adjacency, buffer-then-seal
delta model, delete-by-rebuild, alignment as a format decision for
D5/D6/P5; study backlog complete) -> Q-a1 applied (66th pass): SQ8
quantization module (`src/index/quantize.xi` -- trained per-dim ranges,
truncation codec, FAISS-pattern query tables, sqlite-vec-pattern
two-tier rescore) gated by `probe_quantization` (17 checks;
bit-identical rescore 10 queries x 3 metrics; documented error bounds
pinned) + suite Section 16; compiler finding **XVC-C-15** found and filed
during the slice (literal stores into `Vec[Float32]` slots skip
narrowing; repro `xv-f32-slot-literal-write`; bus item
`REL-20261011-1134-xvector`) -> Q-a2a applied (67th pass): segment codec
**v2** (opt-in SQ section: `has_sq/sq/codes` + `sealed_segment_enable_sq`;
`q`/`c` sections after the graph; v1 output byte-identical when not
armed; loader accepts both versions with torn-section drop) + artifact
gates in `probe_quantization` (roundtrip, rescore over the loaded segment
bit-equal to exact, torn q/c keeps vectors, byte delta 35 B/vector text
vs 8 B future binary); owner directive 11:59Z routing also recorded
(bus `-1203-xvector/-2`) -> xiom.ann porter evaluation (68th pass):
registry watch CLOSED -- `xiom.ann` 0.1.0 LIVE (eco-v0.1.139); the
package is the pre-P-a snapshot (`8a8b0ff`; codec v2, legacy 296/300) ->
**0.2.0 refresh ask filed** (`REL-20261011-1206-xvector`: carry the P-a
generous level 0 + codec v3); the consumer swap awaits package 0.2.0 +
owner greenlight (vectors precedent); eval in `docs/XIOM-ANN-EVAL.md` -> 73rd pass: re-verification era opened on the
new pins -- `xiom.http` 0.1.6 re-sync (native 507, adapter special-case
retired, tripwire re-synced); the stdlib wave-111 `strnlen` fix
**verified on their uncommitted WIP** (both `docs/repro/xv-json-parse
-quadratic` probes exit 0; 5k fit 120 s -> 57.4 s) with full batteries
green on the wave-110/WIP pins (Windows + WSL spot); quick_bench re-run
recorded; gated pivots re-checked (fsync + mmap still stubs, no new
compiler release); bus -2002/-1206/-9/-1835 verified+closed + WIP signal
filed (`-1618`) -> 74th pass: VectorDBBench client adapter shipped
(`bench/adapters/vectordbbench/`: drop-in DB client + direct-mode live
smoke 11/11; shared `oracle.py` extracted; `xvector_client.drop_collection`)
-> G-phase thread gate probed: `xiom.thread.spawn[T]` compiles on
v0.64.3 but AVs at the runtime entrypoint (Windows 0xC0000005 / WSL
SIGSEGV; last mark `M2: spawn returned`); witness
`docs/repro/xv-thread-abi/` filed (`REL-20261011-1627-xvector`); the
concurrency phase stays gated on the next archive -> wave-111 CLOSED:
stdlib committed the fix (`9a2b5ab`; committed hashes == the
pre-verified WIP); both repros exit 0 Windows + WSL; batteries green
(Windows ALL GATES; WSL suite 177/177 x2 + probes); xvectord 5k x
dim-25 fit 661 s -> 51.2 s (98 pts/s); acceptance gate re-pinned to a
linearity bound (20x-ratio + 3 s net); bus `-1453`/`-1543` verified +
closed -> 75th pass: P2 memory accounting estimate + budget thresholds
(`engine_memory_estimate` + `/stats` mem_* fields; documented uniform-row
model; `probe_memory_estimate` 17 checks; 41-probe batteries green both
platforms; `docs/OPERATIONS.md` section 8) -> wave-113 re-verification
(19:00Z doorbell): stdlib `a996f7b` str-family fully closed -- both repro
probes + full battery green (41 probes x2) on Windows; WSL suite 177/177
x2 + `probe_json_fast` 228/228 x2 + `probe_memory_estimate` x2; stdlib
item `-1856` acked -> fixed. Compiler batches 1-6 complete (m261-m271),
v0.64.4 staged -- C-15/-1134 + phantom/-2124 both `fixed`, re-run at the
archive (next doorbell) -> 77th pass (2026-10-12): **v0.64.4 archive
re-verification** -- released tag `df493530` (run 38256358845), assets
sha256-verified, installed lane-local both platforms; **C-15 + phantom
imports VERIFIED FIXED** (C-15 workaround dropped from probe_quantization);
**XVC-C-13/C-14 + the thread gate re-tested (still red/open)**; the new
hard-error import gate caught stale pre-swap imports in the bench harness +
repro copies (repaired to `xiom.vectors`); first-arm sweep + full batteries
green both platforms; verdicts + closures filed on the bus -> 78th-80th passes: D5 durability delta (kill matrix 6/6 Windows + 6/6 WSL), D6 retention + snapshots (`probe_snapshot` 27/27), D7 multi-segment read path (roll/union queries over active + sealed, tombstone shadowing, bit-exact compaction, opt-in auto-roll policy; `probe_multisegment` 27/27; two gate-caught fixes `2552824` request-path union bypass + `71af343` replay symmetry) -> **81st pass (2026-10-15): v0.64.5 archive re-verification** -- assets sha256-verified and installed lane-local both platforms; **THREAD GATE GREEN on BOTH platforms** (real spawn+join: 3 workers exact sums, worker id != main; marks `M3: join ok 42`; was 0xC0000005/SIGSEGV) -> G phase flips; **C-13 verified fixed** (65 both platforms; m320), **C-14 verified fixed** (bundle build+run 0 both platforms; m278+m298), C-15 + phantom controls stay green; repro sweep 19/19 OK; **Windows battery ALL GATES GREEN** (suite 177/177 x2 + sbom 44 modules unsafe=0 + 44 probes x2 + bench smoke + kill matrix); **WSL battery RED on 6 service/search gates: XVC-C-16** -- v0.64.5 linux-x64 miscompiles the HTTP service `/search` path (v0.64.4 linux + v0.64.5 windows green, bundled-stdlib repro => compiler not stdlib; repro `docs/repro/xv-http-service-linux/`; filed `REL-20261015-2142-xvector`; **v0.64.5 re-pin HELD**); C-13/C-14 items verified+closed on the bus, thread items stay `fixed` pending the C-16 fix per the archive-pass protocol. -> **16th Oct (82nd+):** L-1 mote polish (quickstart + `probe_mote_embedded`, cid-collision fix) + L-2 collection move (`export_collection`/`attach_segment` + segment integrity footer + `probe_collection_move`); reference study 04 (lattice mechanics); lattice-tier wishlist asks relayed; mote/lattice naming + architecture plan + release ownership; stdlib POSIX break filed+verified+closed; C-16 acked (v0.64.6 fixer wave), C-17 open; v0.64.5 re-pin HELD. -> **83rd pass (2026-10-16): README product-tier section** (mote/lattice codenames, usage, features, served quickstart; stale socket/durability/segment rows truthed-up, `bc53af7`); **L-3 ROUTER v1 LANDED** (`src/api/router.xi`: versioned mapping file + strict loader, verbatim forwarding by collection with client-key pass-through, `/health` `/version` `/cluster/mapping` `/cluster/stats` + bare-`/stats` aggregate, retry-on-404 stale-mapping gated on version change + context coverage, in-process transport; `probe_router_2shards` = 48th probe, 72 checks x2 Windows; service-family probes x2; suite 177/177 x2); **XVC-C-18 filed** (object-key reads through a `match` binding return garbage; repro `docs/repro/xv-object-key-iter/`; copy-out workaround; bus `REL-20261016-1541-xvector`); WSL legs HELD (owner resource guidance + C-16); doorbell re-armed (3h); **then L-5 LANDED same day** (`POST /cluster/move` + `/cluster/drain`, compaction-aware export via D7, mapping flip + atomic persist; `probe_move_under_load` 41 checks x2 = 49th probe; affected probes x2 + suite 177/177 x2 + full Windows battery green); **then L-4 LANDED same day** (file-ship replica catch-up + manual promotion runbook; `probe_replica` 24 checks x2 = 50th probe; `probe_reopen_write` 6 checks x2 = 51st probe after finding + fixing a durable reopen-then-write loss in `engine_enable_durable` -- the segment file is the durable frontier; full battery ALL GATES GREEN, 51 probes x2; website tier copy approved on the bus). -> **v0.64.6 RELEASED 20:33Z same day**: installed lane-local (win sha256 `a32bf7fa`); Windows battery ALL GATES GREEN on it (51 probes x2) + C-17 (extended: Semaphore multi-field) + C-18 repros green; WSL bash unavailable (`execvpe` failure) -> WSL legs + the `-1627`/`-1402`/finding closures deferred; `scripts/sbom.ps1` now records the lane-local compiler; pins refreshed (stdlib tree 6375e50 / pin b81430b; packages b0ba2a6). -> **2026-10-17: WSL root-caused** (the default distro had become `docker-desktop`, which has no bash; Ubuntu works with `wsl -d Ubuntu`); v0.64.6 installed on WSL (linux sha `82a7417b`); C-16/C-17/C-18 repros GREEN on WSL; `-1937` custom-home retest clean; **full WSL + Windows batteries ALL GATES GREEN on stdlib `7073a64` + packages `53cba79b` (xiom.http 0.1.8 installed in both lane homes)**; all findings + thread items CLOSED on the bus; **v0.64.6 re-pin COMPLETE**. -> **2026-10-17 afternoon: embedded-tier package gates** -- `xiom.orbitdb` 0.2.1 (Satellite) + `xiom.pulse` 0.2.0 (Beacon) declared in `xiom.toml` and gated (`probe_package_orbitdb` 11 checks; `probe_package_pulse` 8 checks incl. the version-token + 0.2.0 hook seams); `xiom.http` bumped to 0.1.8 (`probe_package_http` green); WSL x2 + Windows x1 each green; **full Windows battery re-run DEFERRED -- the build machine hit paging-pressure spikes (PowerShell spawn failures; the transient suite `compiler exit -1` after "compiled:" was that, not a compiler bug)**; next wrap re-runs the 53-probe battery when the machine is calm. -> **2026-10-17 18:20Z: clean log landed** -- full batteries ALL GATES GREEN BOTH platforms (53 probes x2 + suite + sbom + bench + kill matrix) on stdlib `d6b562a` + packages `b9d28f9a` + xiom.http 0.1.9; **v0.64.7 candidate ref `candidate-v0.64.7-m351` (065481eb4) is in the stdlib/compiler release gates -- NO archive yet** (watch for the cut; then the §1 re-pin protocol). -> **2026-10-17 21:10Z pause for the night**: latest-tree again (stdlib `5686029`, packages `0ddbe0ac`, **xiom.pulse 0.2.1** live; its artifact still reports 0.2.0 -> version-identity bug filed `REL-20261017-2102-xvector`); **Windows battery ALL GATES GREEN (53 probes x2) on the new trees; WSL battery re-run PENDING** (last WSL green was on `d6b562a`); v0.64.7 tag still blocked upstream (m353 residual); doorbell cancelled for the pause. -> **2026-10-18: v0.64.7 RE-PIN COMPLETE** (release 2026-10-17T22:59Z, run 39076930839; win `16a436c4` / linux `153f0cc9` both sha256-verified + installed lane-local both platforms, v0.64.6 kept as rollback; C-16 acceptance repro exit 0 on WSL, C-17 7/7 + C-18 exit 0 on BOTH platforms; full batteries ALL GATES GREEN BOTH platforms (suite 177/177 x2 + 53 probes x2 + sbom 46 + bench + kill matrix) on stdlib `6727526` (pin tag `1271dd5`) + packages `2e7c5524`; suite E001 false positives dropped on 0.64.7; no findings open). -> **2026-10-18: G-1 COMPLETE** (probe upgraded to natural module-level `SyncMutex`/`AtomicInt` globals -- the Int-handle workaround is RETIRED (C-17 fix confirmed); cross-thread producer/consumer 2x200 through a scalar mailbox under the shared spinlock; 14 checks x2 BOTH platforms); **XVC-C-19 FILED** (v0.64.7 compiler HANG on module-level function-call/allocating `var` initializers, shape-sensitive; repro `docs/repro/xv-global-init-hang/`; bus `REL-20261018-1518-xvector`) + channel handle wishlist (`-1518-xvector-2`); next: G-2b accept-loop threads. -> **2026-10-18 ~16:00Z: MOTE PUBLISHED** -- `xiom.vectors` **0.2.0** live in **eco-v0.1.198** (2026-10-18T15:55:48Z; sha256 `130427a5...`; run 39142312352 green; owner-greenlit; registry live-verified; carve from `c858ec1`, 239 files, lattice `api/router`+`api/replica`+`api/httpd` excluded; suite 177/177 x2 on v0.64.7). **The carve found four real library-mode gaps in our pin** (internal `use xiom.vectors;` -> primitives module split; dead `use xiom.core.ids;` in storage/id_map.xi; missing core.shim import in collection/schema.xi's contract; xiom.http.status dep) -- fixed in the carve (`1807615e`); **next session must add a library type-check gate to CI** + port those fixes. G-1 complete; XVC-C-19 open.

---

## 0. STATE (hand-off point)

**Repo:** private, no pushes. HEAD `bc53af7` (README tiers) + this pass's
commits (L-3 router v1 + wrap); tag `v1.0.0-rc.1` still on `530b041`.
**Installed lane-local: compiler v0.64.5** (was v0.64.4; old dirs parked
OUT of the repo: `%TEMP%\kilo\xvector-toolchain-v0.64.4.bak` (+ a second
copy at `%TEMP%\kilo\v0645\toolchain-v0.64.4.bak` from a concurrent
archive-pass session); the WSL backup under `/tmp` was wiped by a WSL
restart -- the v0.64.4 linux archive was re-downloaded on demand for A/B
(sha256 `72a131cc`)). Upstream at install: stdlib `stdlib-v0.64.5` (tag
`092dfa0`, 2026-10-15); at battery time stdlib lane HEAD = `ea1c312b`
(docs snapshot 37) and packages HEAD = `47dc93ea` (2026-10-15).
**v0.64.5 re-pin is HELD**: Windows battery ALL GATES GREEN; WSL battery
RED on the new linux-only XVC-C-16 (service `/search` miscompile; filed
`REL-20261015-2142-xvector`) -- see the 81st-pass slice entry below and
`docs/COMPILER-FINDINGS-XVECTOR.md`.
**Product tiers (owner-picked 2026-10-16):** `xvector-mote` (embedded) /
`xvector-lattice` (scale-out server) -- decision `docs/PRODUCT-LAYERS.md`;
architecture plan `docs/PRODUCT-ARCHITECTURE.md` + execution checklist
`docs/checklists/lattice-v1.md` (**L-0..L-3 + L-5 landed**; L-3 = router v1 with
the in-process transport -- the socket hop waits on the `xiom.http` client
half `REL-20261016-1129-xvector-2`). README carries the tier story. **Release ownership (owner directive 2026-10-16):**
mote registry publication -> coordinate with the packages lane via relay
when package-ready (owner-gated); lattice releases -> ops-owned GitHub
Actions release set.
Recent slices: **G-1 completion (2026-10-18)**: `probe_thread_sync` now exercises the NATURAL concurrency pattern -- module-level imported-type globals (`SyncMutex`, `AtomicInt`; the C-17 fix confirmed, Int-handle workaround RETIRED) + a cross-thread producer/consumer leg (2 real producers x 200 scalar-mailbox handoffs under the shared spinlock; exact totals + per-producer FIFO; 14 checks x2 Windows + WSL); **XVC-C-19 found + filed** (v0.64.7 hangs on module-level function-call/allocating `var` initializers -- shape-sensitive; the same shape in the larger module builds then hangs before `main`; repro `docs/repro/xv-global-init-hang/`; channel handle form wished to stdlib for the channel's own cross-thread leg). + **Package tiers (2026-10-17)**: the registry's embedded/lite products are now consumed and gated -- `xiom.orbitdb` 0.2.1 (ORBITDB Satellite: validated open, WAL-before-ack puts, range, delete, txn savepoint-free commit, checkpoint, close/reopen recovery) and `xiom.pulse` 0.2.0 (PULSE Beacon: request parse + Content-Length framing, neutral default Server token + consumer setter + CR/LF rejection, pre-hook install/clear, header builder); both declared in `xiom.toml`, probes registered in both batteries (53 probes total), `xiom.http` 0.1.8 consumed cleanly; WSL x2 + Windows x1 each green (battery deferred under machine paging pressure). + **L-4 replica v1 (2026-10-16)**: file-ship async catch-up (`replica_ship`: byte-copy the leader checkpoint when its size changed + the delta segment; shipped-frontier watermark in `<follower_ckpt>.ack`) + `replica_lag_estimate` -> `ServiceState.replica_lag` -> `/stats` `replica_lag` + `xvector_replica_lag`; manual promotion runbook (OPERATIONS section 12) walked by `probe_replica` (50th, 24 checks: snapshot/delta/re-snapshot ships, byte-equal reads, lag visibility, kill sweeps, mapping-flip retry onto the promoted home); **durable reopen-then-write loss found + fixed in `engine_enable_durable`** (frontier = segment file, not max(file, in-memory); post-reopen writes survived only after the fix; regression `probe_reopen_write` 51st probe; `probe_wal_segment` expectation updated); WSL spot held. + **L-5 move/drain (2026-10-16)**: `POST /cluster/move` (compaction-aware export -> destination create+attach -> source drop -> mapping flip + atomic persist; a failed persist reinstalls the source; `export_collection` now merges sealed+active via D7, bit-exact) + `POST /cluster/drain` (round-robin off a node, first failure reported); `probe_move_under_load` (49th probe, 41 checks: no acked write lost across a 30-id sweep, stale-cache window == one reload + one retry, sealed/union exactness, drain repoint, admin fuzz + read-key scope); OPERATIONS section 11 + systemd/docker template sketch. + **L-3 router v1 (2026-10-16)**: `src/api/router.xi` -- versioned mapping file + strict loader (refuse-start), verbatim forwarding by collection (client key travels; shards re-check -- defense in depth), router endpoints (`/health`, `/version`, `/cluster/mapping`, `/cluster/stats`, bare `/stats` aggregate), stale-mapping retry-on-404 (accept gated on a version change + full context coverage; one retry when the owner moved), in-process transport (socket hop = follow-up on the `xiom.http` client half); `probe_router_2shards` (48th probe, 72 checks) + routing fuzz; service-family probes x2 + suite 177/177 x2 Windows; WSL spot HELD (owner resource guidance + C-16); **XVC-C-18 found during the slice** (repro `docs/repro/xv-object-key-iter/`). + **L-2 collection move (2026-10-16)**: `export_collection`
(durable roll -> one self-contained segment artifact; source keeps
serving via its sealed entry) + `attach_segment` (fresh cid, no cid
requirement, index config travels) + the segment **integrity footer**
(`z <count> <crc32>`; attach refuses truncated/corrupt/pre-L-2 copies)
+ `probe_collection_move` (47th probe, both batteries) +
`docs/OPERATIONS.md` section 9; staged facts: probe/suite x2 both
platforms, full Windows battery re-run (see commit). + **L-1 mote polish (2026-10-16)**: `probe_mote_embedded`
(the 46th probe) + `docs/MOTE-QUICKSTART.md`; caught + fixed the
**cid-collision regression** (create-after-reopen reused a recovered cid
-> the next recovery silently dropped the earlier collection); WSL legs
HELD on the stdlib wave-146 POSIX build break
(`REL-20261016-1143-xvector`); reference study 04 landed
(`docs/REFERENCE-STUDY-04-LATTICE.md`); lattice-tier wishlist asks filed
(`REL-20261016-1129-xvector` / `-2`). + **G-1 thread + sync smoke (2026-10-16)**: `probe_thread_sync`
(the 45th probe) in both batteries -- spawn/join + 4-thread mutex counter
(exact) + 4-thread atomic counter (exact) + channel contract; new finding
**XVC-C-17** filed (imported-type global pointer-field drop; Int-handle
workaround shipped); + the 81st pass (2026-10-15): v0.64.5 archive
re-verification (thread gate GREEN on BOTH platforms -> G phase flips;
C-13/C-14 verified fixed; C-15 + phantom stay green; repro sweep 19/19 OK;
Windows battery ALL GATES GREEN; WSL battery RED on XVC-C-16 -- repro
`docs/repro/xv-http-service-linux/`, A/B v0.64.4-linux + v0.64.5-windows
green; re-pin HELD), `c828e94` archive-pass docs (concurrent backstop
session), release-watch commits `6222793`..`1311e7b` (2026-10-15,
3h cadence; v0.64.5 hold -> fix -> release), `8cef86d` 80th wrap
completion, `71af343` replay-symmetry fix + `fd61951` D7 docs +
`2552824` M-D7 request-path union fix + `2583351` M-D7 compaction/gate +
`9565ffa` M-D7 union search + `a9d5246` M-D7 plumbing +
`25ee9da` M-D7 design (80th), `48fca54` xvectord D6 policy + `401c120` D6
compact+swap + snapshots (79th),
`5a9b8fd` xvectord durable mode + `6bf292d` kill harness +
`11eb1cd` D5 delta segment/engine (78th),
`390c7a4` v0.64.4 archive re-verification (77th),
`6da4c32` wave-113 re-verification (76th wrap),
`fcd2f64` P2 memory estimate (75th), `200cbc7` G-plan P1, `45e6f5b`
wave-111 closure, `bc53759` thread gate (G groundwork), `95699e9`
VectorDBBench adapter (74th), `039e240` 73rd wrap, `de151d6` http
re-sync (73rd), `bd1d521` 72nd wrap,
`5fce3cf` fast scanner (72nd), `ede0e20` json finding
(71st), `29cfa57` benchmark wrap, `3051160` benchmark starter (70th),
`590310b` pyc hygiene, `7883ca3` Q-serve wrap, `5f6894b` Q-serve (69th),
`404d80c` session note (sdl3 0.8.0
verification + ann greenlight request), `80d8579` ann porter eval,
`d42171c` Q-a2a,
`a7a4d0e` session note (owner directive routing), `69379bc` bus note,
`c25c756` Q-a1 wrap, `ea73829` Q-a1 (feat), `f3aacdf` pin sync,
`9c340df` study 03, `6a25c1d` pin sync,
`1fce9fe` study 02, `a73fc5e` P-a wrap, `9f00836`
P-a (feat: generous level 0 + codec v3), `e04c723` handoff refresh,
`5cbe6ee` study 01, `dc32d73` reference area
(owner grant), `2d9b4d6` stdlib pin sync, `51290a1` vectors wrap,
`c414e2a` vectors swap, `396b239` bus state sync, `e23ee3d` integration
refresh, `a0d631f` rate adoption, `31b95d9` metrics adoption,
`37e9d57`/`3c36f34` XV-ORBITDB-01 fix+wrap, `1db0550` relay bus.
Identity `Lefteris Notas <lefterisnotas@gmail.com>`; conventional
commits, DCO `git commit -s`.

**Toolchain (latest-tracking; record hashes at every wrap):**

| Lane | Version / hash | Path |
|---|---|---|
| compiler | **v0.64.8 pinned -- re-pin COMPLETE both platforms (2026-10-19)**; Windows `out\toolchain` (sha256 `c31d9c46`; v0.64.7 rollback at `out\toolchain-v0647`, sha `16a436c4`) + WSL `~/.xvector-toolchain` (linux sha `a8c003c0`; v0.64.7 rollback at `~/.xvector-toolchain-v0647`, sha `153f0cc9`; **always target `wsl -d Ubuntu`**); release 2026-10-19T17:49Z (tag `4d040604b`, run 39296778685); arena / zero-cap Vec / Vec-drop reclaim + **XVC-C-20**; **C-20 repro GREEN both platforms** (count 1 / second create Err); **G-2b threaded accept loop GREEN** (54th probe x2 both; Windows full battery ALL GATES GREEN; WSL suite 177/177 x2 + `probe_ui`/`probe_concurrency`/service family x2 green; WSL long sweeps were environment-interrupted by repeated VM restarts -- targeted re-runs queued); E001 build warnings reappear (non-fatal, suite green) | lane-local + `%LOCALAPPDATA%\xiom.new` fallback; WSL `~/.xvector-toolchain` |
| stdlib | lane HEAD `750384f` (2026-10-21; **shared-tree block RESOLVED** -- v0.64.8 `--check`/build/suite pass again; bus `REL-20261020-1531-xvector` acked; `XVECTOR_STDLIB_BUNDLED=1` remains a fallback); release pin tag `stdlib-v0.64.8` = `0bf5b75` (asset sha256 `6ea77968...`); **registry publish BLOCKED -- `publisher_not_mapped` for xiom-lang/stdlib (bus `REL-20261019-1755-stdlib`); registry latest remains 0.64.7**; latest-tree protocol enforced each pass | `E:\xiom-lang\stdlib` (= `/mnt/e/xiom-lang/stdlib`; WSL via `wsl -d Ubuntu`) |
| packages | lane HEAD `b133b1a7` (2026-10-21; lane consumes the registry, not this checkout; stdlib block resolved; `xiom.epos` 0.1.0 / `xiom.jev` 0.2.0 are unrelated); **latest set installed both homes: xiom.wal 0.1.0 + xiom.metrics 0.2.0 + xiom.rate 0.2.0 + xiom.http 0.1.9 + xiom.vectors 0.1.0 declared / 0.2.0 installed (MOTE, eco-v0.1.198) + xiom.ann 0.2.0 + xiom.orbitdb 0.2.1 (Satellite; `probe_package_orbitdb`) + xiom.pulse 0.3.1 declared + installed (Beacon; adopted 2026-10-19 -- exact identity + HookCtx + fallback + HEAD-trim probe x2 both platforms)**; the 0.2.1/0.2.2 pulse version-identity note is superseded; `xiom.ann` swap owner-gated; `xiom.vectors` live + swapped | `E:\xiom-packages\packages` |
| xvector | `6b417b2` + this handoff commit (rc tag `v1.0.0-rc.1` = `530b041`) | this repo |

`XIOM_RUNTIME_DIR` retired (env-free builds). `xiom.toml` has
`root = "src"`, `source-roots = ["src"]` (C-PULSE-02 workaround).

**Toolchain isolation (2026-10-10):** the lane pins its OWN toolchain and
package home -- Windows `out\toolchain` + `out\xiom-home`, WSL
`~/.xvector-toolchain` + `~/.xvector-home`; both dev-env scripts set them
and every build/probe/battery inherits it. Reason: concurrent sessions on
this machine deleted the shared `%LOCALAPPDATA%\xiom\packages` home and
parts of `%LOCALAPPDATA%\xiom.new` mid-battery (bus incident
`REL-20261010-1835-xvector`), and a v0.64.3 `xiom pkg install` bug with a
custom `XIOM_HOME` on WSL misplaced the `xiom.wal` install
(`REL-20261010-1937-xvector`). Never build against the shared homes.

**What is DONE and green:**

- Bootstrap: `scripts/` ps1+sh twins (`dev-env`, `build`, `run-suite`,
  `run-probe`, `lib.ps1`), WSL-verified; `images/` for the owner icon;
  `.gitignore`/`.gitattributes`; relay docs.
- **Phase 2 slice (durable in-memory + whole-file WAL):** vector WAL codec,
  payload codec (`[version, fields..., UTF-8 bytes]`), WAL-before-ack for
  upserts AND metadata, `recover_state` replay (torn records skipped),
  compacted checkpoint carrying vectors + payloads, chained reopen, LSN
  monotonicity; whole-file WAL checkpoint on disk landed 2026-10-09 (see
  below). `fsync`/append + file-backed segments still blocked on the stdlib
  fd/fsync gap.
- **Phase 3 slice:** typed `FieldValue`/`Payload`/`FilterExpr`
  (Eq/Range/In/Exists/And/Or/Not + no-payload semantics), `PayloadStore`,
  `set_payload`/`get_payload` (WAL-durable), `search_filtered`
  (pre-filter exact scan, k-bounded), delete clears metadata.
- **Module extraction waves 1-4 (tree final, acyclic):**
  `src/payload/{payload,filter_ast,filter_eval}.xi`;
  `src/types/{dense_vector,metric,neighbor,dimension}.xi`;
  `src/storage/vector_store.xi` (+ vector codec);
  `src/query/search_service.xi`; `src/durability/{wal,recovery,
  write_ahead_events}.xi` (+ `wal_file.xi` 2026-10-09); **wave 4 (final):**
  `src/core/shim.xi`
  (`xiom.vector.core.shim`: CoreError/Counter/ids/predicates) and
  `src/engine/core.xi` (`xiom.vector.engine.core`: VectorEngine + engine_*);
  `src/engine.xi` (`xiom.vector.engine`) is now the **facade only**.
  Dependency order: `core.shim <- engine.core <- engine` (no cycles).
- **Phase 3 refinement (request surface):** `SearchRequest` rewritten against
  the real types + `search_request_set_with_payload`; `SearchHit`/
  `HydratedHits` + `hydrate_hits` in `query/search_service.xi`;
  `engine_search_request` (metric validation, filtered/plain dispatch,
  optional hydration) + facade `search_with_request`; new probe
  `probe_search_request` (real-module gate). Hydration flags were gated in
  that probe only while XVC-C-08 was open; since the v0.64.2 fix the suite
  asserts them too.
- **Phase 3 refinement (payload index):** sorted key index in `payload.xi`
  (rows sorted by field/kind/num/text/id in parallel vectors; maintained on
  put/overwrite/remove; `payload_store_index_len/_exists/_field_count/_eq/
  _range`; float Eq scans the field window for semantic +-0.0/NaN parity).
  Gate `probe_payload_index` (31 checks; stress 6/6 fresh builds). The
  planner (next) consumes candidate ids + `_field_count` selectivity.
- **Phase 3 refinement (planner):** `query/filter_plan.xi` -- exact match
  counts for Eq/Range/Exists (new allocation-free `index_count_eq/_range`),
  `-1` for unknown shapes; `choose_filter_plan` = pre-filter scan by default,
  post only for known count >= k and a majority; `search_knn_filtered`
  executes the post path with a scan fallback. Gate `probe_filter_plan`
  (16 checks incl. equivalence vs a scan reference + fallback; stress 6/6).
- **HNSW multi-layer graph + recall harness (Phase 4):** `src/index/hnsw.xi`
  is real (was a T001 stub): flat parallel arrays (per-(node, layer)
  adjacency rows, no nested Vec[Struct-with-Vec]), deterministic geometric
  level assignment (`ml`; LCG high-bit test -- low bits made level >= 2
  impossible), greedy descent above layer 0 + layer-0 beam honouring `ef`,
  results as `Vec[Neighbor]` with user ids. Tombstone deletes
  (`hnsw_delete`: routers kept, never returned, revive on re-insert;
  `hnsw_live_count`). Gate `probe_hnsw_recall`: n=200 recall@10 300/300 at
  ef=64 and 300/300 at ef=8, cosine 100/100, top level 4; n=800 200/200 at
  ef=64 (avg visited 288/800); after-delete recall 300/300 stray42=0;
  delete-all -> empty; stress 6/6 fresh builds (~0.9s run).
- **Engine HNSW wiring (Phase 4):** `VectorEngine` owns `graph/index_kind/
  ann`; `set_index(kind, params)` validates and builds the graph from the
  flat store; `engine_upsert` feeds `hnsw_insert_ref`, `engine_delete`
  tombstones the graph, `engine_search` + the request plain path route
  through `hnsw_search` (`ef = ann.ef_search`); filtered search stays the
  exact flat scan. In-memory only -- re-apply after `engine_recover`. Gate
  `probe_engine_hnsw`: two engines (flat oracle vs Hnsw) over 150 points,
  engine recall 200/200, delete/revive, filtered exact, Flat switch
  bit-identical, invalid params Err, recover + re-apply; stress 6/6.
- **HNSW compaction:** `hnsw_compact(g, metric)` rebuilds from live nodes
  only (tombstones dropped, edges rebuilt, slots reclaimed); engine
  `compact_index` (Flat -> `Ok(0)`, returns reclaimed). Gates: compact-all
  -> empty graph; 50 deletes -> size/live 150 with recall 200/200 and
  stray_deleted=0; engine-level reclaim 1 + post-compact recall holds.
- **HNSW graph codec:** `hnsw_encode`/`hnsw_decode` (deterministic word
  stream, strict decode: malformed/truncated/tampered -> None; version 2
  carries ef_construction). Gate `probe_hnsw_codec` (9 checks: 100-node
  structural roundtrip + search bit-identical, tombstones, empty graph,
  seven rejection cases, decoded graph mutable). File-backed segments stay
  pending on stdlib I/O.
- **HNSW beam construction:** `hnsw_insert` descends greedily then runs a
  per-layer beam (`search_layer_build`, width = `max(m, ef_construction)`)
  with diversified selection (`select_diverse`); full blocks are pruned with
  the same heuristic. `ef_construction` lives on the graph (default 200;
  setter ignores < 1) and is seeded by `set_index` from AnnParams. Harness:
  n=200 300/300 (ef=64) / 296/300 (ef=8), n=800 200/200,
  deletes/compaction still green, run ~1.8s.
- **HNSW id map + XVC-C-09 workaround:** sorted `id_keys`/`id_vals` map
  (binary-search insert/find; duplicate ids rejected; codec unchanged and
  rebuilds the map; compaction rebuilds it). Wiring it exposed **XVC-C-09**:
  the compiled `engine_set_index` segfaulted on WSL while Windows stayed
  green; fixed by building the graph in a local then assigning `eng.graph`
  once. Repro pinned at `bca8b7f`: `docs/repro/xv-wsl-nested-field/`.
- **Workaround pins + unwind decision (slice 5):** new per-build pin
  `probe_result_shapes.xi` gates the whole XVC-C-04 shape matrix (incl. the
  real engine path) on every build -- 8/8 fresh builds Windows + 2/2 WSL;
  `probe_bind_semantics` pins C-01 (8/8 + 2/2). Decision: KEEP the
  `SearchHits` wrapper (zero-cost, public API, C-08/C-09 family still open)
  and KEEP the suite's direct dispatch; revisit at the next compiler
  archive.
- **HNSW+filter integration:** `hnsw_search_filtered` (ANN fetch `ef_search`
  wide + matching subset; falls back to the exact flat filtered scan when
  under-filled) behind `engine_search_filtered` and the request-driven
  filtered branch; Flat keeps the planner. Gate `probe_engine_hnsw`:
  majority filter k-filled 8/8 with recall 80/80 vs the oracle; 1- and
  3-match filters fall back bit-identically; zero-match empty; stress 6/6.
- **Fuzz gate + decoder hardening:** new `probe_fuzz_codecs.xi`
  (deterministic random/mutated/truncated streams into `payload_decode`,
  `hnsw_decode`, WAL replay + chained checkpoint). It found **XVC-C-10**:
  `hnsw_decode`'s inline pad loop segfaulted at `m >= 512`; fixed by moving
  the pad step behind `pad_adj_slots` and adding strict bounds
  (`m <= 512`, `count <= words.len()`). Repro pinned at `e0b1f7f`:
  `docs/repro/xv-decode-pad-loop/`. Gate: 400+400+200 cases green,
  invariants hold on every `Some`, recovery keeps exactly the valid
  records; stress 6/6.
- **Mixed-workload soak:** `probe_soak_mixed.xi` (400-point Hnsw
  collection, 600 deterministic ops: 311 upserts / 115 searches / 63
  filtered / 61 payload sets / 50 deletes) with per-op bookkeeping
  invariants (search live/bounded/sorted/unique; filtered hits match the
  bucket; Ok flags == presence), periodic consistency + compaction, and
  final + chained recovery checks. ~2.5s; stress 4/4. NOTE: op/id/bucket
  selection uses LCG HIGH bits (low-bit residue 8 was unreachable -- the
  payload branch never ran; same degeneracy class as the level fix).
- **Latency metrics + release-prep (slice 4/J):** `hnsw_build_ops`
  (construction distance-op proxy; n=200: 62,129, bounded 4*n^2) and a
  per-ef visited/recall table in the harness (ef=8 -> 97/100 @ 63 visited;
  ef=16/32/64/128 -> 100/100 @ 84/126/171/196). Release-prep:
  `scripts/ci.ps1` + `scripts/ci.sh` (full battery, aggregated exit; both
  green end-to-end this pass), `VERSION` (0.1.0-dev), a SHA-pinned
  `.github/workflows/ci.yml` draft (activates with self-hosted runners) and
  `docs/RELEASE-CHECKLIST.md` (owner-gated flow).
- **Upsert update-in-place fix (found during E-stretch recon):**
  `index_add` used to reject an existing id and keep the OLD vector, so
  re-upserting silently diverged from the HNSW graph (which updates in
  place) and compaction reverted updates; recovery also kept the first
  vector. Now it updates in place (WAL replay matches live behavior).
  Regression gate in `probe_vector_store` (size stays, get_point/search
  see the NEW vector bits, recovery keeps the latest).
- **Index-driven candidates + compound upper bounds (E stretch):** store
  gains a sorted id -> slot map (O(log n) `index_get`/`index_add`/
  `index_remove`, swap-remove updates the moved slot); `filter_plan` gains
  plan 3 (index: exact Eq/Range/Exists candidates, incl.
  `payload_store_index_field_ids`) and `filter_matching_upper` for And/Or/
  Not (post when the bound is a majority, scan otherwise);
    `search_knn_filtered` executes the index plan with distances only for
    matches. Gate `probe_filter_plan` (20 checks: plan codes, upper bounds
    And=3 Or=1 Not=2 In=-1, index equivalence bit-identical to the scan
    reference).
- **Durable collection manifest:** `create_collection`/`set_index` log a
  `ManifestUpdate` record (`[version=1, dim, metric_code, kind_code, m,
  ef_construction, ef_search]`); `engine_recover` restores dim/metric/index
  kind/params from the latest manifest (rebuilding an Hnsw graph) without a
  manual `set_index`; `wal_writer_checkpoint_from` carries it forward, so
  chained recovery keeps the config; legacy/malformed logs fall back to the
  caller config + Flat. Gates in `probe_engine_hnsw` (23 checks).
- **HNSW update re-linking:** re-inserting an existing id now refreshes the
  node's edges for the new vector (per-layer beam through the old
  structure + diversified replacement; connect factored into `beam_select`/
  `apply_layer_edges`, construction behavior-identical). Gate: recall@10
  200/200 after 60 in-place updates vs the flat oracle (`probe_hnsw_recall`,
  size/live unchanged).
- **Kill-recovery acceptance:** `probe_kill_recovery.xi` proves the crash
  guarantee at the WAL model level -- for every prefix of a 46-record
  scripted log, recover(prefix) + apply(record t) == recover(prefix +
  record t) (store bits, payloads, config); same on the compacted
  checkpoint log (28 records); full recovery equals the live engine; empty
  log and corrupt-final-record cases hold. ~120ms; batteries then ran 17
  probes (18 since the file-WAL probe, below).
- **Multi-key intersections:** the index plan serves And of indexable
  clauses (Eq/Range/Exists) via per-clause candidate intersection;
  `choose_filter_plan` routes answerable compounds to the index when the
  upper bound is selective or < k (`filter_index_answerable`). Gate:
  planner probe 23 checks (And(grp=1,tier=1) -> index, {1,5} bit-identical;
  disjoint -> empty). NOTE (compiler quirk): a private helper with two
  `&Vec[Int]` params reported T001 undefined-second-parameter in three
  shapes; the intersection is inlined in the And arm.
- **File-backed WAL (whole-file checkpoint):** new
  `src/durability/wal_file.xi` -- `wal_persist(w, path)` writes a text
  checkpoint (header + one line per record: `lsn op key value timestamp
  payload_len [words...]`) and `wal_load(path)` is a byte-level,
  torn-tail-safe prefix load (longest run of complete valid records;
  missing/garbage/empty -> empty). Built on the stdlib whole-file APIs
  that exist today (`write_file_bytes`/`read_file_bytes`/`file_exists`/
  `file_size`); no fsync/append yet, so it is a checkpoint rewrite at
  quiescent points, not a delta log. Gate `probe_wal_file`: roundtrip
  equality vs the live WAL, kill/reopen (== live incl. Hnsw config),
  overwrite persistence, 9-point truncation sweep with per-cut prefix
  checks, record-boundary cuts, missing/garbage/empty files. Both
  batteries now run 18 probes. Found **XVC-C-11** (`io.read_file` content
  does not survive in some units -- `slice.str_bytes(s)` = 0 bytes for a
  written 11-/1771-byte file; silent wrong data) and **XVC-C-12**
  (`io.read_file_bytes` aborts on files of <= 8 bytes: `contract
  violated: ensures at 947:12`). Repro:
  `docs/repro/xv-stdlib-file-read-defects/`; workarounds: read bytes and
  parse byte-wise (never handle file content as a Str), guard with
  `file_size < 25` (semantically exact for a WAL).
- **v0.64.2 re-test + workaround reverts (31st pass, 2026-10-09):** all
  relayed fixes verified on the tag archive (`c51170a6`, Windows + WSL).
  **C-07:** `Str::from_utf8(&Vec[UInt8])` compiles and returns correctly;
  the payload codec (`src/payload/payload.xi`) and suite mirror reverted to
  the `&` spelling. **C-08:** trailing-scalar repro exit 0, all 14
  `variants.xi` green; the suite hydration mirror is restored and asserts
  the trailer `has_payload` flags (suite 168 -> 169). **C-10:** the inline
  pad shape no longer segfaults; `pad_adj_slots` + strict bounds kept as
  hygiene. **C-11/C-12:** unguarded reads green in a copy of the original
  failing unit; byte parser + `file_size` guard kept as defense in depth.
  **C-09:** repro green on WSL + Windows (local-assign kept; weaker
  re-test). Batteries: suite 169/169 x2 + 18 probes x2, Windows + WSL.
- **Production programme kicked off (2026-10-09):** requirements intake
  (`docs/requirements/production-v1.md`), v1.0 flagship plan
  (`docs/PRODUCTION-PLAN.md`: M-G truth/benchmark, M-D on-disk durability,
  M-Q query surface, M-S server/security, M-O observability, M-P
  performance/scale, M-R release + owner handoff; first-12 slice backlog),
  execution checklist (`docs/checklists/production-v1.md`);
  ROADMAP/README/readiness aligned.
- **M-D1 atomic WAL checkpoint (2026-10-09):** `wal_persist` writes
  `<path>.tmp` then swaps via `io.rename` (platform replace semantics);
  `probe_wal_file` gained 7 fault-injection checks (no temp left behind;
  staged-complete temp and partial temp both leave the previous checkpoint
  intact; completed persist advances the file). Evidence: probe x2 +
  full batteries both platforms.
- **Consumer handshakes (2026-10-09):** `docs/PULSE-INTEGRATION.md` and
  `docs/ORBITDB-INTEGRATION.md` written (API surface + snippets, build/link
  contract + platform matrix, pin/stability + on-disk layout,
  findings/lifecycle incl. C-PULSE-14 RSS notes, conformance proposals,
  cross-asks). PULSE will build `probe_pkg_xvector`; ORBITDB the hybrid
  `probe_hybrid` (1k rows + vectors, join integrity after kill/reopen +
  repair). Bindings relay: accelerators stay GATED (sole unscheduled
  sector).
- **M-Q1 exact range search (2026-10-09):** `search_range_scan` kernel +
  `engine_search_range` + facade `search_range` -- every point within
  `radius` (inclusive), distance-sorted, bounded by `limit`; exact on both
  index kinds; errors for dim mismatch / limit 0 / negative radius. Gate
  `probe_range_search` (11 checks: 72 radius x limit combos vs a local
  brute-force scan, inclusive boundary, radius-0, KNN equivalence, Hnsw
  routing, reopen); suite mirror test added (169 -> 170).
- **M-Q2 batch ops (2026-10-09):** `upsert_many` / `delete_many` /
  `search_many` + `BatchHits` (one set per query, order preserved);
  all-or-nothing validation per call (bad dimension/length/empty leaves the
  engine untouched); delete counts actual removals (missing ids skipped);
  duplicate ids collapse; facade + engine paths. Gate `probe_batch_ops`
  (14 checks incl. recover equality and the Hnsw batch path); suite mirror
  test added (170 -> 171).
- **M-G benchmark harness + baseline (2026-10-09):** `bench/bench_main.xi`
  -- deterministic workloads (W1 ingest, W2 flat knn, W3 HNSW build/recall
  per ef, W4 filtered, W5 batch, W6 range, W7 recovery), integer-only JSON
  report at `out/bench_report.json`, group-calibrated per-op sampling,
  hard-capped loop budgets, `XV_BENCH_STAGE` diagnostics; runners
  `scripts/bench.ps1` / `bench.sh`; **bench smoke (quick) wired into both
  CI batteries**. Baseline committed in `docs/BENCHMARKS.md` (n=5000
  dim-4: flat knn p50 10.7 ms; HNSW ef=32 p50 0.44 ms recall 1.000;
  filtered Eq 1.13 ms; recovery 12.6 s). **Fixed the `wal_persist` O(L^2)
  string builder** (linear `append_bytes`; the builder drove multi-GB
  paging during harness bring-up -- all loops now capped + monitored);
  `probe_wal_file` +4 scale checks (1200-record roundtrip). Native `--icon`
  embedding wired in `scripts/build.ps1` + `images/xvector-icon.ico`
  (compiler m214/v0.64.2; rcedit workaround retired).
- **M-D2 manifest file (2026-10-09):** new `src/durability/manifest_file.xi`
  -- `xvector-manifest 1` text registry (one line per collection:
  `name dim mc kc m efc efs`; names 1..64 chars of `[A-Za-z0-9_.-]`),
  whole-file persist with atomic temp+rename (invalid name/dim/params
  refused, target untouched), byte-level torn-tail-safe load (longest
  complete-entry prefix; header-only = valid empty; missing/garbage =
  invalid; `file_size < 19` reads skipped). Engine: `engine_manifest_save`
  + `engine_recover_file` (facade `save_manifest` / `open_engine`) -- the
  file registry governs the config on open; the in-WAL manifest is the
  migration fallback (shared private `engine_recover_with`). Stable
  metric/kind codes moved to the leaf modules (`metric_code/_from_code`,
  `ann_kind_code/_from_code`); `wal_file` byte helpers (`parse_int_at`/
  `append_bytes`) shared with the new codec. Gate `probe_manifest_file`
  (38 checks: roundtrip/overwrite/valid-empty, invalid refusals, atomic
  staged/partial temp injection, 10-point truncation sweep, malformed-line
  prefixes, save/open wins-vs-fallback matrix, 500-entry scale). **Found
  XVC-C-13** (fixed v0.64.5 / m320; repro now prints 65): `&Str` parameters
  were unknown to the checker (i64 fallback, silent wrong values --
  `first_byte("A")` = 71 Win / 127 WSL); repro
  `docs/repro/xv-str-ref-param/`; lane convention is `Str` by value.
- **M-D3 multi-collection (2026-10-09):** named collections with
  `create_named_collection` / `select_collection` / `drop_collection` /
  `list_collections` / `collection_count` (facade + engine; names 1..64
  chars of `[A-Za-z0-9_.-]`; duplicates, invalid names and invalid dims
  rejected). Per-collection isolation of stores, payloads, index kind and
  ANN params; the ACTIVE collection is materialized in the engine's
  top-level fields and parked entries live in `collections` (snapshot-copy
  discipline, shape-validated on v0.64.2; switches copy once, data ops
  never). Durable: WAL ManifestUpdate v2 config records (record value =
  cid) + v3 drop records; data records stamp the active cid; recovery
  builds every collection, routes data by cid in D3 strict mode (legacy
  logs route to the single collection), overrides configs from the
  manifest file by name, and checkpoints all alive collections.
  `save_manifest`/`engine_manifest_save` now persist the WHOLE registry;
  `open_engine` restores it (file-wins by name). Gate `probe_collections`
  (41 checks). Legacy `create_collection` -> "default" keeps every
  existing consumer green.
- **M-D4 sealed segment files (2026-10-09):** new
  `src/segment/segment_file.xi` -- the sealed-segment codec
  (`xvector-segment 1`; required meta line with seg_id/cid/state/dim/
  metric/index kind/params; `v` vector lines via `vector_encode`; `p`
  payload lines via `payload_encode`; optional `g` Hnsw graph line via
  `hnsw_encode`). Whole-file atomic persist (`<path>.tmp` -> `io.rename`;
  only Sealed/Immutable states accepted; invalid meta/state refused with
  the target untouched); byte-level torn-tail-safe load (complete-record
  prefix; malformed lines stop the prefix; graph best-effort/rebuildable;
  41-byte `file_size` guard). `segment_state_from_code` added; the seal
  drives the REAL lifecycle Mutable -> Sealing -> Sealed
  (`segment_state_can_transition`). Engine: `engine_seal_segment` (active
  collection -> vectors + payloads + graph) and `engine_restore_segment`
  (cid/dim/metric validated; swaps the live state; re-checkpoints the WAL
  through the new shared `engine_checkpoint_from` so a reopen replays the
  restored state). Facade `seal_segment`/`restore_segment`. Gate
  `probe_segment_file` (38 checks). Multi-segment read path + retention
  stay D5/D6.
- **M-Q3 pagination (2026-10-09):** new `src/query/pagination.xi` -- the
  paginated total order is **(distance ascending, id ascending)**:
  `search_page_scan(idx, query, k, offset)` returns ranks [offset,
  offset+k); `search_after_scan(..., k, after_id)` returns the next k ranks
  strictly after the CURRENT position of `after_id` (its live vector defines
  the cursor distance; `None` when the id is gone). Both scan the raw store
  (exact on Flat AND Hnsw; ANN widening is M-P) with a bounded collector
  carrying the id tie-break. Engine `engine_search_page` /
  `engine_search_after` (facade `search_page` / `search_after`; missing
  cursor -> `Err(NotFound)`). Gate `probe_pagination` (22 checks: page
  reconstruction without gaps/dupes, exact tie clusters {1,7,8} /
  {2,15,16,17} id-ascending, cursor walks incl. tie boundaries, refusals,
  Flat/Hnsw parity, pages after recovery, deleted cursors).
- **M-Q4 delete-by-filter (2026-10-09):** `engine_delete_filter` + facade
  `delete_filter` -- remove every live point matching a typed filter.
  Planner-driven: index-answerable shapes (Eq/Range/Exists/And-of-those)
  resolve candidates from the sorted payload index (each verified);
  In/Or/Not scan the live store. Ids are collected BEFORE mutating (store
  shifts cannot skip points) and applied ascending (plan-independent WAL)
  through the gated single-delete path: per-point WAL record, graph
  tombstone (Hnsw), payload + index cleanup. Nothing matching -> Ok(0).
  Gate `probe_delete_filter` (26 checks: eq/range/exists/in/not/or/and
  plans, idempotence, index cleanup, match-none/ match-all, lsn delta per
  removal, recovery + chained recovery, Hnsw tombstones + compaction +
  search exclusion, multi-collection isolation).
- **M-Q5 index admin (2026-10-09):** `engine_collection_stats` + facade
  `collection_stats` -- per-collection stats (name/cid/dim/metric/index
  kind/ANN params, live points, payloads, Hnsw nodes + tombstones, shared
  WAL lsn); the active collection reports from the live fields, parked
  collections from their registry entries (no switching); unknown ->
  Err(NotFound). `engine_rebuild_index` + facade `rebuild_index` -- admin
  rebuild from the flat store with `IndexStats` (kind/points/nodes_before/
  nodes_after/reclaimed): Hnsw = fresh graph over live nodes (tombstones
  reclaimed), Flat = no-op with zeroed stats; `compact_index` stays the Int
  wrapper. Gate `probe_index_admin` (20 checks: config/counts exactness,
  tombstone accounting, rebuild stats/idempotence/search equality vs a
  flat twin, parked-vs-live agreement, set_index transitions,
  compact_index compat, lsn/points movement, recovery consistency).
- **M-Q6 request extensions (2026-10-09):** `SearchRequest` gains `mode`
  (`SearchMode.Knn | Range`), `radius` (range mode; `top_k` = inclusive-
  radius limit), `offset` (knn page ranks) and `after_id` (knn cursor,
  -1 = none), with setters `set_mode/set_range/set_page/set_after`;
  defaults are the old plain-knn behavior. Dispatch: Range -> exact range
  path (hydrated); filters/pagination are Knn-only and rejected loudly in
  range mode; `offset`+`after_id` mutually exclusive; pagination does not
  combine with filters yet; cursor keeps `Err(NotFound)`. Batch:
  `SearchBatchRequest` + `HydratedBatch` + `search_batch_with_request`
  (one HydratedHits per request, order preserved, all-or-nothing).
  `probe_search_request` extended to 24 checks (range radii 0.5/1.0
  inclusive + hydration, range refusals, page/cursor dispatch matching
  the kernels, mutex + filter refusals, batch order/empty/abort).
- **M-G1 reference oracle (2026-10-09):** new `probe_reference_oracle`
  (22 checks) -- an INDEPENDENT Float64 oracle (own loops over the raw
  Float32 storage, `math.sqrt` in Float64, no `vector_distance` calls):
  pairwise kernel agreement for cosine/dot/euclidean (780 seeded pairs
  each; measured deviations at Float32-ulp scale: 1.70e-07 / 9.83e-07 /
  5.06e-07, bit-identical Windows/WSL), metric axioms (exact symmetry;
  self-distance l2==0 / cosine~0 / dot==-|v|^2; euclidean triangle
  inequality on engine values; cosine bounds [0,2] + exact x2 scale
  invariance; zero-vector cosine guard == 1.0), and the ranked search
  paths vs the oracle ranking (top-5 rank exact per metric; hit
  distances within tolerance; page ranks 5..12; cursor ranks 7..14;
  inclusive-range subset at a midpoint radius + engine-distance boundary
  inclusion; Hnsw recall@5 == 5/5 + distance fidelity).
- **M-S1 HTTP service skeleton (2026-10-09):** new `src/api/http_service.xi`
  -- transport-agnostic `http_service_handle(eng, raw) -> response`
  (parse -> route -> JSON -> serialize; bytes in, bytes out; no sockets
  until the `xiom.net` proof, C-PULSE-02). Strict HTTP/1.1 parsing (CRLF
  framing, lowercased headers, Content-Length must match the body
  exactly; incomplete -> 400 "incomplete request", trailing -> 400).
  Endpoints: GET /health, GET/POST /collections, GET/POST/DELETE
  /collections/{n}/points, POST /search (knn/range/page/batch), GET
  /stats?collection=; honest statuses 400/404/405/409/500. Uses the
  stdlib JSON engine with QUALIFIED calls (`json.json_*`): unqualified
  names misresolve to the parent `xiom.serialize` helpers in this unit
  (BUG 25 #1 -- documented in the json module header) and silently built
  empty string values; numeric request fields are strictly typed. Two
  real parser bugs found via the probe: the method was validated but
  never stored, and the header scan dropped the final header line
  (Content-Length). Gate `probe_http_service` (40 checks).
- **M-S2 service config/limits/errors (2026-10-09):** `ServiceConfig`
  (max_request_bytes 65536 / max_top_k 1000 / max_batch 256 / max_dim
  1024) + `service_config_from_env` (XVECTOR_MAX_*; malformed ignored)
  + `service_config_load` (key=value file; comments; unknown keys
  ignored; malformed line -> valid=false with good lines kept).
  `http_service_handle_cfg` enforces limits (413 size/batch before/at
  routing, 400 named top_k/dim; boundary requests accepted); every error
  is `{error,kind,status}` with stable kinds, and `core_err_response`
  maps the full CoreError enum. `http_service_shutdown(eng, wal_path)` =
  drain + whole-file WAL checkpoint (false when unwritable). Gate
  `probe_service_limits` (27 checks).
- **M-S3 auth + rate limiting (2026-10-09):** `ApiScope { Read; Write;
  Admin }` (ordered) + `ServiceAuth` (keys 8..128 of `[A-Za-z0-9_.-]`,
  duplicates rejected; first key enables; disabled default in embedded
  mode); lookups via the stdlib constant-time comparator
  (`xiom.crypto.mac.constant_time_eq`); `service_auth_parse_list` /
  `service_auth_from_env` (`XVECTOR_API_KEYS`). Route scope map (/health
  public; POST /collections Admin; points POST/DELETE Write; else Read);
  401 unauthorized / 403 forbidden / 429 rate_limited kinds. Token-bucket
  `RateLimiter` (capacity + refill/sec, explicit clock, `last_ms = -1`
  sentinel); `ServiceState { cfg; auth; rate }` +
  `http_service_handle_state` (rate -> parse -> auth/scope -> route;
  auth-off == handle_cfg). Gate `probe_service_auth` (24 checks).
- **M-S4 security pass (2026-10-09):** `docs/SECURITY.md` (assets, trust
  boundaries, secure-defaults table, threat/control matrix, dependency +
  SBOM statement, no-unsafe audit, honest out-of-scope list).
  `probe_http_fuzz` (14 checks: 1200 seeded mutations + 1300 random
  streams all well-formed; targeted abuse -- empty/lying-CL/header-flood/
  30 KB header/60 KB unbalanced JSON/8000-deep nesting/NUL/500-segment
  path/300-burst; phase marks in `out/fuzz_mark.txt` for forensics).
  **Found + fixed a remote stack-exhaustion DoS**: the stdlib `json_parse`
  recurses per nesting level, so ~60 KB of `[` (inside the body limit)
  crashed the service with an access violation; the HTTP edge now
  pre-scans with `json_depth_ok(body, 64)` (string-aware, linear) and
  rejects deeper payloads with 400 -- the stdlib gap is filed in
  `docs/STDLIB-WISHLIST-XVECTOR.md`. `scripts/sbom.ps1`/`sbom.sh` emit
  `out/sbom.json` (compiler, stdlib pin, per-module sha256, unsafe=0) and
  FAIL on any `unsafe` in src/; both batteries now run the SBOM + unsafe
  gate.
- **M-O observability core (2026-10-09):** new
  `src/observability/metrics.xi` -- fixed-bucket latency `Histogram`
  (1/5/10/50/100/500/1000 ms + `+Inf`; `_sum`/`_count`/p50/p95/p99),
  `ServiceMetrics` (requests/errors/search_ops/upsert_ops/auth_failures/
  rate_limited counters + global and search histograms) and a bounded
  JSON-log `LogRing` (method/path/status/ms/slow, hostile strings
  sanitized, oldest-first eviction + `dropped`). Service: public
  `GET /metrics` (prometheus text: counters, cumulative buckets +
  percentiles, live gauges collections/points_active/lsn), `/health`
  gains `ready:true`, and `http_service_handle_state` instruments every
  request (status-derived counters, latency, op classification, one log
  line). Worked around the XVC-C-09 family AGAIN: nested-field mutation
  through a `&mut` param (`st.metrics.counter`) silently does not
  persist -- the wrapper copies the metrics struct out and writes back
  once. `docs/OPERATIONS.md` runbook (start/stop, config, monitoring +
  alerts, backup/restore drill, failure domains, migration, diagnostics).
  Gate `probe_metrics` (23 checks).
- **M-R release candidate v1.0.0-rc.1 (2026-10-09):** `VERSION` =
  `1.0.0-rc.1`; `docs/RELEASE-NOTES-v1.0.0-rc.1.md`;
  `docs/sbom-v1.0.0-rc.1.json` (44 modules, unsafe=0);
  `docs/OWNER-HANDOFF.md` (repo public / runners / rulesets / publish
  flow / benchmark protocol + gated-pivot table + evidence index);
  `docs/RELEASE-CHECKLIST.md` audited step-by-step with the repro re-runs
  (9 green, `contract-trap-exit0` exit 1 = fixed symptom, XVC-C-13 open
  by design). Final batteries at the rc commit `5226226`: Windows + WSL,
  ALL GATES GREEN. Tag `v1.0.0-rc.1` annotated (no GPG key on this
  machine; commits carry DCO sign-off). **The owner has been told; the
  public release + benchmark are the owner's actions.**
- **xiom.wal first adoption (2026-10-10):** C-PULSE-02 RESOLVED in v0.64.2
  -- `xiom.toml [dependencies] xiom.wal = "0.1.0"` maps the installed
  package root into the catalog; `xiom.wal` 0.1.0 installed from the
  registry on Windows + WSL (sha256 + ed25519 verified; registry key
  pinned via `xiom pkg trust`, fp `4f:3b:47:f3:ae:17:b1:3c`). Alignment
  verified: op codes 1..7 byte-identical to our codec (8/9/10 txn ops);
  same payload carrier (+ `timestamp`); same LSN semantics; equivalent
  torn-tail outcome. Gate `probe_package_wal` (9 checks: codes, tagged
  roundtrip, LSN resume, torn-tail skip + heal-on-open, missing-path
  open). Design + D5 migration plan: `docs/XIOM-WAL-ADOPTION.md`.
  Discovery: `XIOM_HOME/packages` also carries `xiom.metrics` 0.2.0,
  `xiom.rate` 0.2.0, `xiom.router` 0.1.0, `xiom.http` 0.1.4 -- scheduled
  as gated adoption slices (metrics first).
- **xiom.metrics 0.2.0 adoption (2026-10-10, 55th pass):** second
  registry adoption. `observability.metrics` internals run on the package
  behind the same exported surface (`/metrics` output byte-identical):
  package `Histogram`/`Counter` value types, lane accessors + the
  percentile helper (package SPEC excludes percentiles), the Prometheus
  histogram block moved into the module (consumers never name the package
  types); engine stat counters (`upserts`/`deletes`) moved onto the
  package and the core shim `Counter` was retired -- forced by
  **XVC-C-14** (two same-named struct types across modules shadow each
  other's field layout; clang store reject when incompatible, silent when
  compatible). Minimal repro `docs/repro/xv-counter-type-shadow/`
  (Windows + WSL identical, clang exit 1); relay Addendum 10; bus item
  `REL-20261010-1709-xvector`. Gates: new `probe_package_metrics`
  (12 checks, direct package) + re-gated `probe_metrics` (24 checks incl.
  package min/max/mean alignment); both batteries now **34 probes**.
  Record: `docs/XIOM-METRICS-ADOPTION.md`.
- **xiom.rate 0.2.0 adoption (2026-10-10, 56th pass):** third registry
  adoption. The S3 `RateLimiter` internals run on the package
  `TokenBucket` behind the same API (`rate_limiter_new/_disabled/_allow`
  unchanged; 429 path + the rate-limited counter unchanged). Accuracy
  delta: unearned sub-token remainders are now carried, so fractional
  refill is exact (the lane limiter consumed the whole elapsed span and
  discarded remainders); every gate-visible boundary (capacity drain,
  rate 0, whole-second refill) is unchanged -- `probe_service_auth` (24
  checks) and `probe_metrics` (24) stay green unmodified. Gates: new
  `probe_package_rate` (14 checks: bucket drain/refill/carry/rate 0/
  clamp/retry/cost, fixed window, keyed bucket + keyed window layers);
  batteries now **35 probes**. Record: `docs/XIOM-RATE-ADOPTION.md`.
  Also this pass: orbitdb **closed** the `REL-20261010-1550-orbitdb-11`
  bus item after their verification of the XV-ORBITDB-01 fix; v0.64.3
  **released** by the compiler lane (assets staged + sha256-verified;
  version upgrade + full re-test + release-check verdicts are the next
  pass).
- **compiler v0.64.3 re-pin + isolation (2026-10-10, 57th pass):** v0.64.3
  released (run `38071481303`; tag `v0.64.3` on `a5b87965`), assets
  sha256-verified, installed lane-local on Windows + WSL; full re-test:
  all 12 repro bundles re-run (17/18 single-file probes green), XVC-C-13
  (Win 71 / WSL 127) and XVC-C-14 (clang `xiominput.ll:850`) re-tested
  **UNCHANGED** -> release-check verdicts filed
  (`release-checks/compiler-compiler-v0.64.3`); then the shared-home wipe
  incident hit mid-battery on both platforms: diagnosed (recursive delete
  of the shared homes by concurrent activity), filed as
  `REL-20261010-1835-xvector`, and neutralized for the lane with
  lane-local toolchain + package home; the WSL `xiom pkg install`
  custom-`XIOM_HOME` misplacement was found and filed on the way
  (`REL-20261010-1937-xvector`); final isolated batteries green on both
  platforms. Also recorded: **`xiom.vectors` LIVE (eco 508)** + `xiom.ann`
  extracted by the packages lane (our wishlist items `-9` fixed /
  `-10` acked).
- **xiom.http helper evaluation + adoption (2026-10-10, 58th pass):**
  `xiom.router` 0.1.0 + `xiom.http` 0.1.4 evaluated for the service:
  **`xiom.http.status.http_status_text` ADOPTED** behind a 3-line lane
  adapter (every emitted code keeps its pre-adoption wire text;
  the package has no 507 -> the lane keeps "Insufficient Storage" and
  its "Error" fallback; upstream gap filed `REL-20261010-2002-xvector`);
  **router + parser/types/client NOT adopted** (static 7-route dispatch
  + strict byte pipeline are gate-pinned; full reasons in
  `docs/XIOM-HTTP-EVAL.md`). New `probe_package_http` (5 checks) + the
  `probe_http_service` raw `HTTP/1.1 507 Insufficient Storage` pin
  (41 checks); batteries now **36 probes**. Next adoption candidate:
  **`xiom.vectors` (LIVE)**.
- **xiom.vectors 0.1.0 wiring + fidelity gate (2026-10-10, 59th pass):**
  the registry extraction of THIS lane's own primitives; **all six SPEC
  extraction pins match the current tree byte-for-byte** (byte-exact
  carve; behavior-identical by construction). `xiom.toml` dependency +
  new `probe_package_vectors` (13 checks: distances on
  exactly-representable corpora, normalize, metric codes, dimension,
  top-K ordering/eviction, codec round-trip, torn-skip replay); the
  package's own codec probe runs green from the lane home (bit-exact
  incl. -0.0 / denormal / max). Batteries now **37 probes**. Internals
  swap planned as **one atomic step** (all six surfaces at once --
  partial swaps are an XVC-C-14 short-name hazard; ~45 import sites) in
  `docs/XIOM-VECTORS-EVAL.md`; gated on owner greenlight `-12` + a quiet
  window, sequenced with the `xiom.ann` porter flow.
- **xiom.vectors internals swap EXECUTED (2026-10-10, 60th pass):** the
  atomic change set (51 files: 96 insertions, 409 deletions) put every
  consumer on the package -- 11 source modules + 27 probes now import
  `xiom.vectors`; the five local modules
  (`types/dense_vector|metric|neighbor|dimension`, `query/topk_heap`)
  are deleted; the WAL value codec was stripped from
  `storage/vector_store` (encode/decode resolve through the package
  import). Behavior-identical by construction (pins byte-exact);
  verified by the full batteries on **Windows AND WSL** (suite 171/171
  x2 + sbom + 37 probes x2 + bench smoke), including the
  `probe_reference_oracle` kernel-fidelity and `probe_floatval_roundtrip`
  bit-exact gates. Docs swept to the package paths (SPEC/ARCHITECTURE/
  contracts/core-vs-vector/query-execution/vector-types-and-metrics);
  record: `docs/XIOM-VECTORS-EVAL.md` §3. Also found + filed the
  v0.64.3 diagnostic gap: unresolvable imports are silently ignored
  (`REL-20261010-2124-xvector`; explained part of the shared-home
  incident misdiagnosis).
- **Bus round (2026-10-10, 55th pass):** `REL-20261010-1550-xvector-7`
  (json depth cap) **verified + closed** -- boundary re-run against the
  stdlib checkout (`a16daff`): 128-deep Ok; 129 and 60000-deep Err
  `json_parse: nesting too deep`; Windows + WSL identical; the HTTP
  64-level pre-scan stays as defense in depth. XVC-C-14 filed to the
  compiler lane (bug). Shared-clone note: the bus clone on this machine
  is used by several lane sessions; scope `git add` to your own item
  files (ops item `REL-20261010-1709-compiler` tracks per-lane
  clone/helper proposals; expect interleaved commits).
- **XV-ORBITDB-01 fix (2026-10-10):** relay item from the orbitdb lane on
  the new bus: chained persist/load of a RECOVERED engine's WAL reloaded
  EMPTY because `wal_load` required the first record's LSN to be exactly
  1, while recovered checkpoints resume LSNs (silent vector loss on the
  next open). Fixed in `wal_file.wal_load` (commit `3c36f34`): the first
  record may start at any LSN >= 1, consecutive +1 stepping still
  enforced, torn-tail/corruption behavior unchanged. Gate
  `probe_wal_file` +3 chained checks (persist a recovered checkpoint,
  non-empty reload with the resumed first LSN, second recovery equals
  live). Bus item moved open -> acked -> fixed with the commit ref
  (orbitdb verifies at its next release check).
- **FloatVal workaround unwound** after the v0.64.1 fix: float payload
  gates restored in the suite and probes.
- **P-a generous HNSW level 0 (63rd pass, 2026-10-11):** reference study 01
  F1 applied in `src/index/hnsw.xi` (no vendoring): level-0 capacity
  `m0 = 2*m`, full-block prune to 80% of `m0` (FAISS `prune_headroom` 0.2,
  anti-churn), adjacency rows uniformly `m0`-strided,
  `hnsw_new_full(m, ml, m0)` for explicit capacity (the legacy `m0 = m`
  control graph), codec **v3** (`[3, m, m0, ml, ef, cap, entry, count,
  ...]`; v2 still decodes; strict `m0 < m` / `m0 > 1024`; pad step stays
  behind `pad_adj_slots`). Gate `probe_hnsw_recall` extended: `m0 == 2*m`,
  "generosity engaged" (max L0 degree 26 > m; higher layers <= m),
  reachability 200/200, and a hard clustered corpus (n=300 dim=16,
  6 clusters, midpoint queries at ef=8): generous **285/300** vs legacy
  control **275/300** (strict `>` gate; bit-identical Windows/WSL). The
  FAISS `keep_max_size_level0` fill arm was measured (same hard-corpus
  recall at ~2.5x build work: 150,716 vs 60,852 ops, ~40% more visited)
  and NOT adopted. Costs recorded: n=200 build work 60,852 ops (~legacy
  62,129); per-ef visited 70/93/134/175/197 (legacy 63/84/126/171/196);
  n=800 avg_visited 346 (legacy 288); bench medium build 13.0 -> 14.7 s,
  ef=32/64/128 p50 0.56/0.84/1.44 ms, recovery 16.0 s, recall 1.000
  unchanged. `probe_hnsw_codec` 12 checks (v3 roundtrip + v2 strip
  compat); C-10 pad-loop repro re-run green on v3 (m=512, m0=1024).
  Record: `docs/REFERENCE-STUDY-01-FAISS.md` F1.
- **Q-a1 SQ8 quantization (66th pass, 2026-10-11):** `src/index/quantize.xi`
  (reference study 02 Q-a; no vendoring): `SQ8` trained per-dimension
  ranges (`sq8_train` -> Option; constant dims step 0), FAISS-truncation
  codec (`sq8_encode_one`/`sq8_decode_one`; clamp; strict decode), the
  FAISS SQ distance-computer pattern (`sq8_table_l2`/`sq8_table_ip`/
  `sq8_table_norm2`; `sq8_l2_distance`/`sq8_ip_distance`/`sq8_cos_distance`
  with cosine zero guards), and the sqlite-vec rescore contract:
  `sq8_scan_coarse` (gated deviation tier) + `sq8_scan_rescore` (phase 1
  `k*oversample` capped at 4096 -> phase 2 exact `vector_distance` in
  store-position order -> **bit-identical** to the exact scan). Gate
  `probe_quantization` (17 checks): training determinism/order
  independence, empty/mismatch/decode rejection, roundtrip bound
  (measured `0.99974 * vstep` vs bound `1.0`), clamping, constant dims,
  tables vs exact on decoded vectors (deviation 0), the documented coarse
  bound (0.0257 vs 0.6307), bit-identical rescore for 10 queries x 3
  metrics, determinism, empty store, `k > n`, bytes/vector 32 B f32 vs
  8 B SQ8 (dim 8). Suite Section 16 mirrors the math (177/177 total).
  Q-a2 = segment codec v-next + read-path wiring (lands with D5);
  XVC-C-15 (this slice's compiler finding) filed + fixed around.
- **Q-a2a segment v2 artifact (67th pass, 2026-10-11):**
  `SealedSegment` gains `has_sq/sq/codes` + `sealed_segment_enable_sq`
  (trains SQ8 on the segment's vectors, opt-in); codec **version 2**
  writes `q <vmin words dim> <vstep words dim>` + `c <id> <codes dim>`
  after the graph only when armed (v1 files byte-identical otherwise);
  the loader accepts v1+v2, validates ranges/codes in store order, and
  drops a torn/partial SQ section while keeping the vectors
  (`has_sq` gate). Gates: `probe_quantization` grew to 23 checks (seal +
  enable_sq, v1/v2 persist, load roundtrip of ranges+codes, rescore over
  the loaded artifact == exact for 10 queries, torn q/c drop, byte delta
  35 B/vector text); `probe_segment_file` (38) and the engine probes
  unchanged-green (v1 path byte-identical). Q-a2b (read-path wiring)
  lands with D5.
- **Q-serve runnable server (69th pass, 2026-10-11):** `src/api/httpd.xi`
  -- sequential-accept socket adapter over the stdlib `xiom.net` layer
  (PULSE pattern): `httpd_read_request` (CRLFCRLF + exact Content-Length,
  4 MiB socket guard), `httpd_once` (30 s dead-peer guard -> service ->
  `TcpStream.write_all` -> close; rc 0/1/-1, quit on `X-Xvector-Quit`),
  `httpd_serve` + `main` (`--bind/--port`, `XVECTORD_BIND/PORT`) ->
  **`xvectord.exe`**. Gates: `probe_http_server` (10 checks over real
  sockets in one process) green x2 Windows + WSL; **curl user test**:
  `/health` -> create `docs` -> upsert 3 -> `POST /search` k=2 returns
  id 1 (0.0061) then id 2 -> `/stats` points 3 lsn 4 -> quit -> clean
  exit. First user-testable artifact; next candidates: a vector-bench
  adapter (ann-benchmarks/VectorDBBench-style client) + the version
  endpoint (S6), the ann swap (greenlight pending), Q-a2b (D5).
- **Benchmark integration + API completion (70th pass, 2026-10-11):**
  `GET /version` (`{"name","version","api"}`, public);
  `POST /collections` accepts `{"index":"hnsw"|"flat","m",
  "ef_construction","ef_search"}` (calls `engine_set_index`; the kind is
  echoed); `/search` accepts a per-request `"ef_search"` (new
  `engine_set_ef_search` in core: validated 1..4096, no rebuild, no
  manifest write; next select restores the configured beam); `xvectord`
  now applies the documented `XVECTOR_MAX_*` service limits per request
  (`service_config_from_env` in `httpd_once`; socket guard 32 MiB).
  **`bench/adapters/`** (the owner-requested starter): stdlib
  `xvector_client.py` (urllib; no numpy/requests), ann-benchmarks
  drop-in `module.py` + `config.yml` (metric map angular->cosine /
  euclidean / dot; `ef_search` sweep 16..256; 0-based ids; batched
  upserts sized by `XVECTOR_BATCH`, default 128), and `smoke.py` --
  **live green on a default-cap server: version -> HNSW create ->
  400-pt batched upsert -> recall@10 1.000 at ef>=64, 0.940 at ef=8 ->
  duplicate 409**. Gate `probe_http_server` now 15 checks (version, ef
  override + rejection, hnsw create/search). F 96 -> 100 (its last item
  shipped); overall 81.80 -> 82.12 -> 82 %. Next adapter: VectorDBBench
  client over the same surface.
- **stdlib finding: json_parse quadratic (71st pass, 2026-10-11):** the
  first HTTP-path benchmark (5k x dim-25) exposed it: `json_parse` of
  numeric payloads is quadratic (2.5k/5k/10k/20k numbers ->
  248ms/1.10s/4.77s/17.9s; the 50k-number 382KB upsert body -> 83.7s,
  ~88% of the request; in-process engine insert is 2ms/vector).
  Repro bundle `docs/repro/xv-json-parse-quadratic/` (self-contained
  byte-buffer input, sweep + a 5s gate on 20k numbers, exit 1 pre-fix);
  filed to stdlib (`REL-20261011-1453-xvector`, severity high) with
  hypotheses and the string-vs-tokens discriminator; recorded in
  `docs/BENCHMARKS.md` + the adapter README. **Next slice: lane-local
  fast numeric scanner for the upsert hot path** (benchmarks run
  regardless of the stdlib fix timeline; the adapter/browser paths
  already default to safe batch sizes).
- **Upsert hot-path fast scanner (72nd pass, 2026-10-11):**
  `src/api/json_fast.xi` -- byte-level scanner for the canonical
  `{"ids":[...],"vectors":[[...]]}` body (strict grammar mirror; inline
  decimal accumulation; conservative bounds: 15 significant digits,
  |exp| <= 22, else None -> strict generic path) + `HttpRequest.body_bytes`
  (linear byte copy; one `from_utf8` keeps the Str for the strict path)
  + the dispatch fast branch behind `ServiceConfig.fast_upsert`. Gate
  `probe_json_fast` (in CI now; 40 probes): **fast vs strict responses
  byte-for-byte equal across 228 cases** (28-case hand matrix + 200
  deterministic byte mutations), 409/404/400 parity, 52k-number body in
  1.7-2.9 s (strict ~84 s). ROOT CAUSE pinned:
  `docs/repro/xv-json-parse-quadratic/probe_strbytes.xi` (400 KB
  str_bytes = ~4 s, quadratic) + README ask filed; measured effect:
  **5k x dim-25 fit via `xvectord` 661 s -> 120 s** (HNSW-build bound,
  ~42 pts/s); search 53-78 QPS. Batteries green both platforms.
- **Re-verification era (73rd pass, 2026-10-11):** `xiom.http` **0.1.6
  re-sync** -- native `507 Insufficient Storage` (sha256 `bb8a5029...`,
  key pinned in both lane homes), the lane special-case retired
  (`status_text` keeps only `Unknown -> "Error"`), `probe_package_http`
  flipped to the native entry + fallback contract (6 checks); gates green
  x2 Windows + WSL. **Wave-111 WIP acceptance**: both
  `docs/repro/xv-json-parse-quadratic` probes exit 0 on stdlib `b8eda7d` +
  WIP (`json.xi E69E0275...` / `slice.xi 874A8F67...` / `string.xi
  36D1F4FF...`): 400 KB `str_bytes` 438 ms (was 3981 ms);
  2.5k/5k/10k/20k-number parses 79/168/343/755 ms (was up to 17.9 s);
  `xvectord` 5k x dim-25 fit **120 s -> 57.4 s** (87 pts/s, HNSW-build
  bound; machine-load sensitive); recall/QPS unchanged. Full batteries on
  the pins: suite 177/177 x2 + sbom (42 modules, unsafe=0) + 40 probes
  x2 + bench smoke (Windows) + WSL spot (suite x2 + http probes) -- ALL
  GREEN (hashes stable before/after). Bus: -2002/-1206/-9/-1835
  verified+closed; WIP signal `REL-20261011-1618-xvector`. Gated pivots:
  fsync chain + full mmap family still stubs; compiler C-15/phantom not
  yet landed (no release past v0.64.3).
- **VectorDBBench client adapter (74th pass, 2026-10-11):**
  `bench/adapters/vectordbbench/` -- drop-in DB client (`xvector_db.py`:
  framework-tolerant; init/ready, create with `drop_old` best-effort,
  batched `insert_embeddings` returning `(count, error)`, `search` with
  `(distance, id)` rows, metric map COSINE/L2/IP; metadata + filters fail
  loudly -- not exposed over HTTP yet) + `smoke_db.py` (direct-mode live
  smoke, 11/11: insert 400/400, recall 1.000/0.930/1.000 at ef 64/8/128,
  unsupported-path + drop-fallback checks) + README (drop-in
  registration + limitations). Shared `oracle.py` extracted (`smoke.py` +
  `quick_bench.py` refactored onto it); client gains `drop_collection`
  (route may not exist; 404/405 tolerated).
- **G-phase thread gate probed (2026-10-11):** `docs/repro/xv-thread-abi/`
  -- real `xiom.thread.spawn[T]` compiles on v0.64.3 (fn-cast accepted)
  but AVs at the runtime entrypoint (Windows `0xC0000005`, WSL SIGSEGV);
  the marks variant localizes it to the worker-entry/join path after
  `spawn` returns (`M2: spawn returned` is the last mark). Acceptance
  pinned (exact sums + distinct worker id; exit 0); bus witness
  `REL-20261011-1627-xvector`; re-run at the next archive (fn-ABI batch
  m263-m265 / `fde5548e`). The concurrency phase stays gated until green.
- **Wave-111 closure (2026-10-11):** stdlib committed the fix
  (`9a2b5ab`; committed hashes == the pre-verified WIP); **both repros
  exit 0 on Windows + WSL** (str_bytes 43/87/174/379 Windows,
  87/177/359/691 WSL; sweep 56/110/220/437 Windows, 103/206/395/799
  WSL); full batteries green on the committed pin (Windows ALL GATES;
  WSL suite 177/177 x2 + probes + `probe_json_fast` 228/228 x2);
  xvectord 5k x dim-25 fit **661 s -> 51.2 s (98 pts/s)**; quick_bench
  recall 0.779/0.960/1.000 unchanged. Acceptance re-pin: the 500 ms
  absolute gate became a linearity bound (20x-ratio + 3 s net) -- the
  platform spread (~380 ms Windows vs ~650-750 ms WSL) is real post-fix
  while scaling is linear on both (pre-fix 34x). Bus: `-1453`/`-1543`
  verified + closed. Upstream note: `str_chars`/`str_code_points` still
  use the strnlen accessors (outside our acceptance).
- **P2 memory accounting (75th pass, 2026-10-11):** `engine_memory_estimate`
  + facade `memory_estimate` + `/stats` `mem_*` fields (per-collection
  store/graph/payloads + engine-wide WAL); documented model
  (`hnsw_memory_estimate` constants; HNSW rows are uniform: `adj` =
  nodes*8*m0, level-independent) with exact deltas; gate
  `probe_memory_estimate` (17 checks x2 Win+WSL); `docs/OPERATIONS.md`
  section 8 (rules of thumb: ~2.3 KiB/point at m=16 dim=25; seal/compact
  triggers). Batteries ALL GATES GREEN with **41 probes x2**.
- **v0.64.4 archive re-verification + re-pin (77th pass, 2026-10-12):**
  the compiler lane released v0.64.4 (tag on `df493530`, run 38256358845;
  assets sha256-verified; batches m254-m275). Installed lane-local on
  Windows + WSL and ran the full re-verification set: **C-15 repro exits 0**
  (all six shapes; the `as Float32` workaround was dropped from
  `probe_quantization` -- 23 checks green x2); **phantom-import controls now
  fail at the import with exactly one clear T001** (`unresolved import
  <path>`; exit 1, no binary) -- and the new hard error immediately caught
  stale pre-swap `xiom.vector.types.*` imports in `bench/bench_main.xi` +
  four repro probes + six diagnostic copies, all repaired to
  `use xiom.vectors;` (commit `390c7a4`); **C-13 still red** (Win 167 /
  WSL 63, expect 65; warning unchanged), **C-14 still red**
  (`xiominput.ll:850` unchanged; Windows clang / WSL opt), **thread gate
  still AVs** (0xC0000005 / SIGSEGV; last mark `M2: spawn returned` -- the
  fn-ABI batch fixed the marshal half only; evidence re-filed
  `REL-20261012-1402-xvector`). 19-probe repro sweep green except the known
  reds (`ctrap` exit 1 = fixed symptom). Full batteries green both
  platforms (Windows suite 177/177 x2 + sbom 42 modules unsafe=0 + 41
  probes x2 + bench smoke; WSL suite x2 + quantization/codec/memory probes
  x2 + strbytes repro). Verdicts on
  `release-checks/compiler-compiler-v0.64.3`; **`-1134` + `-2124` verified +
  closed on the bus**; re-pinned in §0.
- **Production tracker:** `docs/PRODUCTION-READINESS.md` -- weighted
  scorecard, **82 % today** (F 96 -> 100 with version/index-config/ef +
  the benchmark adapters; C 99, D 74, G 25); recompute at every wrap.

**Green evidence (compiler v0.64.5 installed 2026-10-15 lane-local + stdlib
lane `ea1c312b`; latest re-verification = the v0.64.5 archive pass + the
L-1/L-2 slices on top -- Windows batteries green; the WSL archive battery
is red on XVC-C-16, so the v0.64.5 re-pin is HELD):**

- **L-2 collection move (2026-10-16):** `export_collection` +
  `attach_segment` (the offline move primitive; the portable unit is one
  self-contained segment file) + the segment-codec **integrity footer**
  (`z <count> <crc32>`; backward compatible -- old loaders ignore it --
  and REQUIRED by attach, so truncated/corrupted/pre-L-2 copies are
  refused instead of attaching a partial collection). `probe_collection_move`
  (47th probe, both battery lists): export refusals, three bad-copy
  refusals, bit-exact attach (distances + HNSW config m=8/ef_search=16),
  dst persist+reopen, cid freshness (docs+extra survive), src drop +
  reopen consistent. Evidence: probe x2 + suite 177/177 x2 on Windows AND
  WSL; segment-family probes re-green (footer compatibility); full
  Windows battery re-run. `docs/OPERATIONS.md` section 9 = the ops recipe.

- **L-1 mote polish (2026-10-16):** `tests/probes/probe_mote_embedded.xi`
  (46th probe, both battery lists) -- the embedded round trip a mote
  consumer does: open -> create named collection -> upsert -> search ->
  persist (manifest + WAL) -> reopen identical; second collection ->
  routing intact; persist/reopen again with BOTH collections surviving.
  The last leg gates the gate-caught **cid-collision fix**
  (`engine_recover_registry` restores `next_collection = max(cid)+1`, so
  create-after-reopen can never reuse a recovered cid -- the old bug made
  the next recovery's last-wins manifest merge silently drop the earlier
  collection). Evidence: probe x2 + suite 177/177 x2 + full Windows
  battery green. WSL legs held on the stdlib wave-146 POSIX break
  (`REL-20261016-1143-xvector`). Quickstart: `docs/MOTE-QUICKSTART.md`.

- **G-1 thread + sync smoke (2026-10-16, on top of v0.64.5):**
  `tests/probes/probe_thread_sync.xi` joins both batteries as the 45th
  probe. Green on Windows (5/5 stress runs) + WSL (x2 via the battery
  path): spawn/join acceptance (3 workers return exact 10/20/30; worker
  OS thread id != main -- 95160 vs 27468 on one run; available_parallelism
  >= 1); **mutex**: 4 real threads x 500 guarded increments through
  `xiom.sync.mutex` = exact 2000, no lost updates; **atomics**: 4 threads
  x 500 `atomic_fetch_add` = exact 2000; **channel**: same-thread
  cap/FIFO/close contract pinned. Suite 177/177 x2 both platforms.
  Workaround required (XVC-C-17): shared handles travel as Int globals,
  reconstructed locally per worker. Channel CROSS-THREAD leg deferred
  (blocked on XVC-C-17). New finding filed: `REL-20261015-2216-xvector`
  (high). Full Windows battery re-ran clean with the new probe:
  **ALL GATES GREEN (suite x2 + sbom + 45 probes x2 + bench smoke + kill
  matrix)**; one earlier run carried a transient clang-spawn flake on
  `probe_wal_file` (retry x2 green; machine healthy).

- **v0.64.5 archive pass (81st, 2026-10-15):** installed lane-local both
  platforms (tag `84f761c5`, run 38792051847; assets sha256-verified: win
  `bd71e2d3` / linux `246e5e82`). **Thread gate GREEN on BOTH platforms**
  (exit 0: 3 workers return exact sums via join; worker OS thread id
  differs from main; marks variant reaches `M3: join ok 42` -- was AV
  0xC0000005 / `M2: spawn returned`) -> G phase flips. **C-14 fixed**
  (bundle build+run exit 0; xiominput.ll:850 mismatch gone). **C-13
  fixed** (`first_byte(A)=65`, warning gone). C-15 regression clean
  (exit 0); phantom controls exactly one T001 each (exit 1, no binary);
  repro sweep 19/19 OK; **Windows battery ALL GATES GREEN** (suite
  177/177 x2 + sbom 44 modules unsafe=0 + 44 probes x2 + bench smoke +
  kill matrix). **WSL battery RED on 6 service/search gates -- XVC-C-16**
  (v0.64.5 linux-x64 service `/search` miscompile; A/B: v0.64.4 linux +
  v0.64.5 windows green; bundled-stdlib repro => compiler, not stdlib;
  repro `docs/repro/xv-http-service-linux/`; filed
  `REL-20261015-2142-xvector`). Bus: C-13/C-14 verified+closed; thread
  items accepted green but stay `fixed`; **v0.64.5 re-pin HELD.**
- **D7 multi-segment read path (80th pass, 2026-10-13):**
  `probe_multisegment` **27/27** (Flat union bit-exact vs brute force incl.
  2 sealed + active; range/page across sources; sealed-only delete +
  delete_by_filter + resurrection; filtered union; restart bit-exact;
  compaction bit-exact + restart; missing-file counter; policy auto-roll;
  HNSW union recall >= 0.8; diag 50 warm union searches over 60 pts = 6
  ms). Live: policy server (`SEAL_EVERY=50`) sealed serving verified
  end-to-end (self-query ~0 distance, `/stats sealed_loaded=1`, restart
  kept); request-path bypass found + fixed (`2552824`); stock smoke 7/7
  with the policy off; request-path probes green (search_request,
  filtered_search, range_search).
- **D6 retention + snapshots (79th pass, 2026-10-13):** `probe_snapshot`
  **27/27** (compact+swap churn 451 -> 251 records; post-swap
  crash-recovery bit-exact; auto-policy at N commits zero-loss;
  multi-collection bit-exact restore; corrupt meta refused); both
  batteries ALL GATES GREEN (suite 177/177 x2 + sbom 44 modules unsafe=0
  + 43 probes x2 + bench smoke + kill matrix; Windows + WSL); live
  server: policy `every=3` fired auto swaps during the 400-point smoke,
  quit swap committed (`frontier 1063`), restart 400 pts recall 1.000;
  **4000-point snapshot reload 10 ms**.
- **D5 durability delta (78th pass, 2026-10-12):** `probe_wal_segment`
  **38/38**; **kill matrix 6/6 Windows** (acked 99-213 per run) + **6/6
  WSL** (acked 25-36), missing=0 both platforms; durable server home
  restart-verified (smoke 7/7 + 400 points recall@10 1.000); regression
  probes `vector_store`/`kill_recovery`/`payload_recovery`/
  `delete_filter`/`batch_ops`/`collections` green; stdlib wave-115
  durability smoke all green + wave-117 `truncate_fd` verified in-lane
  (10 -> 4 bytes).
- **v0.64.4 archive pass (77th, 2026-10-12):** Windows `scripts\ci.ps1` ->
  `ci: ALL GATES GREEN` (suite **177/177 x2** + sbom **42 modules, unsafe=0,
  compiler v0.64.4** + **41 probes x2** + bench smoke; exit 0). WSL: suite
  **177/177 x2** + `probe_quantization` x2 + `probe_hnsw_codec` x2 +
  `probe_memory_estimate` x2 (all green) + strbytes repro exit 0.
  Re-verification set: C-15 repro exit 0 (Win + WSL; all six shapes);
  phantom controls -> exactly one `error[T001]: unresolved import '<path>'`
  each, exit 1, no binary (Win + WSL); C-13 red (Win 167 / WSL 63, exit 1);
  C-14 red (clang/opt mismatch at `xiominput.ll:850`, exit 1); thread gate
  `-1073741819` (Win) / SIGSEGV (WSL), last mark `M2: spawn returned`.
  19-probe repro sweep: `ctrap` exit 1 (fixed symptom) + all other
  single-file probes exit 0 after the stale-import repair (`390c7a4`);
  C-13/C-14/thread-gate are the documented reds. Assets: sha256-verified
  against the release `SHA256SUMS` (windows-x64 `44a41aea...`, linux-x64
  `72a131cc...`).

- `scripts\run-probe.ps1 tests\probes\probe_engine_import.xi -Runs 2` green
  (the new-module import gate: `xiom.vector.engine` + `xiom.vector.engine.core`
  in one consumer).
- `scripts\run-suite.ps1 -Runs 2` -> **171/171 passed** twice, exit 0;
  WSL `bash scripts/run-suite.sh 2 240` -> **171/171 x2**.
- **v0.64.2 re-test pass (31st):** suite **169/169 x2** + 18 probes x2 on
  Windows and WSL, ALL GATES GREEN; repro bundles: C-07 exit 0, C-08 probe
  + 14 variants exit 0, C-10 exit 0, C-11/C-12 green in the original
  context unit, C-09 green on WSL; suite W004 count 0 (C-03).
- **M-Q2 batch pass:** suite **171/171 x2** + **20 probes x2** (Windows +
  WSL), ALL GATES GREEN; new `probe_batch_ops` (14 checks) plus the batch
  ops suite mirror test.
- **M-D2 manifest pass:** suite **171/171 x2** + **21 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_manifest_file`
  (38 checks, atomic/torn-tail/fallback matrix) wired into both batteries;
  WSL spot x2 bit-identical diagnostics.
- **M-D3 collections pass:** suite **171/171 x2** + **22 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_collections`
  (41 checks) wired into both batteries; WSL spot x2 bit-identical. No
  regression across the recovery rewrite (kill-recovery prefix exactness,
  wal_file, payload/soak/engine probes all green).
- **M-D4 segment pass:** suite **171/171 x2** + **23 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_segment_file`
  (38 checks: atomic temp injection, 14-point truncation sweep, seal/
  restore bit-exact search, WAL durability after restore) wired into both
  batteries; WSL spot x2 bit-identical.
- **M-Q3 pagination pass:** suite **171/171 x2** + **24 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_pagination`
  (22 checks) wired into both batteries; WSL spot x2 bit-identical.
- **M-Q4 delete-filter pass:** suite **171/171 x2** + **25 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_delete_filter`
  (26 checks) wired into both batteries; WSL spot x2 bit-identical.
- **M-Q5 index-admin pass:** suite **171/171 x2** + **26 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_index_admin`
  (20 checks) wired into both batteries; WSL spot x2 bit-identical.
- **M-Q6 request-extensions pass:** suite **171/171 x2** + **26 probes x2**
  + bench smoke (Windows + WSL), ALL GATES GREEN; `probe_search_request`
  extended 10 -> 24 checks (probe-only gate; suite mirror untouched --
  the mirror is a standalone re-implementation); WSL spot x2
  bit-identical.
- **M-G1 reference-oracle pass:** suite **171/171 x2** + **27 probes x2** +
  bench smoke (Windows + WSL), ALL GATES GREEN; new
  `probe_reference_oracle` (22 checks) wired into both batteries; WSL
  spot x2 bit-identical (same Float32-ulp deviations).
- **M-S1 service pass:** suite **171/171 x2** + **28 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_http_service`
  (40 checks) wired into both batteries; WSL spot x2 bit-identical.
- **M-S2 limits pass:** suite **171/171 x2** + **29 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_service_limits`
  (27 checks) wired into both batteries; WSL spot x2 bit-identical.
- **M-S3 auth pass:** suite **171/171 x2** + **30 probes x2** + bench
  smoke (Windows + WSL), ALL GATES GREEN; new `probe_service_auth`
  (24 checks) wired into both batteries; WSL spot x2 bit-identical.
- **M-S4 security pass:** suite **171/171 x2** + **SBOM/unsafe gate** +
  **31 probes x2** + bench smoke (Windows + WSL), ALL GATES GREEN; new
  `probe_http_fuzz` (14 checks) wired into both batteries; the JSON depth
  guard fixed a found stack-overflow DoS; WSL spot (sbom.sh + fuzz x2)
  bit-identical.
- **M-O observability pass:** suite **171/171 x2** + **SBOM/unsafe gate** +
  **32 probes x2** + bench smoke (Windows + WSL), ALL GATES GREEN; new
  `probe_metrics` (23 checks) wired into both batteries; WSL spot x2
  bit-identical.
- **M-R release-candidate pass:** final batteries at commit `5226226`
  (v1.0.0-rc.1): suite **171/171 x2** + **SBOM/unsafe gate** + **32 probes
  x2** + bench smoke on **Windows AND WSL**, ALL GATES GREEN; all primary
  repro bundles re-run at v0.64.2 (expected statuses); checklist + owner
  handoff + release notes committed; annotated tag `v1.0.0-rc.1`.
- **xiom.wal adoption pass:** suite **171/171 x2** + **SBOM/unsafe gate** +
  **33 probes x2** + bench smoke on **Windows AND WSL**, ALL GATES GREEN
  with the registry dependency active in every build; `probe_package_wal`
  (9 checks) wired into both batteries; WSL spot x2 bit-identical.
- **XV-ORBITDB-01 fix pass:** suite **171/171 x2** + **SBOM/unsafe gate** +
  **33 probes x2** + bench smoke on **Windows AND WSL**, ALL GATES GREEN;
  `probe_wal_file` gained the three chained-reopen checks; the relay item
  is `fixed` with commit `3c36f34`; WSL spot x2 bit-identical.
- **xiom.metrics adoption pass (55th):** suite **171/171 x2** +
  **SBOM/unsafe gate** + **34 probes x2** + bench smoke on **Windows AND
  WSL**, ALL GATES GREEN; new `probe_package_metrics` (12 checks) and the
  re-gated `probe_metrics` (24 checks) green on both platforms;
  `docs/repro/xv-counter-type-shadow` reproduces XVC-C-14 on both
  (clang exit 1, `xiominput.ll:850`); the json-depth boundary unit
  (128-deep Ok; 129/60000 Err) green on Windows + WSL (bus item -7
  verified + closed; stdlib checkout `a16daff`).
- **xiom.rate adoption pass (56th):** suite **171/171 x2** +
  **SBOM/unsafe gate** + **35 probes x2** + bench smoke on **Windows AND
  WSL**, ALL GATES GREEN; new `probe_package_rate` (14 checks) green on
  both platforms; `probe_service_auth`/`probe_metrics` re-verified with
  the package-backed limiter (orbitdb closed the XV-ORBITDB-01 bus item
  this pass).
- **v0.64.3 re-pin pass (57th):** Windows AND WSL isolated batteries ALL
  GATES GREEN (suite **171/171 x2** + sbom + **35 probes x2** + bench
  smoke each); repro re-test on v0.64.3: 12 bundles, 17/18 single-file
  probes green, C-13/C-14 red as filed; release-check verdicts filed on
  `release-checks/compiler-compiler-v0.64.3`; the first two WSL battery
  reds were the shared-home wipe (environmental), root-caused and fixed
  with lane-local isolation.
- **xiom.http helper pass (58th):** Windows AND WSL batteries ALL GATES
  GREEN (suite **171/171 x2** + sbom + **36 probes x2** + bench smoke
  each); new `probe_package_http` (5 checks) green both platforms;
  `probe_http_service` 41/41 incl. the raw 507 status-line pin;
  `probe_service_limits` 27/27 with the package-backed phrases.
- **xiom.vectors wiring pass (59th):** Windows AND WSL batteries ALL
  GATES GREEN (suite **171/171 x2** + sbom + **37 probes x2** + bench
  smoke each); new `probe_package_vectors` (13 checks) green both
  platforms; extraction pins re-hashed 6/6 MATCH; the package's own
  codec probe green (bit-exact).
- **xiom.vectors swap pass (60th):** Windows AND WSL batteries ALL GATES
  GREEN on the swapped tree (suite **171/171 x2** + sbom + **37 probes
  x2** + bench smoke each); zero stale module references; three
  representative probes compiled green on first try; scratch resolver
  experiments (positive/negative controls) confirmed the silent-import
  behavior filed as `REL-20261010-2124-xvector`.
- **P-a pass (63rd):** Windows battery ALL GATES GREEN (suite **171/171
  x2** + sbom (39 modules, unsafe=0) + **37 probes x2** + bench smoke);
  WSL spot bit-identical (recall x2, codec x2, fuzz x2, engine_hnsw x2,
  soak, segment, index_admin) + WSL bench smoke quick; P-a diag identical
  on both platforms (build 60,852 ops; hard corpus 285 vs 275; n=800
  visited 346; per-ef table in `docs/hnsw-design.md`, baseline refreshed
  in `docs/BENCHMARKS.md`); C-10 repro re-run green on codec v3.
- **Q-a1 pass (66th):** Windows battery ALL GATES GREEN (suite
  **177/177 x2** + sbom (40 modules, unsafe=0) + **38 probes x2** + bench
  smoke); WSL spot (suite 177/177; `probe_quantization` x2 with diag
  bit-identical to Windows; C-15 repro identical on both platforms);
  C-15 filed on the bus (`REL-20261011-1134-xvector`, pushed).
- **Q-a2a pass (67th):** Windows battery ALL GATES GREEN (suite
  **177/177 x2** + sbom (40 modules, unsafe=0) + **38 probes x2** + bench
  smoke); WSL spot (quantization x2 diag bit-identical, segment_file,
  collections, index_admin) green; segment v1 path byte-identical
  (14-point tear sweep diags unchanged).
- **Q-serve pass (69th):** Windows battery ALL GATES GREEN (suite
  **177/177 x2** + sbom (41 modules, unsafe=0) + **39 probes x2** + bench
  smoke); WSL spot (probe_http_server x2 + probe_http_service) green;
  curl end-to-end user test green incl. clean quit.
- **Benchmark pass (70th):** Windows battery ALL GATES GREEN (suite
  **177/177 x2** + sbom (41 modules, unsafe=0) + **39 probes x2** + bench
  smoke); WSL spot (server 15/15 x2, service 42, limits 27) green;
  **adapter smoke live-green** against `xvectord` (default caps):
  recall@10 1.000 at ef>=64 / 0.940 at ef=8, duplicate 409; all adapter
  Python syntax-checked.
- **Fast-scanner pass (72nd):** Windows battery ALL GATES GREEN (suite
  **177/177 x2** + sbom (**42 modules**, unsafe=0) + **40 probes x2** +
  bench smoke); WSL spot (json_fast 228-case byte-equality + big body
  1.7s, http_server 15/15, http_service 42/42) green; quick_bench 5k
  x dim-25 through `xvectord`: upsert 120s (was 661s), recall 0.779 /
  0.960 / 1.000 at ef 8/32/128, 53-78 QPS.
- **Re-verification pass (73rd):** Windows batteries ALL GATES GREEN on
  both the wave-110 pin and the stable wave-111 WIP pin (suite
  **177/177 x2** + sbom (42 modules, unsafe=0) + **40 probes x2** + bench
  smoke; WIP hashes unchanged before/after; the first run straddled the
  WIP edits and was superseded by the clean re-run); WSL spot (suite
  **177/177 x2** + `probe_package_http` 6/6 x2 + `probe_http_service`
  42/42 x2) green; both repro probes exit 0 on the WIP; quick_bench 5k
  x dim-25: upsert **57.4 s** (87 pts/s), recall 0.779/0.960/1.000,
  58-82 QPS; `probe_package_http` now 6 checks.
- **VectorDBBench adapter (74th):** py_compile 6/6 across the adapter
  modules; live smokes against `xvectord` (raised caps): `smoke_db.py`
  11/11 (exit 0), `smoke.py` 7/7 (exit 0), `quick_bench.py` small-run
  (N=600) exit 0 after the oracle refactor.
- All **37 probes x2** green on Windows: `probe_hello`, `probe_bind_semantics`,
  `probe_engine_import`, `probe_vector_store`, `probe_filtered_search`,
  `probe_payload_recovery`, `probe_floatval_roundtrip`, `probe_search_request`,
  `probe_payload_index`, `probe_filter_plan`, `probe_hnsw_recall`,
  `probe_engine_hnsw`, `probe_hnsw_codec`, `probe_result_shapes`,
  `probe_fuzz_codecs`, `probe_soak_mixed`, `probe_kill_recovery`,
  `probe_wal_file`, `probe_manifest_file`, `probe_collections`,
  `probe_segment_file`, `probe_range_search`, `probe_pagination`,
  `probe_delete_filter`, `probe_index_admin`, `probe_reference_oracle`,
  `probe_http_service`, `probe_service_limits`, `probe_service_auth`,
  `probe_http_fuzz`, `probe_metrics`, `probe_package_wal`,
  `probe_package_metrics`, `probe_package_rate`, `probe_package_http`,
  `probe_package_vectors`, `probe_batch_ops`
  (run via `scripts\run-probe.ps1`); plus the SBOM + unsafe gate
  (`scripts/sbom.ps1`, `scripts\sbom.sh`).
- Bench smoke: `scripts\bench.ps1 -Mode quick` / `bash scripts/bench.sh
  quick` green (Windows + WSL), wired into both CI batteries; baseline
  numbers in `docs/BENCHMARKS.md` (M-G).
- Per-ef tradeoff (n=200, 10 queries each): ef=8 -> 97/100 recall @ 63
  visited; ef=16 -> 100/100 @ 84; ef=32 -> 100/100 @ 126; ef=64 -> 100/100
  @ 171; ef=128 -> 100/100 @ 196; build work 62,129 distance ops.
- Release battery: `scripts/ci.ps1` and `scripts/ci.sh` -> `ci: ALL GATES
  GREEN` this pass on Windows and WSL (suite x2 + 18 probes x2 each); the
  file-WAL slice `c84ccbc` was verified through both batteries.
- Handoff re-verification (file-WAL wrap, v0.64.1-era): `scripts/ci.ps1` ->
  `ci: ALL GATES GREEN` (suite 168/168 x2 + 18 probes x2); WSL spot
  `bash scripts/run-probe.sh tests/probes/probe_wal_file.xi 2` -> 2/2
  green with bit-identical diagnostics; both stdlib-defect control probes
  (`docs/repro/xv-stdlib-file-read-defects/`) green in their own units.
- WSL spot: `probe_soak_mixed` x2 + `probe_fuzz_codecs` x1 + the pad-loop
  repro probe + `probe_result_shapes` x2 + `probe_bind_semantics` x2 +
  `probe_engine_hnsw` x2 + `probe_hnsw_recall` x2 + `probe_filter_plan` x2 +
  `probe_filtered_search` x1 + `probe_vector_store` green
  (`bash scripts/run-probe.sh`).
- Stresses: `probe_search_request` 8/8, `probe_payload_index` 6/6,
  `probe_filter_plan` 6/6, `probe_hnsw_recall` 6/6, `probe_engine_hnsw` 6/6,
  `probe_hnsw_codec` 6/6, `probe_fuzz_codecs` 6/6, `probe_result_shapes` 8/8,
  `probe_bind_semantics` 8/8, `probe_soak_mixed` 4/4 fresh builds (trailing
  field reads are asserted in the suite again since the v0.64.2 C-08 fix).
- WSL matrix `docs/repro/xv-f32-int-miscompile/linux_matrix.sh 3` -> 9/9
  exact (v0.64.1 fixed the per-build f32 lowering).

**Compiler findings (all reported; see `docs/COMPILER-FINDINGS-XVECTOR.md`):**

- **v0.64.5 archive re-verification (2026-10-15, 81st pass):** C-13
  (m320 `b672a19f`) and C-14 (m278 `484d9f21` + m298 `c18e550e`)
  **VERIFIED FIXED on both platforms** (C-13: `first_byte(A)=65`, warning
  gone; C-14: bundle build+run exit 0, `shim counter=1 tally hits=1`);
  bus items `-1550` + `-1709` verified + closed; check rows updated on
  `release-checks/compiler-compiler-v0.64.4`. **Thread gate GREEN**
  (acceptance closed in everything but bookkeeping; items stay `fixed`
  pending the pass-green). **NEW: XVC-C-16** -- v0.64.5 linux-x64
  miscompiles the HTTP service `/search` path (WSL battery red on 6
  gates; Windows green; A/B + bundled-stdlib controls in the repro;
  `REL-20261015-2142-xvector`; **re-pin HELD**).
- **v0.64.4 archive re-verification (2026-10-12, 77th pass):** C-15
  (m271 `f69b542e`) and the phantom-import gap (m266/m267 `0b1c6374`)
  **VERIFIED FIXED** from their witnesses (C-15 repro exit 0 on both
  platforms + the workaround dropped; controls give exactly one clear
  unresolved-import error, exit 1, no silent build). Verdicts + closures
  filed on the bus (`-1134` and `-2124` closed; `REL-20261012-1402-xvector`
  for the thread gate). C-13 (Win 167 / WSL 63) and C-14 (ll:850) re-tested
  unchanged; thread gate still red (runtime-side fix pending). Verdicts on
  `release-checks/compiler-compiler-v0.64.3`.
- **v0.64.2 re-test (2026-10-09): all relayed fixes verified, workarounds
  reverted.** C-03 (suite W004 count 0) and C-06 (pinned FloatVal probe)
  stay green; **C-07 FIXED** -- `Str::from_utf8(&Vec[UInt8])` compiles and
  returns correctly, the payload codec + suite mirror reverted to the `&`
  spelling; **C-08 FIXED** -- trailing-scalar repro exit 0, all 14 variants
  green, suite hydration flags asserted again (168 -> 169 checks).
- Extra re-tests beyond the relayed set: **C-10 FIXED** (inline pad shape
  no longer segfaults; `pad_adj_slots` + strict bounds kept as hygiene);
  **C-11/C-12 re-tested green in a copy of the original failing unit**
  (byte parser + `file_size` guard kept as defense in depth); **C-09 repro
  green on WSL + Windows** (local-assign pattern kept; weaker re-test --
  the inline pattern was green before too).
- Retained workarounds (deliberate choices, not blockers): `SearchHits`
  wrapper (C-04, zero-cost public API), suite direct dispatch (C-01),
  predicate-negative style (C-02).
- Relay for the compiler lane: `docs/RELAY-COMPILER.md` (Addenda 3-12;
  8 = v0.64.2 re-test; 9 = XVC-C-13; 10 = XVC-C-14; 11 = XVC-C-15;
  12 = v0.64.4 archive re-verification). Incoming relay
  `docs/COMPILER-RELAY-2026-10-09-v0.64.2.md` (m220-m239) -- actioned:
  suite + pinned probes re-run on the archive, no residual reds.
- **XVC-C-14 (VERIFIED FIXED v0.64.5 / m278+m298; closed 2026-10-15):** two
  same-named struct types across modules shadowed each other's field layout
  (short-name resolution at struct emission; clang store reject when the
  layouts differ, silent wrong fields when they match). Found during the
  xiom.metrics adoption (shim `Counter` + package `Counter`); repro
  `docs/repro/xv-counter-type-shadow/` (4 modules + manifest); workaround
  (single `Counter` type; shim Counter retired) stays as hygiene; relay
  Addendum 10; bus item `REL-20261010-1709-xvector`; v0.64.5 bundle
  build+run exit 0 on Windows + WSL.

---

## 1. NEXT TASKS (priority order)

**HANDOFF STATE (end of 2026-10-16 session, 83rd pass; HEAD `bc53af7` + this wrap):**

> **2026-10-18: v0.64.7 re-pin COMPLETE + MOTE PUBLISHED.** The owner
> greenlit; the packages lane published **`xiom.vectors` 0.2.0** (the mote
> tier: engine + in-process HTTP; lattice modules excluded) in
> **eco-v0.1.198** at 2026-10-18T15:55:48Z, sha256
> `130427a5bc4e8b251a2e53eb995e84b06ba9255d7a29892108b0a12d78b6d166`,
> run 39142312352 green, registry live-verified, carve from pin `c858ec1`
> (239 files; suite 177/177 x2 on v0.64.7). **The carve exposed real
> library-mode gaps our CI never sees** (see section 1 item 0): internal
> `use xiom.vectors;`, a dangling `use xiom.core.ids;` in
> `storage/id_map.xi`, a missing `core.shim` import for
> `is_valid_dimension` in a `collection/schema.xi` contract, and the
> `xiom.http.status` dep -- all fixed in the carve (package commit
> `1807615e`), with a **recommendation to add a library type-check gate to
> our CI**. Next: that gate + the portable fixes, then G-2b accept-loop
> threads; the rc.1 release-notes refresh is still owed.
>
> **2026-10-18 (library-gate slice, this pass): ITEM 0 COMPLETE.** Ported
> the carve's four fixes -- `src/primitives.xi` (`module
> xiom.vector.primitives`, vendored 0.1.0 surface) with all 15 internal
> imports switched off the public module; the dead `use xiom.core.ids;`
> removed from `storage/id_map.xi`; `core.shim` imported in
> `collection/schema.xi` for the contract; the `xiom.http` dependency
> confirmed. Added `scripts/libcheck.ps1` + `libcheck.sh`, wired into
> `ci.ps1`/`ci.sh`: per-module `--check` against a carve manifest
> (`xiom.vectors` removed) PLUS an explicit import guard. Negative-tested
> both ways -- the guard is authoritative because a module that also imports
> the vendored primitives type-checked green while still importing the
> public module (the installed package can satisfy the undeclared `use`).
> Evidence: **Windows battery ALL GATES GREEN** (suite 177/177 x2 + libcheck
> 47/47 + sbom 47 modules unsafe=0 + 53 probes x2 + bench smoke + kill
> matrix); **WSL spot green** (libcheck 47/47 + suite 177/177 x2 +
> `probe_vector_store` x2 + `probe_mote_embedded` x2) on v0.64.7, stdlib
> `15495aa`, packages `0574c0d6`. Latest registry packages installed in BOTH
> lane homes (`xiom.vectors` 0.2.0, `xiom.pulse` 0.3.0; manifest pins
> unchanged for this slice). **G-2b attempt (same day, doorbell pass):
> BLOCKED on XVC-C-20** -- the threaded accept loop was implemented and the
> server started, but a module-level `VectorEngine` global loses mutations
> through `&mut` (create Ok, count 0, second create Ok; upsert contract
> violation). The slice was reverted; repro
> `docs/repro/xv-global-engine-mutation/`, bus `REL-20261018-1815-xvector`
> (high). Next: Q-a2b / M-P; the release-notes refresh is still owed.
>
> **2026-10-18 19:45Z: PAUSE for the night.** Tree clean at `4c8058a` +
> this note (10 commits ahead of origin; repo stays private). G-2b remains
> BLOCKED on XVC-C-20 (bus `REL-20261018-1815-xvector`; repro
> `docs/repro/xv-global-engine-mutation/`; the threaded slice was reverted).
> Doorbell CANCELLED for the pause. Next session: section 18 -- Q-a2b / M-P,
> then the release-notes refresh; watch the bus for a compiler archive
> answering XVC-C-19/C-20 before re-opening G-2b.
>
> **2026-10-19 (resume): pulse 0.3.0 ADOPTED** -- `xiom.toml` pin 0.2.1 ->
> 0.3.0; `probe_package_pulse` now gates the exact 0.3.0 identity and the
> stateful HookCtx seam (pre->after mutation, limiter 429 short-circuit,
> idempotent clear) -- 11/11 checks x2 on Windows + WSL. **XVC-C-20 FIXED on
> compiler main `56d362a31`** (bus history; no v0.64.7 re-cut): the repro is
> still red on the pinned archive, so G-2b stays blocked until the next
> release; then re-pin, re-run the repro, and re-open the threaded slice.
> Next: Q-a2b / M-P; the release-notes refresh remains owed.
>
> **2026-10-19 12:50Z: pulse 0.3.1 ADOPTED** -- released the same day
> (fallback seam + HEAD trim; sha256 `38465713`; test-back requested).
> Manifest 0.3.0 -> 0.3.1; `probe_package_pulse` now gates the exact 0.3.1
> identity, the unmatched-route fallback (install / duplicate code /
> unmatched-route site response / clear -> package 404) and the HEAD wire
> trim (loopback: GET Content-Length 11 with zero body bytes). Probe 16/16
> x2 Windows + WSL; suite 177/177 x2 + libcheck 47/47 both platforms.
>
> **2026-10-19 15:00Z (doorbell): rc.1 RELEASE NOTES REFRESHED** -- the
> 2026-10-09 draft is replaced with the current candidate: durability
> D5-D7, SQ8 Q-a1/Q-a2a (Q-a2b queued), filters/planner, lattice L-1..L-5,
> G-1, the package tiers (mote 0.2.0 + pulse 0.3.1), the library gate, the
> 177/177 x2 + 53 probes x2 + 47-module SBOM evidence, and the honest
> G-2b/C-19/C-20 limits. SBOM snapshot refreshed to 47 modules; the
> findings summary and OWNER-HANDOFF were truthed up. v0.64.8 cut is GO
> upstream (stdlib gate in progress; no archive yet). Machine load was 100%
> from other lanes: docs-only pass, no heavy gates.
>
> **2026-10-19 18:00Z (doorbell): v0.64.8 RE-PIN + XVC-C-20 VERIFIED + G-2b
> LANDED.** v0.64.8 installed lane-local both platforms (win `c31d9c46`,
> linux `a8c003c0`; v0.64.7 kept as rollback). The C-20 repro is GREEN on
> both: `count after create = 1`, second create `Err` (exit 0). The threaded
> accept loop was re-applied (`XVECTORD_THREADS`: accept in one thread,
> bounded in-flight workers, one coarse engine mutex, graceful `JoinHandle`
> joins) and a new 54th probe (`probe_concurrency`: 4 clients x 8
> deterministic upserts/searches, exact 32 points, worker-served quit,
> shutdown join) is GREEN x2 Windows + WSL; the existing service family +
> `probe_http_fuzz` are GREEN x2. Quick bench (v0.64.8): flat 62us/op
> (~16.1k qps at the quick group size), HNSW ef=32 recall 1.000 / 281us/op
> (~3.6k qps), recovery 1.0 s. **XVC-C-19 is ALSO VERIFIED FIXED on
> v0.64.8** -- the module-level-initializer repro builds+runs (`main
> started` / `vec global ok`) on both platforms; no XVECTOR compiler
> findings remain open. Windows full battery ALL GATES GREEN; WSL suite +
> UI/concurrency/service probes green; the full WSL 55-probe sweep is queued.
> Release notes were refreshed earlier today and are updated for G-2b.
>
> **2026-10-19 (same pass): STATION WEB UI MVP LANDED.** `xvectord` serves
> `/ui` (single-file static `ui/index.html`; `XVECTORD_UI_DIR` overrides):
> collection picker, seeded random 2D scatter of an active-store sample,
> hover/click inspector, `/search` playground with hit highlighting, stats.
> New `GET /collections/{n}/sample?limit=&seed=` (bounded 1..2000,
> deterministic stride, active-store scope). `probe_ui` is the 55th probe
> (GET/HEAD /ui, unknown-path 404, sample bounds/exactness, quit/join);
> headless-Edge screenshot verified the rendered page with 60 demo points.
> Windows full 55-probe battery is ALL GATES GREEN; the WSL targeted gates
> are green and the full WSL 55-probe sweep is queued. Canvas 2D now;
> three.js/WebGL + editor later (`docs/UI.md`).
>
> **2026-10-19 (work window): Q-a2b LANDED.** Sealed Flat segments with SQ
> codes now read through `sq8_scan_rescore` (oversample 4) in
> `union_sealed_knn`; the filtered path stays exact. New `probe_sq_sealed`
> (56th) proves the sealed union is bit-identical to the pre-seal exact
> top-10 across 10 queries on a real rolled segment (SQ armed by the roll).
> Affected probes (quantization / multisegment / snapshot / collection_move
> / move_under_load) + suite 177/177 x2 + a clean libcheck are green; the
> clean 56-probe Windows battery is **ALL GATES GREEN** (suite 177/177 x2 +
> libcheck 47/47 + SBOM 47/0 + 56 probes x2 + bench smoke + kill matrix).
> WSL could not complete a long sweep tonight: the VM restarted repeatedly
> (0-min uptime) and killed the frozen 55-probe run mid-probe; WSL targeted
> re-runs are queued for the next quiet window.
>
> **2026-10-20: P3 KERNEL SEAM LANDED.** `src/index/kernels.xi` routes
> distance/dot/magnitude through a runtime scalar (default) / unrolled
> same-order backend behind the `xiom.vectors` contract. `probe_kernels`
> (57th) proves bit-identical dot/magnitude/distance across all metrics,
> install/restore, and records the microbench. The hot flat/HNSW/range/
> pagination/SQ loops branch once per scan; the scalar path is back at the
> pre-seam baseline (flat 62us/op, HNSW ef32 281us/op when unloaded; range
> r0.6 437us vs 718us). No Float32 accelerated binding exists yet
> (OpenBLAS 0.1.1 is Float64/native); it plugs in as another kind.
> Windows full 57-probe battery **ALL GATES GREEN** (suite 177/177 x2 +
> libcheck 48/48 + SBOM 48/0 + 57 probes x2 + bench smoke + kill matrix);
> WSL targeted `probe_kernels` + suite green (long WSL sweeps remain
> environment-interrupted).
>
> **2026-10-20 (user directive): RESOURCE GUARD.** Every app/probe run is
> hard-capped at 8 GB (Windows Job Object PROCESS+JOB limit + kill-on-close;
> WSL `ulimit -v`); use `scripts/run-capped.ps1`/`.sh` for manual apps.
> Compiler builds use a kill-on-close-only job (v0.64.8 hangs under a
> memory-limit job; XVC-C-21) + the watchdog. The shared stdlib checkout
> `ee1a95c` break is **resolved at `750384f`** (bus item acked; the shared
> tree builds/checks/suite pass again); `XVECTOR_STDLIB_BUNDLED=1` remains a
> fallback. Full 57-probe battery under the guard: suite 177/177 x2 +
> libcheck 48/48 + SBOM 48/0 + 57 probes x2 + bench smoke green; the newly
> capped kill matrix hit a missing `lib.ps1` import in the edited script
> (fixed) and now runs 4/4 PASS. The next full battery will print the
> aggregate line.
>
> **2026-10-21: P4 IVF-PQ prototype BLOCKED on XVC-C-22.** The deterministic
> PQ trainer + IVF-PQ prototype was implemented and exposed a compiler
> memory bug: a second `pq_train` call crashes `0xC0000005`; one
> `ivf_pq_build` returns a corrupted nested codebook (checksum 370608086 ->
> 534399819, mean recon L2 0.84 -> 4.48e28) and the exact rescore <1.0.
> Minimal Option/Vec and nested-struct tests pass. Repro
> `docs/repro/xv-pq-second-call/`; P4 code reverted; bus
> `REL-20261021-1103-xvector`; P4 checklist BLOCKED. Next: L-6 phase B /
> G-3-G-4; P4 reopens on a compiler fix.
>
> **2026-10-21 11:20Z: HANDOFF (fresh context).** State, findings,
> wishlists, and the ordered next work are fully recorded; **the
> fresh-session prompt is section 20**. Tree clean at the handoff commit;
> resource guard active (8 GB apps/probes, compilers kill-on-close only,
> WSL `ulimit -v`); P4 blocked on XVC-C-22; next L-6 / G-3-G-4; WSL full
> 57-probe sweep queued.
>
> **2026-10-20 00:45Z: PAUSE for the night.** Work window complete; tree
> clean at `581d765` (18 commits ahead; repo private). Q-a2b landed at
> `cb66ee5`; Windows full 56-probe battery ALL GATES GREEN (suite 177/177
> x2 + libcheck 47/47 + SBOM 47/0 + 56 probes x2 + bench smoke + kill
> matrix). WSL long sweeps were environment-interrupted (VM 0-min uptime
> restarts); WSL suite + UI/concurrency/service probes are green, full
> sweep queued. Doorbell cancelled; lane rests until tomorrow. Next
> session: section 19 -- M-P, then L-6 phase B; optional station-UI
> editor/three.js.
- Compiler lane: **v0.64.6 RE-PIN COMPLETE (both platforms, 2026-10-17).**
  Windows (sha256 `a32bf7fa`) + WSL (linux `82a7417b`, installed into
  `~/.xvector-toolchain`; old kept at `~/.xvector-toolchain-v0645`).
  WSL must be targeted as `wsl -d Ubuntu` -- the default distro became
  `docker-desktop`, which has no bash; that was the "WSL broken" red
  herring. **Full batteries ALL GATES GREEN BOTH platforms** (suite
  177/177 x2 + 51 probes x2 + sbom 46 + bench + kill matrix) on stdlib
  tree `7073a64` + packages checkout `53cba79b`; **C-16 acceptance repro
  exit 0 (WSL), C-17 7/7 (both), C-18 exit 0 (both); `-1937` custom-home
  retest clean; all three findings + thread items `-1627`/`-1402` closed
  on the bus; `scripts/sbom.ps1` now records the lane-local compiler.**
  Compiler-side queued follow-up: a second layout-sensitive create-path
  corruption that survives the SFB flag (own bisect, v0.64.7 plan).
  **XVC-C-17** (imported-type global pointer-field drop; bus
  `REL-20261015-2216-xvector`) has the fix INTEGRATED upstream (m337); the
  lane re-verify awaits the next candidate build. **XVC-C-18 NEW** (JSON
  object-key reads through a `match` binding return garbage; found on
  Windows during L-3; repro `docs/repro/xv-object-key-iter/`; copy-out
  workaround shipped; bus `REL-20261016-1541-xvector`, high). Thread items
  `-1627`/`-1402` accept-green but `fixed` (closure deferred to a
  full-green archive pass). **v0.64.5 re-pin HELD on C-16.**
- Slices: G-1 + **L-0..L-5 ALL LANDED** (`a94cb9b`, `0ba7f62`, this
  session's three slices); **full Windows battery ALL GATES GREEN** (suite
  177/177 x2 + sbom 46 modules unsafe=0 + **53 probes x2** + bench smoke +
  kill matrix); `probe_router_2shards` 72 + `probe_move_under_load` 41 +
  `probe_replica` 24 + `probe_reopen_write` 6 checks green x2; a durable
  reopen-then-write loss was found + fixed in `engine_enable_durable`
  (segment file = durable frontier; `probe_wal_segment` expectation
  updated). WSL legs HELD (owner resource guidance -- other lanes hold the
  machine -- plus C-16 would red the service/search legs until v0.64.6).
  Slice state: `docs/checklists/lattice-v1.md`.
- **WSL queue: CLEARED (2026-10-17).** `-1937` retested clean (installs to
  the custom home, no `C:Userslefte` tree; item already closed); the L-3
  WSL spot + the full WSL battery are green on v0.64.6; use
  `wsl -d Ubuntu` for every WSL command (the default distro is
  docker-desktop).
- Product tier: `xvector-mote` / `xvector-lattice` named + planned; README
  carries the tier story (codenames, usage, features, served quickstart).
  Mote publication -> packages lane via relay when package-ready; lattice
  releases -> ops GitHub Actions (owner directive).
- Stdlib: waves 149+ (POSIX break verified+closed; f32_bits landed;
  mmap/signals/poll real). Packages: previous pins.
- Doorbell: re-armed in THIS session (3h cron `wku_14536b9e3001JzXTooSehg4klu`)
  -- C-16/C-17/C-18 + archive watch + the WSL-pending queue; the prior
  session's `wku_1418fbc4...` is not visible from this session (do not
  rely on it).

**ORDERED NEXT WORK:**
0. ~~Library type-check gate + the carve's portable fixes~~ **DONE
   2026-10-18** (this pass; evidence in the header note above):
   `src/primitives.xi` vendored + 15 internal imports switched; dead
   `xiom.core.ids` import removed; `core.shim` import added in
   `collection/schema.xi`; `xiom.http` dep confirmed;
   `scripts/libcheck.ps1`/`libcheck.sh` gate every `src/` module in package
   mode and enforce the internal-import rule (wired into both CIs). Reference:
   package carve commit `6933b2b3`, bus `REL-20261018-1520-xvector`.
1. ~~WSL pending-pass~~ **DONE 2026-10-17** (re-pin complete: both
   batteries green on the latest trees; all findings + thread items
   closed on the bus; pins recorded above).
2. In-lane: **G-1 is COMPLETE (2026-10-18)** -- natural module-level globals
   + the cross-thread mailbox leg are green x2 both platforms; the
   Int-handle workaround is retired. **G-2b accept-loop threads: COMPLETE
   2026-10-19 on v0.64.8.** XVC-C-20 was verified fixed on the archive
   (`count after create = 1`, second create Err, both platforms); the
   threaded accept loop is re-applied behind `XVECTORD_THREADS` (accept in
   one thread, bounded in-flight workers, one coarse engine mutex, graceful
   `JoinHandle` joins) and the new `probe_concurrency` (54th) is green x2
   both platforms; the service family + `probe_http_fuzz` are unchanged and
   green x2. **Q-a2b DONE 2026-10-19** (sealed Flat SQ coarse + exact
   rescore; `probe_sq_sealed` 56th; bit-identical gate). **P3 kernel seam
   DONE 2026-10-20** (`src/index/kernels.xi`; `probe_kernels` 57th;
   bit-identical, scalar baseline preserved; no Float32 accelerated binding
   yet). Next **M-P remainder (P4 IVF/PQ, P5 mmap/disk)**; L-6 after.
   **Station web UI MVP LANDED 2026-10-19** (`/ui` +
   `/collections/{n}/sample`, 55th probe, Canvas 2D, screenshot-verified;
   editor/three.js upgrade optional). Note: **XVC-C-19 and XVC-C-20 are
   VERIFIED FIXED on v0.64.8**; no XVECTOR compiler findings remain open
   (the repros stay as regression gates). **Pulse 0.3.1 ADOPTED 2026-10-19**
   (manifest 0.3.1; exact identity + HookCtx + fallback seam + HEAD trim;
   16/16 x2 both platforms).
3. **Latest-tree protocol (owner directive 2026-10-17): always run against
   the newest stdlib checkout + newest registry packages** (pull
   `E:\xiom-lang\stdlib` + `E:\xiom-packages\packages`; `xiom pkg info`
   each consumed package and install the latest into BOTH lane homes
   before the batteries; record the hashes/versions in section 0 at every
   wrap).

**Programme:** `docs/PRODUCTION-PLAN.md` (v1.0 flagship plan) +
`docs/requirements/production-v1.md` + `docs/checklists/production-v1.md`.
Work proceeds autonomously slice-by-slice under the lane's goal loop, one
verified slice at a time (suite x2 + all probes x2, Windows + WSL spot,
signed commits, docs updated).

**ARCHIVE PASS EXECUTED (2026-10-15): `v0.64.5` INSTALLED lane-local both
platforms (tag `84f761c5`, run 38792051847, assets sha256-verified:
win `bd71e2d3` / linux `246e5e82`). RE-VERIFICATION SET ALL GREEN:**
- **THREAD GATE GREEN (exit 0; 3 workers exact sums; OS thread ids; marks
  witness M3 `join ok 42`) -- THE G PHASE FLIPS.**
- **XVC-C-14 FIXED** (counter-type-shadow bundle build+run exit 0; ll:850
  gone) -- bus item verified + closed.
- **XVC-C-13 FIXED** (`first_byte(A)=65`, warning gone; was 167/63) --
  bus item verified + closed.
- XVC-C-15 regression clean (exit 0); phantom controls one T001 each
  (exit 1, no binary); repro sweep 19/19 OK.
**BATTERIES: Windows ALL GATES GREEN** (suite 177/177 x2 + sbom 44 modules
unsafe=0 + 44 probes x2 + bench smoke + kill matrix). **WSL RED on 6
service/search gates -- new finding XVC-C-16** (v0.64.5 linux-x64
miscompiles the HTTP service `/search` path; A/B: v0.64.4 linux + v0.64.5
windows green; bundled-stdlib repro => compiler not stdlib; repro
`docs/repro/xv-http-service-linux/`; bus `REL-20261015-2142-xvector`,
pushed `532b20d`). **v0.64.5 re-pin is HELD**; the thread items stay
`fixed` (acceptance green, closure deferred per the archive-pass
protocol). **NEXT: C-16 is ACKED by the compiler (queued for the v0.64.6
fixer wave; C-17 still open) -- watch for the fix, then re-run the WSL
battery + close -1627/-1402 + finish the re-pin** (then Q-a2b / M-P per
the standing queue below).
**L-1 MOTE POLISH LANDED (2026-10-16):** `docs/MOTE-QUICKSTART.md` +
`tests/probes/probe_mote_embedded.xi` (46th probe, both batteries); the
probe caught a **cid-collision regression** (creating a collection after
a reopen reused a recovered cid; the next recovery's last-wins manifest
merge silently dropped the earlier collection) -- fixed in
`engine_recover_registry` (`eng.next_collection = max(cid)+1`); suite
177/177 x2 + probe x2 + Windows battery green. **WSL legs were held on
the stdlib wave-146 POSIX build break and are GREEN since wave 149
(`a451349`; `REL-20261016-1143-xvector` verified + closed): probe x2 +
suite 177/177 x2 in WSL.** Reference study 04
(`docs/REFERENCE-STUDY-04-LATTICE.md`) landed + folded into
`docs/checklists/lattice-v1.md`.
**L-2 COLLECTION MOVE LANDED (2026-10-16):** `export_collection` +
`attach_segment` (one self-contained segment artifact is the portable
move unit; the source keeps serving via its sealed entry) + the segment
integrity footer (`z <count> <crc32>`; attach refuses truncated/corrupt
copies) + `probe_collection_move` (47th probe, both batteries) +
`docs/OPERATIONS.md` section 9; probe x2 + suite 177/177 x2 both
platforms; full Windows battery re-run. Next lattice step: **L-3 router
v1** (stateless mapping + reverse proxy) -- or L-5 drain CLI once the
router lands; the C-16/C-17 compiler watch continues (C-16 acked,
queued for the v0.64.6 fixer wave).
**G-1 SLICE LANDED (2026-10-16):** `tests/probes/probe_thread_sync.xi`
(45th probe, both batteries) -- spawn/join acceptance + 4-thread
mutex-guarded counter (exact 2000) + 4-thread atomic counter (exact 2000)
+ channel same-thread contract; Windows 5/5 stress + WSL green; suite
177/177 x2 both platforms. The channel CROSS-THREAD leg is blocked on the
new **XVC-C-17** (`REL-20261015-2216-xvector`: imported-type global stores
drop pointer fields; Int-handle workaround shipped in the probe; repro
`docs/repro/xv-global-ptr-field/`). Next G step: G-2 flag-gated accept
loop (after C-16/C-17 or with the workaround where possible).
**80th-pass wrap (2026-10-13 night): D7 MULTI-SEGMENT READ PATH DONE --
M-D is complete except power-loss fault injection.**
- Roll (`engine_roll_segment`): the active collection moves into an
  immutable segment (register + cache + clear; fsync-before-ack in durable
  mode; `SegmentSeal` replays attach+clear; checkpoint attach markers).
- Union queries over active + sealed for every variant (tombstones shadow
  deletes-after-seal; the active copy wins duplicates; the `k + tombstones`
  per-source budget keeps Flat results bit-exact); delete/delete_by_filter
  cover sealed-only points; compaction merges everything bit-exactly and
  survives restart; recovery loads every registered source
  (`sealed_missing` accounted); opt-in policy
  (`XVECTORD_SEAL_EVERY`/`XVECTORD_SEAL_DIR`, works in-memory too).
- **A live-only bypass was found and fixed during the slice** (`2552824`):
  the HTTP request search tail searched the active store directly; now it
  routes through the union, with union hydration for sealed payloads. A
  second real bug was caught by the wrap battery: **replay symmetry** --
  a replayed Insert did not clear a tombstone shadow, so a delete-miss
  then upsert left the id live AND tombstoned after recovery and the next
  checkpoint ate it (`71af343`, found by `probe_soak_mixed`'s chained
  recovery; rec 421 -> rec2 417, now exact).
- Gates: `probe_multisegment` **27/27** (diag: 50 warm union queries over
  60 pts = 6 ms); live policy server verified end-to-end (sealed serving,
  /stats counters, restart); stock smoke 7/7 with the policy off;
  **both wrap batteries ALL GATES GREEN** -- Windows (suite 177/177 x2 +
  sbom 44 modules unsafe=0 + 44 probes x2 + bench smoke + kill matrix)
  and WSL (same shape).
NEXT: **the v0.64.5 archive re-verification the moment the tag lands**
(thread gate first -- stdlib wave-131 hoist + m282; then C-14 after m278;
C-13; C-15/phantom regression; full batteries both platforms), then
**Q-a2b** (SQ two-tier rescore on sealed scans -- unblocked by D7) and
M-P (P3 seam / P4 PQ). Standing watches: the compiler v0.64.5 tag;
stdlib mmap (queued); the `xiom.ann` swap + rc.1 public-release
greenlights. **Reference-port queue (owner guidance 2026-10-12):** FAISS
PQ -> P4 IVF-PQ prototype; FAISS visited-set pruning -> P-b (M-P);
DiskANN layout/merge -> P5 (D7 now owns the multi-segment mechanics);
sqlite-vec two-tier rescore -> Q-a2b -- port mechanics, probe-gate each,
attribute the source, relay platform blockers the moment they bite.

1. **ALL SLICES DONE + v1.0.0-rc.1 PREPARED + five registry surfaces
   live (`xiom.wal`, `xiom.metrics`, `xiom.rate`, `xiom.http` status
   subset, **`xiom.vectors` swapped -- the package now backs all vector
   consumers**) + compiler **v0.64.5** installed lane-local (isolated;
   81st pass -- thread gate GREEN, C-13/C-14/C-15 + phantom verified;
   re-pin HELD on XVC-C-16).**
   Remaining order: **Q-a1 + Q-a2a DONE (66th/67th passes)** -- the
   quantization module + the segment v2 artifact are in and gated;
   **Q-a2b** (read-path wiring: scan sealed segments via codes + exact
   rescore) lands with D5's multi-segment reads (stdlib fsync gate).
   **Owner directive 2026-10-11 11:59Z (engine P3 / vulkan-sdl /
   package coverage) was routed read-only** to bindings
   (`REL-20261011-1203-xvector`: their in-flight sdl3 0.8.0 present-path
   batch matches the engine ask) and packages
   (`REL-20261011-1203-xvector-2`: keep the publish chain current; sdl3
   0.7.0 published eco-v0.1.142, 0.8.0 in flight).
   **Closed loop 13:07Z: `xiom.sdl3` 0.8.0 published (sha256
   `5849f0cf...`); independent registry-artifact verification from this
   lane (hidden-window RGBA blit, engine P3 acceptance shape) GREEN --
   exit 0, SDL3 3.4.8; result relayed to engine
(`REL-20261011-1307-xvector`). The engine's windowed-demo blocker is
cleared on the published consume path.** -> Q-serve applied (69th pass):
the lane's **first user-testable artifact** -- `src/api/httpd.xi` +
`xvectord.exe` (socket adapter over stdlib `xiom.net`, strict framing,
quit header), `probe_http_server` (10 checks over real sockets) x2
Windows + WSL, and a **curl end-to-end user test** (health -> create ->
upsert -> search returns the correct nearest id -> stats -> clean quit).
F 89 -> 96, overall -> **82 %**. -> benchmark integration (70th pass):
`GET /version`, index configuration at create (hnsw/flat + params),
per-request `ef_search` (no-rebuild beam override), `xvectord` applies
the `XVECTOR_MAX_*` limits per request; new `bench/adapters/` (stdlib
HTTP client + ann-benchmarks module/config + live smoke: recall@10 1.000
at ef>=64, 0.940 at ef=8); **F 96 -> 100, overall 82.12 -> 82 %** -> the
first HTTP-path benchmark exposed a stdlib blocker (71st pass):
**`json_parse` is quadratic on numeric payloads** (2.5k/5k/10k/20k
numbers -> 248ms/1.10s/4.77s/17.9s; the 50k-number 382KB upsert body ->
83.7s = ~88% of the request; engine itself 2ms/insert). Repro pinned
(`docs/repro/xv-json-parse-quadratic/`, gate fails pre-fix) and filed to
stdlib (`REL-20261011-1453-xvector`, high); HTTP-path numbers recorded
in `docs/BENCHMARKS.md` (upsert 661s/5k parser-dominated; recall curve
correct: 1.000 at ef>=64, 0.940 at ef=8). **Next slice: a lane-local
fast numeric scanner for the upsert hot path** (benchmarks unblocked
regardless of the stdlib fix timeline). -> fast scanner applied (72nd
pass): ROOT CAUSE of the quadratic = **`slice.str_bytes(Str)`
superlinear** (stdlib lane root-caused it to `strnlen` accessors; fix is
their wave-111 top candidate, `6fbd336`). Lane now keeps bodies as BYTES
(`HttpRequest.body_bytes`) and scans the canonical upsert body at byte
level (`src/api/json_fast.xi`), gated by `probe_json_fast` (228
fast-vs-strict cases byte-for-byte; 52k numbers 1.7-2.9s vs strict ~84s);
**5k x dim-25 fit through `xvectord` 661s -> 120s** (now HNSW-build
bound). Compiler fn-value ABI batch `fde5548e` + stdlib wave 110
(`b8eda7d`) landed during the pass -- re-verification era begins.
   Then: the **`xiom.ann` porter flow -- watch CLOSED; `xiom.ann` 0.2.0
   LIVE + verified in the lane home (m0 / headroom 0.2 / `hnsw_new_full`
   present; sha256 `0a243ce4...`); evaluation `docs/XIOM-ANN-EVAL.md`;
   **owner greenlight requested (`REL-20261011-1308-xvector`; vectors
   precedent `-1550-xvector-12`) -- the swap is the next xvector slice on
   go**; the replay-loop delegation at the D-ledger store migration, then
   the owner's public release + benchmark.
   Gated pivots: D5/D6 on the stdlib fsync chain (still Err stubs at
   `35e6d87`/`2ab2a13`), P5 on
   stdlib mmap, `xiom.kv` on C-PULSE-10 + fsync. (The socket adapter
   pivot CLOSED: `xvectord` shipped on the stdlib `xiom.net` layer.)
2. **M-Q query surface: DONE (Q1-Q6** -- range search, batch ops,
   pagination, delete-by-filter, per-collection stats + index admin,
   SearchRequest extensions). All gated by their probes.
3. **M-G truth & measurement: DONE (G1-G3)** -- reference-oracle
   cross-check, `bench/` harness, `docs/BENCHMARKS.md` baseline +
   external-benchmark protocol (this is what the owner's benchmark
   drives).
4. **M-S server & security: DONE (S1-S4** -- HTTP skeleton,
   config/limits/errors, API-key auth + rate limiting, security pass +
   SBOM); **M-O observability DONE** (metrics//metrics/logs/runbook).
5. **Gated (pick up when the stdlib lane lands the primitives):** D5 delta
   append + fsync + file-level kill-matrix; D6 truncate-based retention;
   P5 mmap segments. Re-check each pass (0.64.3: still stubs --
   `docs/STDLIB-WISHLIST-XVECTOR.md`).
6. **Porter flow (owner-gated):** `xiom.vectors`/`xiom.ann` extraction on
   greenlight (items `REL-20261010-1550-xvector-9/-10/-12`); **`xiom.wal`
   ADOPTED** (0.1.0 registry install + trust pin + `xiom.toml
   [dependencies]`; C-PULSE-02 resolved; gate `probe_package_wal`);
   `docs/PACKAGE-WISHLIST-XVECTOR.md` keeps the lane ledger.
7. **Release gate:** when the M-R criteria are met the lane tells the owner
   -- the owner sets up the public release + benchmark (PULSE-style).

## 2. Consumer-lane rules (non-negotiable)

- **Reference study area (owner-granted, 2026-10-11): `E:\repos` may hold
  cloned MIT-licensed projects as STUDY references -- ideas, patterns,
  mechanics from battle-tested production code -- to elevate xvector.
  Rules: MIT only; study, never vendor blindly or add as a build
  dependency; any adopted pattern is re-implemented in our module tree
  under our license and gated by our probes (commit notes the source
  reference).** Cloned and MIT-verified 2026-10-11: `sqlite-vec`
  (MIT/Apache; compact embeddable vector search -- brute-force kernels,
  quantization, host ergonomics), `faiss` (MIT; HNSW/IVF/PQ mechanics,
  memory mapping, SIMD layouts), `DiskANN` (MIT; SSD-resident ANN --
  informs D5/D6 segment reads + P5 mmap). Sibling-lane references already
  present: `redb`/`bbolt` (storage lanes), `godot`/`JoltPhysics` (game
  lanes). Study backlog (one item per slice, findings recorded in the
  slice docs): (1) faiss HNSW level assignment + search sampling vs ours;
  (2) faiss/vec product quantization for compaction; (3) sqlite-vec
  quantized brute-force kernels vs our flat scan; (4) DiskANN layout
  notes for D5 delta segments + P5 mmap.   Study item 1 (FAISS HNSW)
  DONE 2026-10-11 -> `docs/REFERENCE-STUDY-01-FAISS.md` (ranked
  proposals: P-a level-0 degree generosity **APPLIED 2026-10-11, 63rd
  pass** -- `m0 = 2*m` + FAISS `prune_headroom` 0.2, codec v3, hard-corpus
  control gate 285/300 vs 275/300; the fill arm measured and not adopted;
  gate `probe_hnsw_recall` + refreshed per-ef table; P-b visited
  generation tags for M-P; study 02 quantization DONE 2026-10-11, 64th
  pass -> `docs/REFERENCE-STUDY-02-QUANTIZATION.md` -- Q-a (SQ8 trained
  ranges + two-tier exact rescore for sealed segments) is the first
  adoption candidate; PQ deferred pending deterministic training; a
  documented error-bound story is required before any lossy path; study
  03 DiskANN layout DONE 2026-10-11, 65th pass ->
  `docs/REFERENCE-STUDY-03-DISKANN.md` (sector-packed records for
  D5/D6/P5: 4096 B sectors, no node split, co-located f32 + adjacency,
  buffer-then-seal deltas, delete-by-rebuild, alignment as a format
  decision; backlog item 3 folded into study 02; **study backlog
  complete**); **Q-a1 DONE 2026-10-11, 66th pass** -- `src/index/quantize.xi`
  (trained ranges, truncation codec, query tables, two-tier rescore) +
  `probe_quantization` (17 checks) + suite Section 16 (6 checks);
  Q-a2 (segment/read-path wiring) queued behind D5; XVC-C-15 filed
   during the slice).**
- **Owner guidance (2026-10-12):** prefer porting battle-tested mechanics
  from the MIT reference repos over first-principles design -- translate
  patterns/kernels into our own modules (study rule above: re-implemented
  under our license, probe-gated, source noted) and relay any platform
  blocker (compiler/stdlib/packages/bindings) upstream immediately.
  Queued ports: FAISS PQ codebook/training -> P4 IVF-PQ prototype; FAISS
  visited-set pruning -> P-b (M-P); DiskANN sector layout + merge ->
  D5/D6/P5; sqlite-vec two-tier rescore -> Q-a2b read path. First relay
  of this pass: `REL-20261012-1417-xvector` (accelerator-mirror gate MET;
  M-P3 kernel-surface ask to bindings) -- answered by bindings
  (`REL-20261012-1500-bindings-2`, acked+fixed 2026-10-12): ABI = flat
  contiguous f32 ptr+len in, caller-owned out-ptr, per-call batch kernels
  (dot/l2/cosine), SIMD-width query; **no kernels package/timeline yet**
  (their SDK100/RHI wave first) and the hard gates stay compiler-side
  (vector codegen + thread runtime `-1402`). The M-P3 seam will target
  that ABI (no handle/arena dependence). **Owner-requested production
  relay (2026-10-12):** `REL-20261012-1945-xvector` (gap matrix vs the
  reference league, to all), `-1945-xvector-2` (stdlib mmap ask),
  `-1945-xvector-3` (compiler SIMD-route ask).

- **Coordination bus (2026-10-10, owner rollout): at session start and
  before finishing any task, pull `E:\xiom-lang\xiom-relays`
  (`git pull --ff-only`) and process items addressed to this lane
  (`python tools/relay.py view --lane xvector`). Recurring doorbell: a
  3-hour cron session check is armed.** **Owner directive (2026-10-11
  11:59Z): "prioritize xiom engine request on vulkan sdl etc and whatever
  packages need to be covered 100%" -- routed read-only by this lane to
  the right owners: `REL-20261011-1203-xvector` (-> bindings: engine
  present-path ask `-1153-engine`, their in-flight sdl3 0.8.0 batch
  matches it) + `REL-20261011-1203-xvector-2` (-> packages: keep the
  sdl3/vulkan publish chain current). This lane did not write to the
  bindings/packages/engine workspaces (live writers; coordination-only).** **Ops hygiene rules
  (`REL-20261011-1134-ops`, to: all, 2026-10-11): never delete or
  downgrade the shared homes (`%LOCALAPPDATA%\xiom*`,
  `~/.local/share/xiom`, `~/xiom`); install/uninstall/cleanup tests run
  against an isolated `XIOM_HOME` + lane-local toolchain; announce
  destructive windows with a to: all info item before starting; on
  sudden unresolved-package T001s, stop, rerun once, file to ops with
  timestamps if it recovers.** (Info item from orbitdb
  `REL-20261011-1127-orbitdb` answered: hybrid T001s were package
  resolution, not our pin -- see our reply `REL-20261011-1146-xvector`.)
- **Compiler batch plan (`REL-20261011-1342-compiler`, 2026-10-11
  13:42Z): six fix batches; xvector's are #6 Float32 slot stores
  (XVC-C-15; witness `docs/repro/xv-f32-slot-literal-write/`, expect
  exit 0 post-fix) and #3 phantom imports (`REL-20261010-2124-xvector`;
  expect one clear error, never a silent build). Keep workarounds until
  each fix ships, then re-verify from the witnesses and re-run the full
  batteries both platforms (protocol filed as `REL-20261011-1426-xvector`;
  owner directive: continue until the compiler release unblocks).**
- **Shared bus clone:** the local `xiom-relays` working copy is shared by
  several lane sessions on this machine -- scope `git add` to your own
  item files (never `git add .`), expect commits interleaved by other
  lanes, and re-pull before every transition batch. Ops item
  `REL-20261010-1709-compiler` tracks per-lane clones / a
  `relay.py commit --lane` helper (helper now exists: use
  `python tools/relay.py commit --lane xvector <ids...>`).
- **Shared-machine rule (2026-10-10):** never build against the shared
  toolchain/package homes (`%LOCALAPPDATA%\xiom*`,
  `~/.local/share/xiom`); the dev-env scripts pin lane-local paths
  (`out\toolchain` + `out\xiom-home`; `~/.xvector-toolchain` +
  `~/.xvector-home`). Concurrent sessions deleted the shared state
  mid-battery (`REL-20261010-1835-xvector`); treat sudden
  unresolved-package build errors as environmental first.
- **Never edit another lane's item; open a new item instead** (one item =
  one file; only the addressed lane moves open->acked->fixed; only the
  reporter moves fixed->verified->closed; owner items are the owner's).
- **Never edit** `E:\xiom-lang\stdlib`, `E:\xiom-lang\xiom`,
  `E:\xiom-packages\packages`. Record their HEAD hashes each wrap:
  `git -C <lane> log -1 --format="%h %cI %s"`.
- Upstream reporting now goes through `xiom-relays` items (the relay docs
  keep closed history with a header pointing at the relay ids);
  `RELAY-INTRO-XVECTOR.md` stays as the lane intro.
- Consume packages from the registry only; propose reusable primitives as
  packages (`xiom.vectors` / `xiom.wal` / `xiom.ann`).
- Repo stays private; no pushes (the private relay bus is the only shared
  mailbox); commits signed (`-s`) at every step.

## 3. Module/consumer rules after the final wave

- `src/engine.xi` = facade only (`create_collection`, `upsert`, `search`,
  `delete_point`, `get_point`, `set_payload`, `get_payload`,
  `search_filtered`). Never re-add shims or orchestration here.
- `src/engine/core.xi` = `VectorEngine` + `engine_*` (internal surface).
- `src/core/shim.xi` = xiom-core stand-ins (CoreError/Counter/ids/predicates);
  the porter flow will map it onto the real `xiom.core` package.
- **Consumers that call `engine_*` symbols must `use
  xiom.vector.engine.core;`** in addition to `use xiom.vector.engine;`
  (probes + repro evidence already do).
- Repro evidence copies that import the engine: add the core import when
  re-running them at a new compiler archive.

## 4. Pin discipline that bites (current)

- Initialize every local at declaration; every struct literal lists every
  field (C-PULSE-06). Never module-scope-init from package constructors
  (C-PULSE-07). `convert.int_to_string` instead of `.to_str()` on const
  receivers (C-PULSE-05); explicit `*p` for `&mut Int` reads (C-PULSE-04).
- Types are `Vec[T]`/`Result[T, Err]`; after every write grep for
  `Vec<|Result<|Option<`.
- **XVC-C-07 (fixed v0.64.2): `Str::from_utf8(&Vec[UInt8])` is valid again.**
  The lane uses the `&` spelling (reverted from the by-value workaround);
  repro `docs/repro/xv-from-utf8-vec-ref/` stays as a regression gate.
- **XVC-C-08 (fixed v0.64.2): trailing scalars after a Vec-bearing field are
  readable in large units again.** The suite hydration mirror asserts the
  flags (169 checks); repro `docs/repro/xv-trailing-field-vec/` stays as a
  regression gate. If a future archive reintroduces garbage reads, open a
  delta row instead of re-applying layout hacks.
- **XVC-C-09 (repro green v0.64.2; keep the pattern): build nested values in
  a local and assign the field once.** Always run the WSL spot before
  trusting a green Windows wrap; repro `docs/repro/xv-wsl-nested-field/`.
- **XVC-C-10 (fixed v0.64.2; keep the hygiene): keep large-volume push loops
  behind function boundaries and bound strict decode (`m <= 512`,
  `count <= words.len()`).** Repro `docs/repro/xv-decode-pad-loop/`; general
  gate `probe_fuzz_codecs`.
- **XVC-C-11/C-12 (re-tested green v0.64.2; keep defense in depth): read
  file content as bytes and parse byte-wise; guard short reads with
  `io.file_size` (WAL guard `< 25`).** Repro
  `docs/repro/xv-stdlib-file-read-defects/`.
- **XVC-C-13 (FIXED v0.64.5 / m320 `b672a19f`; the by-value convention
  stays):** was -- never declare `&Str` parameters (the checker warned
  `unknown type '&Str'` and defaulted to i64, then the body read garbage);
  the repro now prints `first_byte(A)=65` with the warning gone on both
  platforms. Pass `Str` by value anyway (lane + stdlib convention). Repro
  `docs/repro/xv-str-ref-param/`; relay Addendum 9.
- **XVC-C-14 (FIXED v0.64.5 / m278 `484d9f21` + m298 `c18e550e`; the
  single-type hygiene stays):** was -- two same-named struct types across
  modules shadowed each other's field layout (clang store reject when the
  shapes differ, silent wrong fields when they match); the bundle now
  builds + runs exit 0. The lane keeps one `Counter` type (engine stats +
  observability on `xiom.metrics`); repro
  `docs/repro/xv-counter-type-shadow/`; relay Addendum 10.
- **Stdlib JSON calls must be QUALIFIED (`json.json_*`) in this lane: the
  parent `xiom.serialize` defines same-named helpers that misresolve
  under the compiler (BUG 25 #1, documented in the stdlib json module
  header); unqualified `json_string()` silently built empty string
  values in `api.http_service`.** Gate `probe_http_service` pins the
  wire behavior.
- **filter_plan helper quirk (loud T001, not silent):** a private helper
  with two `&Vec[Int]` parameters can report `undefined variable` for its
  second parameter (three shapes tried, v0.64.1); inline the logic or use
  single-parameter helpers in `filter_plan.xi`.
- Historical v0.64.0/v0.64.1-era traps (C-01..C-08) are fixed; if any
  reappears, open a delta row instead of re-bisecting (details in the
  findings doc).
- Keep numeric gates per build (suite/probes assert exact bits; red = build
  rejection). Keep watchdogs (`-TimeoutSec`) and gate on exit codes; run
  every green suite x2; redirect long-running output to files; build
  scripts delete stale binaries; use `scripts/lib.ps1` for process capture
  (PS 5.1 `Start-Process` ExitCode is unreliable).
- WSL: default distro is `docker-desktop`; use `wsl.exe -d Ubuntu` for the
  toolchain (`~/.local/share/xiom/bin/xiom`).
- Before trusting a red build, check machine health (`Get-CimInstance
  Win32_OperatingSystem` free memory): a concurrent lane's benchmark once
  starved the machine (free < 1 GB) and produced spurious miscompiles and
  OutOfMemory interrupts in the shell. Re-run on a quiet machine before
  filing anything.

## 5. Ecosystem status (2026-10-12)

- **stdlib:** current lane HEAD `cd281b7` (2026-10-12, docs block 124 --
  the v0.64.4 release check; the tree this pass's batteries ran on: the
  `a996f7b` str-family closure + the `4e8b696` metro revert + the `3df0843`
  v0.64.4 pin). Wave 105.1 `dd352f6`: io `read_file_bytes`
  clause made payload-free -- pulse-reported nested-path static-read
  trap; compatibility re-checked 2026-10-11: suite + codec probe green).
  Wave 102 `5b7bf8f` = **bounded-depth `json_parse` FIXED** -- the
  xvector bus item `-7` is verified + closed 2026-10-10: 128-deep Ok;
  129/60000 Err; Windows + WSL identical. **Re-checked 2026-10-12
  (`cd281b7`): fsync/fdatasync/fsync_dir return Err stubs
  (`xiom/os/fs_ffi.xi`); `mmap_anonymous` still an Err stub --
  the whole mmap family stays open; the fd path (`write_all` etc.),
  `append_file_bytes`, `truncate`/`ftruncate` still open; no
  `f32_bits`/`bits_to_f32`; `flush_stdout` still a no-op** (see
  `docs/STDLIB-WISHLIST-XVECTOR.md`). `io.rename` exists -- atomic
  temp+rename checkpoint hardening is available today (used by M-D1).
  Byte-exact file writes / CRLF-clean reads since 0.64.2. **mmap ask
  ACKED 2026-10-12 (`REL-20261012-1945-xvector-2`, after the production
  relay):** queued in the runtime bundle after the durable-IO P1+P2/P3
  core (real file/anonymous mappings + unmap/msync/madvise; probe locks
  the Err->Ok transition); consumers see it at the next compiler pin that
  re-vendors stdlib/runtime (until then the runtime on v0.64.4 keeps the
  stubs).
- **compiler (CURRENT, 2026-10-15): v0.64.5 installed lane-local** (tag
  `84f761c5`, run `38792051847` green, assets sha256-verified: win
  `bd71e2d3` / linux `246e5e82`; the release wave carries m276-m333 incl.
  the pin-gate round m328-m333). Archive re-verification: **thread gate
  GREEN both platforms** (thread items accept-green; closure held until
  the pass is green), **C-13 + C-14 VERIFIED FIXED** (bus items verified +
  closed 2026-10-15), C-15 + phantom stay green; **NEW XVC-C-16** --
  v0.64.5 linux-x64 miscompiles the HTTP service `/search` path (WSL
  battery red on 6 gates; `REL-20261015-2142-xvector`; **v0.64.5 re-pin
  HELD**). History: v0.64.4 (2026-10-12; tag `df493530`, run
  `38256358845`) -- C-15 + phantom imports VERIFIED FIXED; C-13/C-14
  re-tested unchanged then; thread gate still AVd; verdicts on
  `release-checks/compiler-compiler-v0.64.3`. v0.64.2-era
  re-tests: relayed fixes C-03/06/07/08 verified, C-10..C-12 green
  (Addendum 8). **Findings `acked` by the compiler lane** (both still
  unfixed): **XVC-C-13** (`&Str` parameters unknown to the checker -> i64
  fallback, silent wrong values; Addendum 9) **and XVC-C-14** (same-named
  struct types shadow field layouts; Addendum 10). Compiler-lane local
  main is AHEAD of origin (`91860f11`): v0.64.5 candidate -- **m276-m284
  landed** (T1 env-unwrap m276; T2 cast-call fn code m277; **T3 m278
  `484d9f21` same-named types keep module identity** = the C-14 identity
  mechanic; FFI-pointer batch m279-m281; **m282 `d6690868` = the
  thread/spawn batch: our `-1627`/`-1402-xvector` are `fixed` -- cause 1
  (compiler): `f as *UInt8` on a fn value passed the closure ENV handle,
  now unwraps env field 1 (raw code), lock `ffi_fn_env_cast`; cause 2
  (runtime/stdlib): the spawn result buffer lives in the confined block's
  guard arena and is freed before join (UAF), filed as
  `REL-20261013-1423-compiler` (acked, high) -- **stdlib ADOPTED the proposed hoist (spawn result buffer -> main heap, matching dealloc in join/detach) and LANDED it in wave 131 `664e4a7` (probe p_wave131_shapes 308th; battery green); their spawn e2e note: still hangs on the v0.64.4 pin as expected (m282 not in an archive) -- the flip + e2e re-run queue on the next pin**; our real-spawn acceptance
  re-runs after that fix + the next archive**); m283 contract
  postcondition cycles + nested enum payloads; m284 `&mut local` capture
  in confined blocks (B-21); **m287 `d4e818d6` adapter closure fields win
  over same-leaf free fns (1548-stdlib-3); m288 `554489f5` e2e lock for
  `&mut` parameter field @pre entry snapshots (1548-stdlib-4); next free
  m289; one attempt reverted for 1548-bindings-4 (module-leaf alias
  collision, logged in failed_attempts)**.   (DATED 2026-10-13 state, now superseded: the v0.64.5 tag landed 2026-10-15 and was re-verified -- see the CURRENT entry above; the themed-batch items m276-m333 all shipped in the tag; the thread env fix was m282). Re-checked the bus 2026-10-13T17:05Z: nothing new
  addressed to xvector; stdlib wave 126 (strnlen batch 2) landed.
- **packages:** lane HEAD `674dea9d` (2026-10-12: stage-promotion policy
  per owner; live working tree with in-flight edits -- this lane consumes
  the registry into its own homes, not their checkout). Earlier era:
  **`xiom.ann` extracted**, assimp 0.7.0 + glfw 0.3.0 published,
  eco-v0.1.132, 48 eco releases; xiom.durable port + WAL reconciliation
  wrapped earlier (152/152 x2). **`xiom.wal` 0.1.0 is ADOPTED by XVECTOR
  (2026-10-10)** -- installed from the registry on Windows + WSL (sha256 +
  ed25519 verified), registry key pinned via `xiom pkg trust`
  (fp `4f:3b:47:f3:ae:17:b1:3c`), `xiom.toml [dependencies]` wired
  (C-PULSE-02 RESOLVED in v0.64.2), gate `probe_package_wal`; op codes
  1..7 byte-identical, migration plan in `docs/XIOM-WAL-ADOPTION.md`.
  `xiom.wal` is the single WAL home (`wal_flush` no-op on the same fsync
  gap); the local `durability.wal`/`wal_file` stay until the D5 slice
  swaps the disk segment. **`xiom.vectors` LIVE (eco 508)** and
  **`xiom.ann` extracted** (our wishlist items `-9` fixed / `-10`
  acked; owner greenlight item `-12` still open; porter flow next); a
  WSL `xiom pkg install` custom-`XIOM_HOME` misplacement was found
  during lane-home setup (`REL-20261010-1937-xvector`). **`xiom.metrics`
  0.2.0 + `xiom.rate` 0.2.0 ADOPTED by XVECTOR (2026-10-10, 55th/56th
  passes; see `docs/XIOM-METRICS-ADOPTION.md` /
  `docs/XIOM-RATE-ADOPTION.md`); **router/http evaluated 2026-10-10: the
  `xiom.http.status` helper subset ADOPTED, router/parser not adopted
  (`docs/XIOM-HTTP-EVAL.md`); `xiom.vectors` 0.1.0 WIRED + GATED +
  SWAPPED (59th/60th passes; the package now backs every vector
  consumer -- `docs/XIOM-VECTORS-EVAL.md`)**;
  `xiom.kv` gated on C-PULSE-10 + fsync. Bindings relay (2026-10-09):
  blas-class accelerators stay **GATED** (incubating placeholders, no
  timeline; pilot complete through batch 22) -- sole unscheduled sector;
  M-P3 stays seam-first.
- Registry ready: `xiom.http` 0.1.1, `xiom.jwt` 0.2.0, `xiom.rate` 0.2.0,
  `xiom.metrics` 0.2.0, `xiom.router` 0.1.0, `xiom.http.middleware` 0.1.0,
  `xiom.session` 0.1.0, `xiom.static` 0.1.0, `xiom.kv` 0.1.0. Read
  `E:\xiom-projects\xiom-pulse\SESSION.md` + its relay docs before filing
  anything new (do not rediscover).

## 6. Relay rows (keep updated every wrap)

| Doc | For | State |
|---|---|---|
| `docs/COMPILER-FINDINGS-XVECTOR.md` | compiler | **v0.64.5 (2026-10-16): thread gate GREEN (accept-green; closure held); C-13/C-14/C-15 + phantom VERIFIED FIXED (items `-1550`/`-1709` closed); THREE OPEN: XVC-C-16 (linux service `/search`; fixer m339 in flight; no candidate build; re-pin HELD) + XVC-C-17 (imported-type global pointer-field drop; m337 integrated upstream; re-verify awaits the candidate; `REL-20261015-2216-xvector`) + NEW XVC-C-18 (object-key reads through a `match` binding return garbage; copy-out workaround shipped; `REL-20261016-1541-xvector`); G-1 probe green both platforms; L-0..L-3 landed, L-3 probe green on Windows (WSL spot held)**; history: v0.64.4 verdicts on `release-checks/compiler-compiler-v0.64.3` |
| `docs/RELAY-COMPILER.md` | compiler | Addenda 3-12 (8 = v0.64.2 re-test; 9 = XVC-C-13 `&Str` params; 10 = XVC-C-14 short-name layout shadow; 11 = XVC-C-15 `Vec[Float32]` literal-slot narrowing; 12 = v0.64.4 archive re-verification) |
| `docs/COMPILER-RELAY-2026-10-09-v0.64.2.md` | compiler -> XVECTOR | received; actioned (re-test done, no residual reds) |
| `docs/STDLIB-WISHLIST-XVECTOR.md` | stdlib | re-checked 2026-10-16 (wave 144; **lattice-tier asks added**): fsync trio + fd path + append + fd-truncate + **mmap family (wave 120)** + **signals (wave 123)** + NODELAY/keepalive/backlog (wave 143) + watch (Windows) + `read_at`/`write_at`/`copy_file`/`walk_dir` all LANDED; **open for lattice: POSIX watch, advisory file lock, TLS/ALPN (ecosystem; PULSE-filed), optional poll**; str-bytes/json quadratic + str-family + bounded-depth json closed earlier |
| `docs/PACKAGE-WISHLIST-XVECTOR.md` | packages | refreshed 2026-10-16 (**lattice-tier asks added**): `xiom.wal`/`metrics`/`rate` adopted; `xiom.http` 0.1.6 re-synced (507 closed); `xiom.vectors` swapped; `xiom.ann` 0.2.0 LIVE (swap owner-gated); **new asks: xiom.http CLIENT half as its own surface (router; med-high), TLS binding (high; ecosystem), zstd (med), OTLP exporter (low-med)**; mote publication coordinates here when package-ready (owner directive 2026-10-16) |
| `docs/REFERENCE-STUDY-01-FAISS.md` | (record) | **P-a APPLIED 2026-10-11 (63rd)**: generous level 0 (`m0 = 2*m` + `prune_headroom` 0.2), codec v3, hard-corpus control gate 285/300 vs 275/300; fill arm measured, not adopted |
| `docs/REFERENCE-STUDY-02-QUANTIZATION.md` | (record) | written 2026-10-11 (64th): FAISS SQ/PQ + sqlite-vec int8/binary/rescore/DiskANN recon; ranked Q-a..Q-d (Q-a = SQ8 + exact rescore for sealed segments); error-bound story section; no adoption yet |
| `docs/REFERENCE-STUDY-03-DISKANN.md` | (record) | written 2026-10-11 (65th): DiskANN Rust + sqlite-vec LM-DiskANN recon -- sector-packed fixed-size records, co-located f32 + adjacency, buffer-then-seal deltas, delete-by-rebuild, alignment/format decision for D5/D6/P5; no format change yet |
| `docs/XIOM-HTTP-EVAL.md` | packages (record) | written 2026-10-10: router/http evaluation; status-helper adoption + 507 upstream gap |
| `docs/XIOM-VECTORS-EVAL.md` | packages (record) | written 2026-10-10: extraction fidelity (6/6 pins), wiring + gate, **atomic swap executed** (60th; §3) |
| `docs/XIOM-METRICS-ADOPTION.md` | packages/compiler (record) | written 2026-10-10: observability internals on `xiom.metrics` 0.2.0; XVC-C-14 record + gates |
| `docs/XIOM-RATE-ADOPTION.md` | packages/compiler (record) | written 2026-10-10: S3 token-bucket internals on `xiom.rate` 0.2.0 (carry-exact refill); gates + follow-ups |
| `docs/PULSE-INTEGRATION.md` | PULSE (consumer) | written 2026-10-09; PULSE builds `probe_pkg_xvector` from it |
| `docs/ORBITDB-INTEGRATION.md` | ORBITDB (hybrid pair) | written 2026-10-09 (mirrors their `XVECTOR-INTEGRATION.md`); hybrid probe next |
| `docs/RELAY-INTRO-XVECTOR.md` | ops + all | OPS parked until owner greenlight |
| `docs/PRODUCTION-READINESS.md` | owner | **88 %** (81st pass: G 25 -> 40 on the thread-gate green; v0.64.5 re-pin HELD on XVC-C-16); recompute every wrap |
| **`xiom-relays` (bus)** | all lanes | onboarding ack `REL-20261010-1549-xvector`; migrated open items: compiler `-1550-xvector` + XVC-C-14 `REL-20261010-1709-xvector`, stdlib `-2..-8` (json `-7` verified + closed), packages `-9` fixed / `-10` acked (vectors LIVE + ann extracted), bindings `-11`, owner `-12`; orbitdb item `-1550-orbitdb-11` **closed** by orbitdb; compiler **v0.64.3 released** (`-1727-compiler`; release-check verdicts for C-13/C-14 filed); **shared-home wipe incident `REL-20261010-1835-xvector` (to ops, open)** + **pkg custom-`XIOM_HOME` bug `REL-20261010-1937-xvector` (to packages)** + **507 wishlist `REL-20261010-2002-xvector`**; shared-clone ops item `-1709-compiler` (helper `relay.py commit` now exists); **66th pass: compiler C-15 item `REL-20261011-1134-xvector` filed; orbitdb hybrid note `REL-20261011-1127-orbitdb` acked + answered (`REL-20261011-1146-xvector`: package resolution, not the pin); ops hygiene `REL-20261011-1134-ops` (to: all) incorporated in 2**; 3-hour doorbell cron; **73rd pass: -2002 (507) / -1206 (ann 0.2.0) / -1550-xvector-9 (vectors) / -1835 (hygiene) verified+closed; WIP-verification signal `REL-20261011-1618-xvector` pushed; compiler batch plan `-1342` watched (C-15/phantom not yet landed); thread-gate witness `REL-20261011-1627-xvector` filed; wave-111 CLOSED on `9a2b5ab` -- `-1453`/`-1543` verified + closed; next-archive re-verification set = thread gate + C-15/phantom**; **77th pass (2026-10-12): v0.64.4 verdicts filed (release-check XVECTOR block); `-1134` (C-15) + `-2124` (phantom) verified + closed; `-1310-bindings-2` read + fixed; thread-gate re-run filed `REL-20261012-1402-xvector`; `-1716-orbitdb`/`-1856-stdlib` were fixed by this lane earlier and await their reporters**; **owner-requested production relay (2026-10-12): `REL-20261012-1945-xvector` (gap matrix to all) + `-1945-xvector-2` (stdlib mmap) + `-1945-xvector-3` (compiler SIMD route); bindings ABI answer `-1500-bindings-2` acked+fixed**; **doorbell 20:08Z: stdlib ACKED the mmap ask (runtime bundle, after durable-IO P1-P3); compiler v0.64.5 plan carries our thread items + C-13/C-14 in themed batches (m276/m277 on main; no tag yet)**; **2026-10-13: relayed the window-resize diagnosis to engine (`REL-20261013-1501-xvector`: sdl3 0.18 HAS `sdl3_window_size`/set/resizable + events 518/519; size-readback breakage = compiler B-24/B-20 fixed m281; mini-RHI resize = 0.12.0 tier)**; **doorbell 17:05Z: our thread items `-1627`/`-1402` FIXED by compiler m282 `d6690868` (env-cast cause locked; the guard-arena UAF cause filed upstream as `REL-20261013-1423-compiler`, acked high); v0.64.5 candidate m276-m284, next m285, no tag; stdlib wave 126 (strnlen batch 2) landed; nothing new for xvector**; **17:11Z: engine ACKED the resize diagnosis (`REL-20261013-1501-xvector`) -- package `sdl3_window_size` route confirmed on 0.17.0+v0.64.4 (no hand-rolled ptr readback), events 518/519 mapped, swapchain+scene recreate landed (their 7250546), probe_rhi_vulkan 20 checks x2 + owner-verified interactive resize; our v0.64.5 re-verify stands; stdlib `1445` guard_free fixed (wave 124), `1423` spawn-buffer arena stays acked pending their thread wave**; **19:52Z: engine ask ledger `REL-20261013-1948-engine` (to all; sections for packages/bindings/compiler/stdlib/ops -- NO xvector section; engine to reference sections in future per-lane items); compiler at m290 (next m291), stdlib wave 130; v0.64.5 still untagged**; **22:25Z: stdlib 1423 FIXED (wave 131 hoist `664e4a7`; battery green); compiler fixer wave m291-m295 landed (m291 contract enforcement/paren snapshots; m292 leaf-collision catalog pre-load; m295 by-value UFCS = 1548-stdlib-6 fully fixed); no v0.64.5 tag yet -- fixer wave continues; stdlib block 160 (wave 132 in flight)**; **18:00Z release watch (cron wku_13b432c8): no tag; compiler m320+ with the THREAD GATE GREEN PRE-PIN (stdlib `ae9c963`; pin request filed); stdlib wave 138; bus: nothing new for xvector**; **15th 00:00Z: v0.64.5 tag HELD -- dry-run candidate regressed two stdlib smokes deterministically (Cell[Int8] set/get readback garbage; aes_encrypt_gcm tuple lengths read 0xFFFFFFFF then AV); `REL-20261014-2123-stdlib` acked -> compiler, high; compiler main at release-prep + m321 (empty-Vec bounds); the thread pre-pin green is unaffected; watch continues**; **15th 03:00Z: compiler ACKED `2123` at high (escalated pre-pin; Cell[Int8] = m249/m250-family lock shape); candidate profile: corpus 953/955, probes 310/315 (3 compilefails: zext-float cast, `invariant_check` dup; 2 runfails = tuple-length readback family); the candidate is DEAD for release -- tag stays HELD pending the fixed candidate**; **15th 06:00Z: quiet hold (compiler main unchanged since the 22:47+03 release-prep; no fix commits yet; stdlib block 177 confirms HELD; nothing open for xvector)**; **15th 09:00Z: hold persists -- compiler main unchanged ~18h (session looks dropped mid-triage; fix set owed: 5 candidate regressions); stdlib doorbells every 2h (block 178); release-train stall is compiler-owned, watch continues**; **15th 12:00Z: 2123 FIXED (m323-m326) + m327 follow-up for an m326-caused suite regression; full e2e re-gate running; stdlib freeze/tag on the fresh archive signal; owner: v0.64.5 does not wait for Darwin support; next fires should catch the tag -> then the archive re-verification queue runs**; **15th 15:00Z: `2123` VERIFIED+CLOSED on the green fresh-archive battery + the pushed `stdlib-v0.64.5` tag (moved-tag pipeline all green); compiler `v0.64.5` still UNTAGGED (gh Latest = v0.64.4) -- push/archive pending compiler-side; nothing open for xvector; queue primed**; **15th 18:00Z: compiler v0.64.5 still untagged -- release-lane recovery (retag 092dfa0; m330 advisories/POSIX; m328/m329 fixers; m331 Darwin quick fix; PR assembly next); stdlib registry publish resolved (185b); queue primed**; **81st pass (2026-10-15): v0.64.5 archive verdicts -- `REL-20261010-1550-xvector` (C-13, m320) + `REL-20261010-1709-xvector` (C-14, m278+m298) verified + closed; thread items `-1627`/`-1402` accept-green on both platforms, closure HELD; **XVC-C-16 filed `REL-20261015-2142-xvector`** (v0.64.5 linux-x64 service `/search` miscompile; WSL battery red; **re-pin HELD**); release-check rows updated; pushed `532b20d`**; **G-1 (2026-10-16): C-17 filed `REL-20261015-2216-xvector` (imported-type global pointer-field drop; high); `probe_thread_sync` joins both batteries green; channel cross-thread leg held on C-17**; **16th 11:29Z: lattice-tier asks filed (`REL-20261016-1129-xvector` stdlib / `-2` packages); 11:43Z: stdlib wave-146 POSIX build break filed HIGH (`REL-20261016-1143-xvector` -- runtime `TCP_NODELAY` missing netinet/tcp.h; all WSL consumer builds blocked); C-16 ACKED by the compiler (queued for the v0.64.6 fixer wave); C-17 still open** |
| (lane-local homes) | xvector only | `out\toolchain` + `out\xiom-home` (Win); `~/.xvector-toolchain` + `~/.xvector-home` (WSL) -- isolation from shared-home wipes (2026-10-10) |
| **83rd pass (2026-10-16) bus delta** | all lanes | **XVC-C-18 filed** `REL-20261016-1541-xvector` (pushed `cdeb646`); inbox handling: `-1150-packages-4` (xiom.http client half TAKEN -- router socket-hop input), `-1150-packages-5` (close `REL-20261010-1937` owed -- WSL-pending), `-1155`/`-1304` (http 0.1.7 bump-ready), `-1314-engine-3` (lite-tier embed intent), `-1323-packages-3` (registry-tier release standing order; mote pipeline), `-1446` (codenames convention: mote=registry tier, lattice=standalone); v0.64.6 cut being assembled upstream (stdlib pin ask on the bus; no candidate build yet); doorbell re-armed in-session (3h cron) |

---

## 7. Paste prompt for the next XVECTOR session

> **NOTE (72nd pass):** the prompt below is the older (62nd-pass) version,
> kept as history. The CURRENT prompt is **section 8** at the end of this
> file -- use that one.

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first, then
README/SPEC/ARCHITECTURE/ROADMAP/AUDIT and docs/ (especially
docs/PRODUCTION-PLAN.md + docs/PRODUCTION-READINESS.md and the
requirements/checklists for the v1.0 programme). Consumer lane: never edit
E:\xiom-lang\stdlib, E:\xiom-lang\xiom, E:\xiom-packages\packages. Repo
stays PRIVATE; no pushes. Identity "Lefteris Notas
<lefterisnotas@gmail.com>"; conventional commits, DCO -s.

Orientation: HEAD `9f00836` (feat: reference study 01 P-a -- generous
level 0 + codec v3) +
the wrap commit; tag `v1.0.0-rc.1` on `530b041`; clean tree;
`git log --oneline -12` shows the recent slice commits. Lane pins:
stdlib `35e6d87` (fsync chain still stubs), packages `511dd0f5`
(xiom.ann extracted in-tree, publication pending OPS LIVE; xiom.vectors
LIVE eco 508), compiler **v0.64.3 installed lane-local** (Windows
`out\toolchain`,
WSL `~/.xvector-toolchain`; C-13/C-14 unchanged). **Toolchain + package
homes are lane-local on purpose** (shared homes get wiped by concurrent
sessions -- incident `REL-20261010-1835-xvector`); never point builds at
`%LOCALAPPDATA%\xiom*` or `~/.local/share/xiom`. **Reference study area
(owner-granted): `E:\repos` -- MIT-only clones as study references
(sqlite-vec, faiss, DiskANN already cloned + MIT-verified; rules + study
backlog in SESSION 2; study 01 DONE and **P-a applied** -- findings in
`docs/REFERENCE-STUDY-01-FAISS.md`; study 02 quantization is next).**

Coordination bus (owner rollout 2026-10-10): the private `xiom-lang/
xiom-relays` repo is the only cross-lane channel. At session start and
before finishing any task: `git -C E:\xiom-lang\xiom-relays fetch origin
main` + `git merge --ff-only origin/main` (the clone's bare `pull` hits a
"Cannot fast-forward to multiple branches" quirk)
then `python tools/relay.py view --lane xvector` from that repo; process
items addressed to xvector; never edit another lane's item (open a new
one); commits in the bus are pushed (it is the shared mailbox). A 3-hour
doorbell cron is armed for this session. The local bus clone is shared by
lane sessions on this machine: scope `git add` to your own item files,
re-pull before transition batches, expect interleaved commits (ops item
`REL-20261010-1709-compiler`).

Autonomous mode: arm a session goal with this objective (verbatim):
"Execute docs/PRODUCTION-PLAN.md for xiom-xvector autonomously, one
verified slice at a time, without further user prompting. Work the ordered
slice backlog: all plan slices are done and v1.0.0-rc.1 is prepared;
`xiom.wal` is adopted. Next, in order: `xiom.metrics` 0.2.0 adoption
(observability internals behind the same surface), `xiom.rate` 0.2.0
adoption (token-bucket internals), `xiom.router`/`xiom.http` helper
evaluation. Each pass re-checks the external lanes and pivots when a gate
clears (fsync -> D5/D6, net -> socket adapter, mmap -> P5, kv). Otherwise
maintenance (docs drift, dependency pins, repro re-runs).
Re-check external lanes every pass (stdlib fsync/fd/append chain gates
D5/D6/P5; packages xiom.wal adoption + ops allowlist; compiler archives)
and pivot immediately when primitives land. Per slice: implement, extend
probe/suite gates, run suite x2 + all probes x2 + bench smoke on Windows +
WSL spot, update SPEC/ARCHITECTURE/SESSION/PRODUCTION-READINESS + checklist,
commit signed (-s, identity lefterisnotas@gmail.com). Repo stays private; no
pushes; never edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom,
E:\xiom-packages\packages. When the M-R release criteria are met (green
batteries + kill-matrix + benchmark report + security checklist + SBOM +
complete docs + v1.0.0-rc), report complete with the owner handoff summary
so the owner can set up the public release and benchmark (PULSE-style).
Report blocked only when no scheduled wait or non-gated slice can help."

Safety: check free memory before heavy runs -- bench bring-up once hit
multi-GB paging through the O(L^2) wal_persist (fixed in 5562f67); bench
loops are now hard-capped and monitored. Never raise bench loop budgets
without a memory monitor, and never leave a rebuilt binary from a red build.

Toolchain (latest-tracking): compiler v0.64.2 installed on Windows
(%LOCALAPPDATA%\xiom.new\bin\xiom.exe) and WSL (~/.local/share/xiom, use
`wsl.exe -d Ubuntu`); stdlib lane E:\xiom-lang\stdlib (lane HEAD d2b18dc =
release 0.64.3 registry-LIVE, waves 100-101; durability primitives still
stubs; /mnt/e/... in WSL); XIOM_RUNTIME_DIR
retired. Dot-source scripts\dev-env.ps1 (and .sh twin); scripts\build.ps1/.sh
build; scripts\run-suite.* runs the conformance suite; scripts\run-probe.*
runs probes. Green baseline: suite 171/171 x2 + sbom gate, 37 probes x2
+ bench smoke (quick) on BOTH platforms, all under the lane-local
toolchain + package home (compiler v0.64.3).

DONE: bootstrap; Phase 2 (WAL vector+payload codec, recovery/checkpoint,
in-memory) and Phase 3 (payload filtering + durable metadata); FOUR module
extraction waves, tree final: facade (src/engine.xi) <- orchestrator
(src/engine/core.xi) <- xiom-core shim (src/core/shim.xi), plus payload/
types/storage/query/durability modules; consumers call engine_* via
`use xiom.vector.engine.core;`. SearchRequest wire + with_payload hydration
(engine_search_request / search_with_request; gate probe_search_request).
Sorted payload key index (parallel-vector rows; gate probe_payload_index).
Selectivity pre/post filter planner (query/filter_plan + post path with scan
fallback; gate probe_filter_plan).
HNSW multi-layer graph + recall harness (flat-array graph, geometric levels,
greedy descent + beam honouring ef; tombstone deletes; gate probe_hnsw_recall:
n=200 300/300, n=800 200/200, delete checks vs the flat oracle).
Engine HNSW wiring (set_index Flat/Hnsw, upsert graph upkeep, engine_search
routing with ef=ann.ef_search, filtered stays exact; gate
probe_engine_hnsw: engine recall 200/200, delete/revive, recover+re-apply;
hnsw_compact tombstone compaction + engine compact_index; hnsw_encode/
hnsw_decode strict graph codec; beam construction honouring
ef_construction with diversified pruning; sorted id map; XVC-C-04 shape
pin probe; C-01 bind pin; HNSW+filter integration with exact fallback;
deterministic fuzz gate + decoder hardening [XVC-C-10 found];
mixed-workload soak harness; latency metrics + release battery scripts +
VERSION/checklist; durable collection manifest; HNSW update re-linking;
kill-recovery prefix-exactness acceptance; file-backed WAL (whole-file
checkpoint codec + torn-tail-safe byte-level load; gate probe_wal_file;
both batteries then 18 probes) [XVC-C-11/C-12 found there]; M-D1 atomic
checkpoints via temp+io.rename (7 fault-injection checks); M-Q1 exact range
search (`search_range` facade/engine + `search_range_scan` kernel; gate
`probe_range_search`: 11 checks); M-Q2 batch ops (`upsert_many`/
`delete_many`/`search_many` + `BatchHits`; gate `probe_batch_ops`: 14
checks); M-G bench harness + baseline (`docs/BENCHMARKS.md`; bench smoke in
both batteries) [found + fixed the O(L^2) `wal_persist`; linear builder now
scale-guarded]; native `--icon` embedding wired (images/xvector-icon.ico);
M-D2 manifest file (`xvector-manifest 1` collection registry, atomic
temp+rename, torn-tail-safe load, `engine_manifest_save` +
`engine_recover_file` with facade `save_manifest`/`open_engine`, file-wins
open with in-WAL migration fallback; gate `probe_manifest_file`, 38 checks)
[XVC-C-13 found: `&Str` params mislower to i64]; M-D3 multi-collection
registry (named create/select/drop/list with per-collection isolation; WAL
v2 config + v3 drop records with cid-stamped data; routed multi-collection
recovery + whole-registry checkpoint; whole-registry `save_manifest` +
file-wins `open_engine`; legacy create_collection -> "default"; gate
`probe_collections`, 41 checks); M-D4 sealed segment files
(`segment_file` codec: vectors + payloads + Hnsw graph, atomic persist,
torn-tail-safe load; engine `seal_segment`/`restore_segment` with WAL
re-checkpoint; lifecycle Mutable -> Sealing -> Sealed; gate
`probe_segment_file`, 38 checks); M-Q3 pagination (`query.pagination`
offset + after-id cursor over the (distance asc, id asc) total order;
exact tie order by id; gate `probe_pagination`, 22 checks); M-Q4
delete-by-filter (planner-driven index-candidate or scan delete,
per-point WAL + tombstones + payload/index cleanup; nothing matching ->
Ok(0); gate `probe_delete_filter`, 26 checks); M-Q5 index admin
(per-collection stats + `rebuild_index` with build/compact stats; parked
entries report without switching; gate `probe_index_admin`, 20 checks);
M-Q6 request extensions (SearchRequest mode knn/range + radius + offset/
after-id pagination; SearchBatchRequest + search_batch_with_request
ordered all-or-nothing; gate probe_search_request, 24 checks); M-G1
reference oracle (independent Float64 oracle vs the kernels + axioms +
all ranked/paged/cursor/range/Hnsw paths; deviations at Float32-ulp
scale, bit-identical Win/WSL; gate probe_reference_oracle, 22 checks);
M-S1 HTTP service skeleton (`api.http_service` byte-level HTTP/1.1
pipeline + router; strict parsing, qualified stdlib-JSON wire, honest
statuses; gate probe_http_service, 40 checks); M-S2 service
config/limits/errors (ServiceConfig + env/file loaders; enforced limits
413/400; {error,kind,status} over the full CoreError enum;
http_service_shutdown checkpoint; gate probe_service_limits, 27 checks);
M-S3 auth + rate limiting (API keys via x-api-key with constant-time
compare + scopes read/write/admin + XVECTOR_API_KEYS; token-bucket
RateLimiter with 429; ServiceState + http_service_handle_state; gate
probe_service_auth, 24 checks); M-S4 security pass (SECURITY.md; fuzz
gate 2500 inputs + targeted abuse with the JSON depth guard fixing a
found stack-overflow DoS; SBOM + unsafe gate scripts wired into both
batteries; gate probe_http_fuzz, 14 checks); M-O observability core (histograms +
counters + bounded JSON log ring; public /metrics with gauges + health
readiness; per-request instrumentation; OPERATIONS.md runbook; gate
probe_metrics, 23 checks); M-R release candidate v1.0.0-rc.1 (checklist
audit + repro re-runs + release notes + SBOM snapshot + owner handoff;
final batteries green at the tagged commit); xiom.wal first adoption
(registry install + trust pin + xiom.toml dependency; op-code alignment
gate `probe_package_wal`, 9 checks; D5 migration plan); relay-bus
onboarding (owner rollout; ack + all open items migrated; 3-hour
doorbell cron armed); XV-ORBITDB-01 fix (bus item from orbitdb: chained
persist/load of a recovered WAL reloaded EMPTY because wal_load required
first-LSN == 1; fixed in 3c36f34 -- any starting LSN >= 1, +1 steps
enforced; probe_wal_file +3 chained checks); xiom.metrics 0.2.0 adoption
(observability internals behind the same surface, /metrics byte-identical;
engine stat counters on the package; shim Counter retired after XVC-C-14;
new probe_package_metrics; repro docs/repro/xv-counter-type-shadow);
xiom.rate 0.2.0 adoption (token-bucket internals on the package behind
the same API; carry-exact refill; new probe_package_rate); compiler
v0.64.3 re-pin lane-local (re-tests done; C-13/C-14 unchanged,
release-check verdicts filed; shared-home wipe incident diagnosed + lane
isolated); xiom.http helper evaluation + adoption (status phrases on the
package behind a lane adapter; router/parser not adopted; new
probe_package_http + the 507 wire pin); xiom.vectors 0.1.0 wiring +
fidelity gate (byte-exact carve 6/6 pins verified; new
probe_package_vectors) + **internals swap EXECUTED (atomic; local
modules deleted; codec extracted; batteries green both platforms)** --
37 probes + sbom, suite 171).
FloatVal gates restored after the v0.64.1 fix. Compiler v0.64.2 re-test
(2026-10-09): C-03 (W004=0) and C-06 stay green; C-07 FIXED (&Vec spelling
works; workaround reverted in payload codec + suite); C-08 FIXED (repro +
all 14 variants green; suite hydration flags asserted again, 169 checks);
C-10 FIXED (inline pad no longer crashes); C-11/C-12 re-tested green in the
original context unit; C-09 repro green on WSL (workaround retained).
Retained workarounds (deliberate): SearchHits wrapper (C-04), suite direct
dispatch (C-01), local-assign nested writes (C-09), pad_adj_slots + strict
bounds (C-10), byte parser + file_size guard (C-11/C-12), Str params by
value (C-13).

NEXT TASK: **benchmark starter DONE (70th) and the first HTTP-path run
exposed a stdlib blocker (71st): `json_parse` quadratic -> filed
(`REL-20261011-1453-xvector`) + repro pinned; NEXT SLICE: the
lane-local fast numeric scanner for the upsert hot path so benchmarks
run now.** Also standing: **Q-serve DONE (69th)** (`xvectord.exe`,
curl user test green), `GET /version`, index config at create,
per-request `ef_search`, `bench/adapters/` (ann-benchmarks drop-in +
live smoke green: recall@10 1.000 at ef>=64). Phase F now 100. Next:
the **VectorDBBench client adapter** (same HTTP surface), then the **G-phase
(concurrency/scale)** and D continuation when the stdlib fsync gate
clears; plus the standing queue: **Q-a1 + Q-a2a DONE** (SQ8
module + segment v2 artifact); remaining Q-a2b (read-path wiring; D5),
the ann swap (greenlight requested, `REL-20261011-1308-xvector`), the
standing watches (xiom.ann porter flow, replay-loop delegation, gated
pivots re-checked every pass). **Owner directive routed 2026-10-11
11:59Z** (engine P3 vulkan/sdl priority): read-only routing +
verification (`REL-20261011-1307-xvector`, engine unblocked); this lane
makes no writes into those live workspaces. P-a is DONE (63rd pass). Maintain in parallel: the **`xiom.ann` porter wiring** once the
package is published (extracted in-tree, registry 404 as of 2026-10-11;
watch the packages lane's scope item `REL-20261010-1908-packages`; the
wiring follows the vectors pattern: dependency + extraction-fidelity gate
+ atomic swap), the replay-loop delegation at the D-ledger store
migration, then the owner's public release + benchmark (the v1.0.0-rc.1
candidate and owner handoff stand). Each pass: re-check
the external lanes and pivot when a gate clears (D5/D6 on the stdlib
fsync chain, socket adapter on xiom.net, P5 on stdlib mmap, xiom.kv on
C-PULSE-10). Non-gated work proceeds while the stdlib
fsync chain stays pending (v0.64.3-era: still stubs). When the M-R release
criteria are met, TELL THE OWNER (public release + benchmark setup is the
owner's action, PULSE-style). C-01/C-02/C-04 unwinds are optional
deliberate API decisions, no longer compiler-blocked.
Keep the wrap discipline: full batteries (scripts/ci.ps1 + ci.sh, suite x2
+ sbom + 37 probes x2 + bench smoke), signed commits, docs updated.
Never build against the shared toolchain homes (lane-local pins only).

Discipline: struct literals list every field; locals initialized; `Str`
params by value (XVC-C-13); numeric gates per build; watchdogs + exit
codes; check free memory before trusting a red build; suite x2 green before
any wrap; WSL spot every wrap; update
SESSION.md STATE + relay rows + docs/PRODUCTION-READINESS.md at every wrap;
commit signed at every step.
```


## 8. PASTE PROMPT for the next XVECTOR session (72nd pass, superseded by 9)

> **NOTE (73rd pass):** the prompt below is the 72nd-pass version, kept as
> history. The CURRENT prompt is **section 9** at the end of this file --
> use that one.

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first, then
README/SPEC/ARCHITECTURE/ROADMAP/AUDIT and docs/ (PRODUCTION-PLAN,
PRODUCTION-READINESS, BENCHMARKS, and the benchmark adapters). Consumer
lane: never edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom,
E:\xiom-packages\packages. Repo stays PRIVATE; no pushes except the private
xiom-relays bus. Identity "Lefteris Notas <lefterisnotas@gmail.com>";
conventional commits, DCO -s.

Orientation: HEAD 5fce3cf (feat: byte-level fast upsert scanner) + this
wrap commit; tag v1.0.0-rc.1 on 530b041; clean tree. The lane is
USER-TESTABLE and benchmark-integrated: out\xvectord.exe (HTTP server,
curl-verified, /version, index config at create, per-request ef_search),
bench/adapters (ann-benchmarks drop-in module+config, stdlib client,
smoke.py, quick_bench.py), and the byte-level fast upsert scanner (228-case
fast-vs-strict byte-equivalence gate; 5k x dim-25 fit 661s -> 120s, now
HNSW-build-bound). Lane pins: stdlib b8eda7d (wave 110; the str_bytes/
json_parse quadratic was root-caused there to the strnlen accessors -- fix
is the wave-111 top candidate, note 6fbd336), packages 263684d9 (sdl3
0.13.0; xiom.ann 0.2.0 LIVE), compiler fde5548e (fn-value ABI batch:
C-boundary marshaling, cast-fn-ptr Float64 returns, Vec[fn] arity --
closes the bindings/pulse items).

RE-VERIFICATION ERA -- DO THIS FIRST (unblocking events landed while we
worked):
1) Check the lanes for the next compiler release + the stdlib wave-111
   strnlen fix (git log in E:\xiom-lang\stdlib + E:\xiom-lang\xiom; bus
   view). If a new compiler release exists: install lane-local (Windows
   out\toolchain + WSL ~/.xvector-toolchain; never the shared homes),
   then re-run the C-15 repro
   (docs\repro\xv-f32-slot-literal-write: expect exit 0) and the
   phantom-import controls (expect exactly one clear error), and drop
   the explicit `as Float32` workaround in probe_quantization if green.
2) If stdlib fixed the strnlen accessors: re-run BOTH probes in
   docs\repro\xv-json-parse-quadratic (expect exit 0) and re-run
   quick_bench.py against xvectord (expect a further upsert speedup).
3) Run the full batteries on the new pins (suite x2 + sbom + 40 probes
   x2 + bench smoke, Windows; WSL spot) and update the records.

Relay bus FIRST and LAST: git -C E:\xiom-lang\xiom-relays fetch origin
main; git -C E:\xiom-lang\xiom-relays merge --ff-only origin/main (bare
pull hits a multi-branch quirk); python tools/relay.py view --lane xvector;
process items (ack/fix with refs; never edit another lane's item; push only
xvector items). Arm your own recurring 2-4h doorbell check.

Autonomous mode: arm a goal with this objective (verbatim): "Continue the
xiom-xvector lane from SESSION.md: re-verify on the new compiler/stdlib
pins first (C-15 repro, phantom-import controls, the strnlen/str_bytes
repros, quick_bench, then full batteries both platforms), then proceed
with the VectorDBBench client adapter and the remaining queue (Q-a2b at D5,
the ann swap on owner greenlight REL-20261011-1308-xvector, G-phase
groundwork); keep the xiom.ann porter wiring watch and the gated pivots
re-checked every pass (stdlib fsync -> D5/D6, mmap -> P5, xiom.kv). Per
slice: implement, extend probe/suite gates, run suite x2 + sbom + all
probes x2 + bench smoke on Windows + WSL spot, update
SPEC/ARCHITECTURE/SESSION/PRODUCTION-READINESS + checklist, commit signed.
When the M-R criteria are met, report complete with the owner handoff
summary. Report blocked only when no scheduled wait or non-gated slice can
help."

Toolchain: dot-source scripts\dev-env.ps1 (and .sh twin); scripts\build.ps1
/.sh; run-suite.*; run-probe.*; bench.ps1/.sh; bench\adapters\smoke.py +
quick_bench.py against a running out\xvectord.exe (start it with raised
caps: XVECTOR_MAX_REQUEST_BYTES=33554432 XVECTOR_MAX_BATCH=1000). Green
baseline: suite 177/177 x2 + sbom (42 modules, unsafe=0) + 40 probes x2 +
bench smoke. Discipline: struct literals list every field; locals
initialized; Str by value (XVC-C-13); json.json_* qualified; NEVER
str_bytes/str_slice big Strs (quadratic on this pin -- keep bodies as
bytes); suite x2 + WSL spot before any wrap; check free memory before
trusting reds; bench loops hard-capped; the bindings/packages/engine
  workspaces are read-only for this lane.
```

---

## 9. PASTE PROMPT for the next XVECTOR session (73rd pass, superseded by 10)

> **NOTE (context handoff):** the prompt below is the 73rd-pass version,
> kept as history. The CURRENT prompt is **section 10** at the end of
> this file -- use that one.

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first, then
README/SPEC/ARCHITECTURE/ROADMAP/AUDIT and docs/ (PRODUCTION-PLAN,
PRODUCTION-READINESS, BENCHMARKS, and the benchmark adapters). Consumer
lane: never edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom,
E:\xiom-packages\packages. Repo stays PRIVATE; no pushes except the private
xiom-relays bus. Identity "Lefteris Notas <lefterisnotas@gmail.com>";
conventional commits, DCO -s.

Orientation: HEAD de151d6 (feat: xiom.http 0.1.6 re-sync) + the 73rd wrap
commit; tag v1.0.0-rc.1 on 530b041; clean tree. The lane is USER-TESTABLE
and benchmark-integrated: out\xvectord.exe (HTTP server; /version, index
config at create, per-request ef_search), bench/adapters (ann-benchmarks
+ VectorDBBench drop-ins + stdlib client + smoke.py + smoke_db.py +
quick_bench.py), and the byte-level fast upsert scanner (228-case
fast-vs-strict gate). Fit history: 661 s ->
120 s -> 57.4 s (87 pts/s on the wave-111 WIP; HNSW-build bound). Lane
pins: stdlib b8eda7d (wave 110) + the wave-111 WIP working tree (json.xi
E69E0275..., slice.xi 874A8F67..., string.xi 36D1F4FF...; BOTH repros
exit 0; formal verify/close on REL-20261011-1453-xvector when the wave
commits -- watch git log in E:\xiom-lang\stdlib + the bus); packages
fb73c5c8 (sdl3 0.15.0; xiom.ann 0.2.0 LIVE + verified; xiom.http 0.1.6
CONSUMED -- native 507); compiler fde5548e lane HEAD (v0.64.3 installed
lane-local; C-15 + phantom-import fixes NOT yet landed; no release past
v0.64.3).

RE-VERIFICATION ERA -- NEXT STEPS (in order):
1) Wave-111 closure: DONE (2026-10-11; stdlib `9a2b5ab` committed; both
   repros exit 0 Windows + WSL; batteries green; fit 51.2 s / 98 pts/s;
   bus `-1453`/`-1543` verified + closed). Only the upstream note
   remains: `str_chars`/`str_code_points` still use the strnlen
   accessors -- re-check if a future wave touches them.
2) Compiler watch: batches #3 (phantom imports / -2124) and #6 (Float32
   slot stores / XVC-C-15 / -1134) are staged but NOT landed (no commits;
   no release past v0.64.3). On the next lane-local release install:
   re-run the C-15 repro (docs\repro\xv-f32-slot-literal-write; expect
   exit 0) and the phantom-import controls (expect exactly one clear
   error), re-test C-13/C-14 from their bundles, and drop the explicit
   `as Float32` workaround in probe_quantization if green. Also re-run
   the thread gate (docs\repro\xv-thread-abi\probe.xi; expect exit 0 =
   G phase unblocked; witness REL-20261011-1627-xvector).
3) Done since: VectorDBBench adapter (74th), G-phase thread gate +
   `docs/G-PHASE-PLAN.md` P1, wave-111 closure, P2 memory estimate +
   thresholds (`fcd2f64`; 41 probes). Next queue: P3 SIMD seam / P4
   IVF-PQ prototype (M-P), the sharding harness story (G v1), owner-
   gated ann swap REL-20261011-1308-xvector; Q-a2b stays at D5.

Relay bus FIRST and LAST: git -C E:\xiom-lang\xiom-relays fetch origin
main; git -C E:\xiom-lang\xiom-relays merge --ff-only origin/main (bare
pull hits a multi-branch quirk); python tools/relay.py view --lane xvector;
process items (ack/fix with refs; never edit another lane's item; push only
xvector items with `relay.py commit --lane xvector`). Arm your own
recurring 2-4h doorbell check.

Autonomous mode: arm a goal with this objective (verbatim): "Continue the
xiom-xvector lane from SESSION.md: close the wave-111 loop first (when
stdlib commits the fix: re-run both repros + quick_bench + full batteries,
verify/close REL-20261011-1453-xvector); the VectorDBBench client adapter
is DONE (74th pass) -- work the remaining queue (Q-a2b at D5, the ann
swap on owner greenlight REL-20261011-1308-xvector, G-phase groundwork);
keep the compiler batch watch (C-15 repro + phantom-import
controls on the next lane-local release) and the gated pivots re-checked
every pass (stdlib fsync -> D5/D6, mmap -> P5, xiom.kv). Per slice:
implement, extend probe/suite gates, run suite x2 + sbom + all probes x2 +
bench smoke on Windows + WSL spot, update SPEC/ARCHITECTURE/SESSION/
PRODUCTION-READINESS + checklist, commit signed. When the M-R criteria are
met, report complete with the owner handoff summary. Report blocked only
when no scheduled wait or non-gated slice can help."

Toolchain: dot-source scripts\dev-env.ps1 (and .sh twin); scripts\build.ps1
/.sh; run-suite.*; run-probe.*; bench.ps1/.sh; bench\adapters\smoke.py +
quick_bench.py against a running out\xvectord.exe (start it with raised
caps: XVECTOR_MAX_REQUEST_BYTES=33554432 XVECTOR_MAX_BATCH=1000). Green
baseline: suite 177/177 x2 + sbom (42 modules, unsafe=0) + 41 probes x2 +
bench smoke. Discipline: struct literals list every field; locals
initialized; Str by value (XVC-C-13); json.json_* qualified; keep bodies
as BYTES (the byte-level fast scanner is the canonical upsert path; the
stdlib str_bytes fix shipped in wave 111 -- still prefer byte bodies);
suite x2 + WSL spot before any wrap; check free memory before trusting
reds; bench loops hard-capped; the bindings/packages/engine workspaces are
read-only for this lane.
```

---

## 10. PASTE PROMPT for the next XVECTOR session (current -- context handoff at the 76th wrap, supersedes 9)

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first, then
README/SPEC/ARCHITECTURE/ROADMAP/AUDIT and docs/ (PRODUCTION-PLAN,
PRODUCTION-READINESS, BENCHMARKS, G-PHASE-PLAN, and the benchmark
adapters). Consumer lane: never edit E:\xiom-lang\stdlib,
E:\xiom-lang\xiom, E:\xiom-packages\packages. Repo stays PRIVATE; no
pushes except the private xiom-relays bus. Identity "Lefteris Notas
<lefterisnotas@gmail.com>"; conventional commits, DCO -s.

Orientation: HEAD 6da4c32 (wave-113 re-verification records) + the wrap
commit; tag v1.0.0-rc.1 on 530b041; clean tree. The lane is
USER-TESTABLE and benchmark-integrated: out\xvectord.exe, bench/adapters
(ann-benchmarks + VectorDBBench drop-ins + smoke.py/smoke_db.py/
quick_bench.py), the byte-level fast upsert scanner (228-case gate; fit
661 s -> 51.2 s / 98 pts/s), P2 memory accounting (engine_memory_estimate
+ /stats mem_*; probe_memory_estimate 17 checks). Lane pins: stdlib
f501b65 on a996f7b (wave 113: str-family fully closed; fsync/mmap still
Err stubs); packages fb73c5c8 (sdl3 0.15.0; xiom.ann 0.2.0 LIVE +
verified; xiom.http 0.1.6); compiler **v0.64.4 STAGED, expected
imminently** (batch stack m261-m271 complete; v0.64.3 still the
installed archive; release-prep commit b1ee2f4f, no tag at wrap time).

IMMEDIATE WORK -- the v0.64.4 archive (check git log in E:\xiom-lang\xiom
+ the bus; install lane-local, NEVER the shared homes):
1) Install lane-local on Windows (out\toolchain) + WSL
   (~/.xvector-toolchain), then run the compiler re-verification set:
   - C-15 repro docs\repro\xv-f32-slot-literal-write -> expect exit 0
     (m271/f69b542e); then the reporter verifies + closes
     REL-20261011-1134-xvector;
   - phantom-import controls -> expect exactly ONE clear unresolved-
     import error (m266/m267); then verify + close REL-20261010-2124-
     xvector;
   - C-13 (docs\repro\xv-str-ref-param) + C-14
     (docs\repro\xv-counter-type-shadow) bundles -> re-test;
   - thread gate docs\repro\xv-thread-abi\probe.xi -> expect exit 0
     (fn-ABI batch m263-m265; flips the G phase per
     docs/G-PHASE-PLAN.md; witness REL-20261011-1627-xvector);
   - if green, drop the explicit `as Float32` workaround in
     probe_quantization;
   - set the v0.64.3 release-check rows (release-checks\compiler-
     compiler-v0.64.3.md: XVC-C-13 row, XVC-C-14 row, C-15 row per
     NEXT-BATCH m271) verified, or bounce with evidence; create a
     v0.64.4 check file at the archive if the compiler lane has not.
2) Full batteries both platforms on the new toolchain (suite x2 + sbom
   + all probes x2 + bench smoke, Windows; WSL spot) before re-pinning.

Then the queue (docs/G-PHASE-PLAN.md section 6): P3 SIMD seam / P4
IVF-PQ prototype (M-P), the sharding harness story (G v1), post-gate
G-1..G-4 when the thread gate is green; Q-a2b stays at D5; the ann swap
stays owner-gated (REL-20261011-1308-xvector).

Relay bus FIRST and LAST: git -C E:\xiom-lang\xiom-relays fetch origin
main; git -C E:\xiom-lang\xiom-relays merge --ff-only origin/main (bare
pull hits a multi-branch quirk); python tools/relay.py view --lane
xvector; process items (ack/fix with refs; never edit another lane's
item; push only xvector items with `relay.py commit --lane xvector`).
Arm your own recurring 2-4h doorbell check.

Autonomous mode: arm a goal with this objective (verbatim): "Continue the
xiom-xvector lane from SESSION.md: when the v0.64.4 archive lands, install
it lane-local and run the compiler re-verification set (C-15 repro,
phantom-import controls, C-13/C-14 bundles, the thread gate probe; drop
the `as Float32` workaround if green; set the release-check rows;
verify/close -1134 and -2124), with full batteries both platforms; then
work the remaining queue (P3 SIMD seam / P4 IVF-PQ, the sharding harness
story per docs/G-PHASE-PLAN.md, post-gate G slices when the thread gate
flips, Q-a2b at D5, the ann swap on owner greenlight
REL-20261011-1308-xvector); keep the gated pivots re-checked every pass
(stdlib fsync -> D5/D6, mmap -> P5, xiom.kv). Per slice: implement,
extend probe/suite gates, run suite x2 + sbom + all probes x2 + bench
smoke on Windows + WSL spot, update SPEC/ARCHITECTURE/SESSION/
PRODUCTION-READINESS + checklist, commit signed. When the M-R criteria
are met, report complete with the owner handoff summary. Report blocked
only when no scheduled wait or non-gated slice can help."

Toolchain: dot-source scripts\dev-env.ps1 (and .sh twin); scripts\build.ps1
/.sh; run-suite.*; run-probe.*; bench.ps1/.sh; bench\adapters\smoke.py +
smoke_db.py + quick_bench.py against a running out\xvectord.exe (raised
caps: XVECTOR_MAX_REQUEST_BYTES=33554432 XVECTOR_MAX_BATCH=1000). Green
baseline: suite 177/177 x2 + sbom (42 modules, unsafe=0) + 41 probes x2 +
bench smoke. Discipline: struct literals list every field; locals
initialized; Str by value (XVC-C-13); json.json_* qualified; keep bodies
as BYTES (the fast scanner is the canonical upsert path; the str-family
is linear since wave 113 -- byte bodies remain the design); suite x2 +
WSL spot before any wrap; check free memory before trusting reds; bench
loops hard-capped; the bindings/packages/engine workspaces are read-only
for this lane.
```

## 11. PASTE PROMPT for the next XVECTOR session (refreshed 2026-10-12T13:25; section 10 stays the detailed work order)

> **NOTE (77th pass, 2026-10-12):** the archive work this prompt gated is
> DONE -- the v0.64.4 pass completed (see section 0 and the new section
> 12). Kept as history.

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first: the
operative work order is section 10 (the v0.64.4 archive re-verification
set) with this refresh. Consumer lane: never edit E:\xiom-lang\stdlib,
E:\xiom-lang\xiom, E:\xiom-packages\packages. Repo stays PRIVATE; no
pushes except the private xiom-relays bus. Identity "Lefteris Notas
<lefterisnotas@gmail.com>"; conventional commits, DCO -s.

State at 2026-10-12T13:25: HEAD 8627c69 + the handoff commit; clean
tree; tag v1.0.0-rc.1 on 530b041. The lane has been QUIET since the
76th wrap (the successor session dropped after writing section 10).
Lane pins: stdlib f501b65 on a996f7b (wave 113; fsync/mmap still Err
stubs), packages fb73c5c8 (xiom.ann 0.2.0 live+verified; sdl3 0.15.0),
compiler v0.64.3 installed lane-local (Windows out\toolchain, WSL
~/.xvector-toolchain; NEVER %LOCALAPPDATA%\xiom* or ~/.local/share/xiom
-- shared-home wipe incident REL-20261010-1835-xvector). Installed
batteries were green at the 76th wrap: suite 177/177 x2 + sbom (42
modules, unsafe=0) + 41 probes x2 + bench smoke (Windows) + WSL spots.

THE ONE PENDING TRIGGER -- the v0.64.4 archive: the compiler lane pushed
the pin (df493530, stdlib-v0.64.4 3df0843; m254-m275, Gate A green,
e2e 2480/0) but its handoff records "owner tag command; release run
pending", and ls-remote showed NO v0.64.4 tag as of 2026-10-12T00:00.

Do this, in order:
1) Relay bus FIRST and LAST: git -C E:\xiom-lang\xiom-relays fetch
   origin main; git -C E:\xiom-lang\xiom-relays merge --ff-only
   origin/main (bare pull hits a multi-branch quirk); python
   tools/relay.py view --lane xvector; process items (ack/fix with refs;
   never edit another lane's item; push only xvector items). Bus state at
   refresh: nothing open for xvector (orbitdb/ops closed; stdlib
   str-family fixed awaiting its reporter; bindings/batch-plan acked;
   compiler wave item open to all). Arm your own 2-4h doorbell check.
2) Check the archive: git -C E:\xiom-lang\xiom log --oneline -3; git -C
   E:\xiom-lang\xiom tag -l "v0.64.4*".
   - PRESENT -> execute section 10 exactly: install lane-local (Windows
     out\toolchain, WSL ~/.xvector-toolchain), run the re-verification
     set -- C-15 repro (docs\repro\xv-f32-slot-literal-write; expect
     exit 0, then close REL-20261011-1134-xvector), phantom-import
     controls (expect exactly one clear unresolved-import error, then
     close REL-20261010-2124-xvector), C-13 (docs\repro\xv-str-ref-param)
     + C-14 (docs\repro\xv-counter-type-shadow) bundles, the thread gate
     (docs\repro\xv-thread-abi\probe.xi; expect exit 0 -- flips the G
     phase per docs/G-PHASE-PLAN.md; witness REL-20261011-1627-xvector);
     drop the explicit `as Float32` workaround in probe_quantization if
     green; set the v0.64.3 release-check rows (and create a v0.64.4
     check file if the compiler lane has not); then FULL batteries both
     platforms (suite x2 + sbom + all probes x2 + bench smoke, Windows;
     WSL spot) before re-pinning; commit signed.
   - ABSENT -> do NOT invent a substitute slice; keep the bus watch,
     report state and stand by. The remaining queue (P3 SIMD seam /
     P4 IVF-PQ prototype, the sharding harness story, post-gate G slices,
     Q-a2b at D5, the ann swap on owner greenlight) are fresh-session
     slices for after the archive work.

Standing owner items: the v0.64.4 tag command + release run (compiler
lane's pending owner action -- our trigger); the rc.1 public-release
greenlight (docs/OWNER-HANDOFF.md ready); the ann-swap greenlight
(REL-20261011-1308-xvector). Discipline: struct literals list every
field; locals initialized; Str by value (XVC-C-13); json.json_*
qualified; suite x2 + WSL spot before any wrap; check free memory before
trusting reds; bench loops hard-capped; toolchain/package homes are
lane-local on purpose.
```

## 12. PASTE PROMPT for the next XVECTOR session (refreshed 2026-10-13T16:00Z; supersedes 11)

> **NOTE:** section 11 (the archive-gated prompt) is DONE -- the v0.64.4
> archive landed and the re-verification pass completed (77th pass; C-15 +
> phantom imports verified fixed and closed; C-13/C-14 + thread gate still
> red). This prompt carries the post-archive queue.

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first: section 0 is
the state; sections 10-11 are the completed archive work order (history);
the current queue is section 1 ("77th-pass state") and this prompt.
Consumer lane: never edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom,
E:\xiom-packages\packages. Repo stays PRIVATE; no pushes except the
private xiom-relays bus. Identity "Lefteris Notas
<lefterisnotas@gmail.com>"; conventional commits, DCO -s.

State at 2026-10-13T23:30: HEAD 2552824 + the 80th-wrap commit; clean
tree; tag v1.0.0-rc.1 on 530b041. **D5 + D6 + D7 are DONE (fsync-on-ack +
kill matrix + compact/swap + snapshots + the multi-segment read path;
board 86 %).** v0.64.4 archive pass DONE (C-15 + phantom imports verified
fixed; C-13/C-14 + thread gate still red on v0.64.4; **v0.64.5 candidate
on compiler main at m320+ -- THREAD GATE GREEN PRE-PIN (stdlib
`ae9c963`); pin request filed; the re-verification queue is primed**).
NEXT: the v0.64.5 archive re-verification the moment the tag lands
(thread gate FIRST), then
Q-a2b (SQ two-tier on sealed scans), then M-P (P3/P4). Lane pins: compiler
v0.64.4 installed lane-local (Windows out\toolchain, WSL
~/.xvector-toolchain; NEVER %LOCALAPPDATA%\xiom* or ~/.local/share/xiom);
stdlib 260bb44+ (wave 117+; the tree the batteries ran on); packages
674dea9d (xiom.ann 0.2.0 live + verified; swap owner-gated). Batteries
green at the 80th wrap: suite 177/177 x2 + sbom (**44 modules**, unsafe=0)
+ **44 probes x2** + bench smoke + kill matrix (Windows) + WSL suite x2 +
spots + kill matrix.

Work the queue (docs/G-PHASE-PLAN.md section 6): P3 SIMD seam / P4 IVF-PQ
prototype (M-P), the sharding harness story (G v1), post-gate G slices
(gated: thread gate red), Q-a2b at D5 (stdlib fsync), the ann swap on
owner greenlight (REL-20261011-1308-xvector). Recheck the gated pivots
every pass (stdlib fsync -> D5/D6, mmap -> P5, xiom.kv). Per slice:
implement, extend probe/suite gates, run suite x2 + sbom + all probes x2 +
bench smoke on Windows + WSL spot, update SPEC/ARCHITECTURE/SESSION/
PRODUCTION-READINESS + checklist, commit signed.

Relay bus FIRST and LAST: git -C E:\xiom-lang\xiom-relays fetch origin
main; git -C E:\xiom-lang\xiom-relays merge --ff-only origin/main (bare
pull hits a multi-branch quirk); python tools/relay.py view --lane
xvector; process items (ack/fix with refs; never edit another lane's
item; push only xvector items with `relay.py commit --lane xvector`).
Arm your own 2-4h doorbell check.

Standing owner items: the rc.1 public-release greenlight
(docs/OWNER-HANDOFF.md ready); the ann-swap greenlight
(REL-20261011-1308-xvector). Discipline: struct literals list every
field; locals initialized; Str by value (XVC-C-13); json.json_*
qualified; keep bodies as BYTES; suite x2 + WSL spot before any wrap;
check free memory before trusting reds; bench loops hard-capped;
toolchain/package homes are lane-local on purpose.
```

## 13. PASTE PROMPT for the next XVECTOR session (refresh 2026-10-15T19:30Z; supersedes 12)

> **NOTE:** the v0.64.5 watch FIRED at 19:18Z -- the archive is LIVE. Run
> the queue below FIRST; the M-D backlog follows it.

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first: section 0 is
the state, section 1 the queue context, THIS section the work order.
Consumer lane: never edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom,
E:\xiom-packages\packages. Repo stays PRIVATE; no pushes except the
private xiom-relays bus. Identity "Lefteris Notas
<lefterisnotas@gmail.com>"; conventional commits, DCO -s.

TRIGGER FIRED -- v0.64.5 archive is LIVE: tag 84f761c5, release run
38792051847 fully green, assets live (2026-10-15T19:18Z); stdlib-v0.64.5
tagged + published (`092dfa0` retag; their side closed; 2123 closed).
The thread-gate fixes are IN this archive (m282 env-cast + the stdlib
wave-131 spawn-buffer hoist; pre-pin GREEN at stdlib ae9c963), plus the
C-14 identity fix (m278) and the candidate-regression fixes (m323-m327).
Currently INSTALLED lane-local = v0.64.4; this pass installs v0.64.5.

Do this, in order:
1) Relay bus FIRST and LAST: git -C E:\xiom-lang\xiom-relays fetch origin
   main; git -C E:\xiom-lang\xiom-relays merge --ff-only origin/main (bare
   pull hits a multi-branch quirk); python tools/relay.py view --lane
   xvector; process items (ack/fix with refs; never edit another lane's
   item; push only xvector items via `relay.py commit --lane xvector`).
   The thread items REL-20261011-1627-xvector and REL-20261012-1402-xvector
   are `fixed` by the compiler -- do NOT verify/close them until the
   real-spawn acceptance below is GREEN.
2) Install lane-local BOTH platforms from the v0.64.5 release assets
   (sha256-verified against the release SHA256SUMS; Windows out\toolchain
   [move the v0.64.4 dir aside first -- keep the .bak OUT of the repo,
   under %TEMP%], WSL ~/.xvector-toolchain [old copy to /tmp]); verify
   `xiom --version` reports v0.64.5 on both.
3) Re-verification set (Windows; repeat the key legs on WSL):
   a. THREAD GATE FIRST (the pre-pin green must hold at the archive):
      . .\scripts\dev-env.ps1; .\scripts\build.ps1
      docs\repro\xv-thread-abi\probe.xi -Name repro_thread_abi
      .\out\repro_thread_abi.exe  -> expect EXIT 0 (was 0xC0000005);
      run the marks variant too. On green: the G phase flips per
      docs/G-PHASE-PLAN.md -- record the witness, then verify+close BOTH
      thread items (reporter lane; refs: archive tag + commit).
   b. C-14 after m278: docs\repro\xv-counter-type-shadow (bundle; build
      with the bundle as cwd) -> expect the clang/opt store mismatch at
      xiominput.ll:850 to be GONE (exit 0).
   c. C-13: docs\repro\xv-str-ref-param\probe.xi -> record the value
      (expect 65 if fixed; was 167 Win / 63 WSL).
   d. C-15 regression: docs\repro\xv-f32-slot-literal-write\probe.xi ->
      expect exit 0 (fixed in v0.64.4; must stay fixed).
   e. Phantom-import controls: out\phantom_ctrl1.xi / phantom_ctrl2.xi ->
      exactly ONE error[T001] unresolved import each, exit 1.
   f. Repro sweep: re-run the bundle probes (out\repro_sweep.ps1 may
      exist; else rebuild the list) -- all green except documented reds.
4) FULL batteries both platforms BEFORE re-pinning:
   Windows: .\scripts\ci.ps1 -> ALL GATES GREEN (suite 177/177 x2 + sbom
   44 modules unsafe=0 + 44 probes x2 + bench smoke + kill matrix);
   WSL: bash scripts/ci.sh -> same shape.
5) On GREEN: re-pin the docs and close the loop --
   - SESSION section 0 pins: compiler v0.64.5 installed lane-local; record
     the stdlib tree hash actually used (`git -C E:\xiom-lang\stdlib log
     -1` at battery time) + the packages HEAD.
   - PRODUCTION-READINESS: "As of" + log entry; if the G phase flips, the
     G score moves off 25 (recompute); G-PHASE-PLAN status line;
     OWNER-HANDOFF compiler row.
   - Bus: verify+close -1627/-1402; update the release-check rows (read
     the compiler's latest wave item / check file first -- fill verdicts
     as reporter); commit signed.
   - The batteries above ARE the acceptance; no extra re-runs.
   If ANY red: minimal repro -> `relay.py new` to compiler with the repro
   path + evidence; do NOT close the thread items; continue on
   non-blocked in-lane work.
6) After the archive pass, in-lane backlog (fresh slices): Q-a2b (SQ
   two-tier rescore on sealed scans; unblocked by D7), then M-P (P3 SIMD
   seam -- the bindings kernels ABI is agreed, the package is
   compiler-gated; P4 IVF-PQ prototype from FAISS), then the standing
   queue in section 1. Watch: arm a 2-4h doorbell/cron for post-pin waves
   (stdlib mmap revendoring; the compiler's v0.64.6 list is in their
   handoff).

Standing owner items: the rc.1 public-release greenlight
(docs/OWNER-HANDOFF.md ready); the ann-swap greenlight
(REL-20261011-1308-xvector). Discipline: struct literals list every
field; locals initialized; Str by value (XVC-C-13); json.json_* qualified;
keep bodies as BYTES; suite x2 + WSL spot before any wrap; check free
memory before trusting reds; bench loops hard-capped; toolchain/package
homes are lane-local on purpose; DO NOT import the legacy
xiom.vector.collection.* family (XVC-C-14 trap; the m278 fix is in
v0.64.5 but the wrappers stay dead weight).
```

### Handoff notes (for the record)
- The release-watch cron (`wku_13b432c8`, 3h cadence) lives in the
  PREVIOUS session; a fresh session arms its own watch.
- D7 evidence chain: `probe_multisegment` 27/27; live policy server
  (sealed serving + `/stats` counters + restart); two gate-caught fixes
  (`2552824` request-path union bypass; `71af343` replay symmetry); both
  wrap batteries ALL GATES GREEN (2026-10-13/14); D 95 / overall 86 %.
- The v0.64.5 release survived two holds: `2123` candidate regressions
  (Cell[Int8]/tuple-length readback; fixed m323-m327; stdlib item closed)
  and the release-lane recovery (retag/advisories/PR assembly; run
  38792051847 green).

---

## 14. PASTE PROMPT for the next XVECTOR session (refresh 2026-10-15T22:15Z; supersedes 13)

> **NOTE:** the v0.64.5 archive pass RAN on 2026-10-15. Thread gate GREEN
> on both platforms (G phase flipped); C-13/C-14/C-15 + phantom verified;
> Windows battery ALL GATES GREEN; **WSL battery RED on the new linux-only
> XVC-C-16** (service `/search` miscompile) -- the v0.64.5 re-pin is HELD
> and the thread items' closure is deferred. **G-1 (thread + sync smoke)
> landed 2026-10-16** with a second new finding, **XVC-C-17**
> (imported-type global pointer-field drop; channel cross-thread leg
> blocked). First action: the bus.

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first: section 0 is
the state, section 1 the queue context, THIS section the work order.
Consumer lane: never edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom,
E:\xiom-packages\packages. Repo stays PRIVATE; no pushes except the
private xiom-relays bus. Identity "Lefteris Notas
<lefterisnotas@gmail.com>"; conventional commits, DCO -s.

STATE: v0.64.5 installed lane-local both platforms (tag 84f761c5, run
38792051847; sha256-verified win bd71e2d3 / linux 246e5e82). The archive
pass is COMPLETE except one red:
- WSL battery RED on XVC-C-16 -- v0.64.5 linux-x64 miscompiles the HTTP
  service /search path (404s / bogus range error; smoke-only impact;
  engine probes + suite green; A/B v0.64.4-linux + v0.64.5-windows green;
  bundled-stdlib repro => compiler not stdlib). Repro:
  docs/repro/xv-http-service-linux/; bus REL-20261015-2142-xvector.
  => v0.64.5 re-pin HELD; thread items -1627/-1402 accept-green but
  closure HELD (per the archive-pass protocol).

Do this, in order:
1) Relay bus FIRST: git -C E:\xiom-lang\xiom-relays fetch origin main; git
   -C E:\xiom-lang\xiom-relays merge --ff-only origin/main; python
   tools/relay.py view --lane xvector. Process the C-16 response: if the
   compiler has a fix (item fixed / new archive), re-run the repro under
   the new build on WSL; if not fixed yet, note and continue. Push only
   xvector items via relay.py commit --lane xvector.
2) If the C-16 fix is available: re-install lane-local both platforms from
   the carrying archive (sha256-verified; keep old dirs OUT of the repo),
   re-run: the C-16 repro (expect exit 0 on WSL), then the FULL WSL
   battery (bash scripts/ci.sh -> ALL GATES GREEN) + Windows battery
   (.\scripts\ci.ps1). On all-green: verify+close REL-20261011-1627-xvector
   + REL-20261012-1402-xvector (thread gate; refs archive tag + commit),
   finish the v0.64.5 re-pin docs (SESSION section 0 pins incl. the stdlib
   tree hash + packages HEAD; READINESS; OWNER-HANDOFF row), update the
   release-check rows, commit signed.
3) If C-16 is NOT yet fixed: stay on non-blocked in-lane work, one
   verified slice at a time (suite x2 + probes x2 + WSL spot; signed
   commits; docs updated):
   - G-2 (G-1 landed 2026-10-16: `probe_thread_sync` -- spawn/join +
     mutex + atomics exact on both platforms; the channel cross-thread leg
     is blocked on XVC-C-17): flag-gated accept-loop threads per
     `docs/G-PHASE-PLAN.md` section 3 (after C-16/C-17 or with the
     Int-handle workaround where possible);
   - or Q-a2b (SQ two-tier rescore on sealed scans; unblocked by D7);
   - then M-P (P3 SIMD seam per the agreed bindings ABI; P4 IVF-PQ from
     FAISS).
4) Arm a 2-4h doorbell/cron for post-pin waves (stdlib mmap revendoring;
   the compiler v0.64.6 list: general Darwin work + POSIX fault-trace
   parity + the editor/toolchain W1/W2 batch).

Standing owner items: the rc.1 public-release greenlight
(docs/OWNER-HANDOFF.md ready); the ann-swap greenlight
(REL-20261011-1308-xvector). Discipline: struct literals list every
field; locals initialized; Str by value (XVC-C-13); json.json_* qualified;
keep bodies as BYTES; suite x2 + WSL spot before any wrap; check free
memory before trusting reds (and note a second session may share this
tree -- keep edits scoped, commit promptly); bench loops hard-capped;
toolchain/package homes are lane-local on purpose; DO NOT import the
legacy xiom.vector.collection.* family (XVC-C-14 trap; the m278 fix is in
v0.64.5 but the wrappers stay dead weight).
```

### Handoff notes for the 81st pass (for the record)
- Two sessions ran this pass (the user-pasted session and the backstop
  watch session whose cron fired): the install, re-verification set, both
  batteries, the C-16 diagnosis/repro, the bus verdicts and the docs were
  split across both -- `c828e94` (backstop docs) + this session's commits;
  bus push `532b20d`. Keep future passes single-writer per repo.
- C-16 diagnosis chain: WSL battery 6 red service/search probes -> A/B
  v0.64.4-linux (green) vs v0.64.5-linux (red) vs v0.64.5-windows (green)
  -> bundled-stdlib repro (still red; stdlib ruled out) -> direct-API
  controls green in the same program (context-sensitive miscompile of the
  service handler). Repro bundle + README carry the full table.
- Thread-gate evidence: `probe.xi` exit 0 + `probe_marks.xi` exit 0 with
  last mark `M3: join ok 42`, Windows + WSL; fixes m282 (compiler env
  cast) + stdlib wave-131 hoist + wave-139 i64 trampoline.

---

## 15. PASTE PROMPT for the next XVECTOR session (refresh 2026-10-16T15:00Z; supersedes 14)

> **NOTE:** L-1 + L-2 landed (probes 46/47 in both batteries; Windows
> batteries green); v0.64.5 re-pin HELD on **C-16** (acked -- v0.64.6
> fixer wave); **C-17** open (workaround shipped). First action: the bus
> / the doorbell's report.

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first: section 0 is
the state, section 1 the handoff state + ordered next work, THIS section
the work order. Consumer lane: never edit E:\xiom-lang\stdlib,
E:\xiom-lang\xiom, E:\xiom-packages\packages. Repo stays PRIVATE; no
pushes except the private xiom-relays bus. Identity "Lefteris Notas
<lefterisnotas@gmail.com>"; conventional commits, DCO -s.

STATE: HEAD 0ba7f62 (L-2 collection move) + the wrap commit; v0.64.5
installed lane-local both platforms; batteries green (47 probes x2
Windows; WSL spot + suite green); thread items -1627/-1402 accept-green
but `fixed` (closure deferred); XVC-C-16 ACKED (v0.64.6 fixer wave;
repro docs/repro/xv-http-service-linux/); XVC-C-17 OPEN (workaround in
probe_thread_sync); v0.64.5 re-pin HELD on C-16. Product tiers
xvector-mote/xvector-lattice named + planned; lattice checklist
docs/checklists/lattice-v1.md has L-0/L-1/L-2 done -> L-3 next.

Do this, in order:
1) Relay bus FIRST: git -C E:\xiom-lang\xiom-relays fetch origin main;
   merge --ff-only; python tools/relay.py view --lane xvector. Check
   REL-20261015-2142-xvector (C-16) + REL-20261015-2216-xvector (C-17).
   If the C-16 fix is available (or a new archive carries it): re-install
   lane-local both platforms (sha256-verified; old dirs OUT of the repo),
   run docs/repro/xv-http-service-linux on WSL (expect exit 0), then the
   FULL WSL battery (bash scripts/ci.sh) + Windows (.\scripts\ci.ps1);
   on all-green: verify+close -1627/-1402 (thread gate; refs archive tag
   + commit), finish the v0.64.5 re-pin docs (SESSION section 0 pins incl.
   stdlib tree hash + packages HEAD; READINESS; OWNER-HANDOFF), update the
   release-check rows, signed commit. Push only xvector items via
   relay.py commit --lane xvector.
2) In-lane: L-3 router v1 per docs/checklists/lattice-v1.md (versioned
   mapping file + loader; reverse proxy for the route set + aggregates;
   retry-on-404 stale mapping; probe_router_2shards + routing fuzz; WSL
   spot). Inputs: reference study 04, the packages client-half ask
   (-1129-xvector-2), architecture plan sections 6/9/10.
3) Then L-5 (drain/rebalance + CLI + compaction-aware moves), L-4
   (replica; needs L-3), G-2, then Q-a2b / M-P per section 1's queue.
4) Keep a 2-4h doorbell armed for the C-16/C-17 waves (stdlib mmap
   revendoring signals; compiler v0.64.6 list).

Standing owner items: rc.1 public-release greenlight
(docs/OWNER-HANDOFF.md ready); ann-swap greenlight. Discipline: struct
literals list every field; locals initialized; Str by value (XVC-C-13);
json.json_* qualified; bodies as BYTES; suite x2 + WSL spot before any
wrap; one verified slice at a time; signed commits; keep edits scoped (a
backstop session may share the tree); check free memory before trusting
reds; bench loops hard-capped; toolchain/package homes are lane-local on
purpose.
```

---

## 16. PASTE PROMPT for the next XVECTOR session (refresh 2026-10-16T15:50Z; supersedes 15)

> **NOTE:** L-3 router v1 landed (48th probe; full Windows battery ALL
> GATES GREEN); XVC-C-18 filed (object-key reads through a `match` binding
> return garbage; copy-out workaround shipped). v0.64.5 re-pin still HELD
> on C-16 (m339 fixer in flight; no candidate build). **WSL is PAUSED per
> owner guidance** (other lanes hold the machine) -- the WSL-pending queue
> lives in section 1. First action: the bus / the doorbell's report.

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first: section 0 is
the state, section 1 the handoff state + ordered next work, THIS section
the work order. Consumer lane: never edit E:\xiom-lang\stdlib,
E:\xiom-lang\xiom, E:\xiom-packages\packages. Repo stays PRIVATE; no
pushes except the private xiom-relays bus. Identity "Lefteris Notas
<lefterisnotas@gmail.com>"; conventional commits, DCO -s.
STATE: **v0.64.7 re-pin COMPLETE on BOTH platforms (2026-10-18)** --
Windows (sha `16a436c4`) + WSL (linux `153f0cc9`; target `wsl -d Ubuntu`);
full batteries ALL GATES GREEN both platforms (suite 177/177 x2 + 53
probes x2 + sbom 46 + bench + kill matrix) on stdlib tree `6727526`
(pin tag `1271dd5`) + packages `2e7c5524` (xiom.http 0.1.9; orbitdb 0.2.1
+ pulse 0.2.1 gated); C-16/C-17/C-18 repros green both platforms; all
findings + thread items closed; L-0..L-5 ALL LANDED. **G-1 COMPLETE
2026-10-18** (natural module-level globals + cross-thread mailbox leg; the
Int-handle workaround is retired). **Next: G-2b accept-loop threads**
(`XVECTORD_THREADS`; coarse engine mutex; new concurrency probe; graceful
shutdown). **XVC-C-19 OPEN** (v0.64.7 global-init compiler hang; repro
`docs/repro/xv-global-init-hang/`). Then Q-a2b / M-P; L-6 after.

Do this, in order:
1) Relay bus FIRST: git -C E:\xiom-lang\xiom-relays fetch origin main;
   merge --ff-only; python tools/relay.py view --lane xvector. Check
   REL-20261015-2142-xvector (C-16), -2216-xvector (C-17),
   REL-20261016-1541-xvector (C-18). If the C-16 fix / a v0.64.6 archive
   is available AND WSL is free: execute section 1 ORDERED NEXT WORK
   step 1 (re-install sha256-verified, C-16/C-17/C-18 repros, full WSL +
   Windows batteries, close -1627/-1402, finish the re-pin docs, signed
   commit, relay push).
2) WSL-pending queue (when WSL is free): retest + close REL-20261010-1937
   (custom XIOM_HOME install must land in the home; no C:Userslefte tree;
   re -1150-packages-5); run the L-3 WSL spot (probe_router_2shards +
   suite; C-16 reds are expected -- document as C-16, not L-3); full WSL
   battery with the v0.64.6 pass.
3) In-lane: G-2 (in-process concurrency / `XVECTORD_THREADS`; the channel
   cross-thread leg is unblocked, retire the Int-handle workaround), then
   Q-a2b / M-P per section 1's queue; L-6 (phase B) after. **Protocol:
   always pull the newest stdlib + packages and install the latest
   registry versions into both lane homes before gates (record hashes at
   the wrap).** Router follow-up when the xiom.http client half lands: the
   socket transport replaces the in-process forward at the
   `router_forward_direct` seam.
4) Keep a 2-4h doorbell armed (C-16/C-17/C-18 + archives + the
   WSL-pending queue). If the machine is contended, keep deferring WSL
   legs -- do not fight other lanes for it.

Standing owner items: rc.1 public-release greenlight
(docs/OWNER-HANDOFF.md ready); ann-swap greenlight; README tier story
landed (keep it current). Discipline: struct literals list every field;
locals initialized; Str by value (XVC-C-13); json.json_* qualified;
bodies as BYTES; copy nested map/vec data into locals before iterating
(XVC-C-18); suite x2 + WSL spot before any wrap; one verified slice at a
time; signed commits; keep edits scoped (a backstop session may share the
tree); check free memory before trusting reds; bench loops hard-capped;
toolchain/package homes are lane-local on purpose.
```

---

## 17. PASTE PROMPT for the next XVECTOR session (refresh 2026-10-18T16:2xZ; supersedes 16)

> **NOTE:** v0.64.7 pinned both platforms; **the mote tier is PUBLISHED**
> (`xiom.vectors` 0.2.0, eco-v0.1.198, owner-greenlit, registry
> live-verified). G-1 complete. XVC-C-19 open (compiler hang on global
> initializers). The carve exposed library-mode gaps (section 1 item 0).
> First action: the bus. Immediate work: the library type-check gate + the
> portable fixes, then G-2b.

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first: section 0 is
the state, section 1 the handoff + ordered next work, THIS section the work
order. Consumer lane: never edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom,
E:\xiom-packages\packages. Repo stays PRIVATE; no pushes except the private
xiom-relays bus. Identity "Lefteris Notas <lefterisnotas@gmail.com>";
conventional commits, DCO -s.

STATE (2026-10-18): HEAD ~`8b13e4a`+; compiler v0.64.7 pinned BOTH platforms
(win sha 16a436c4 / linux 153f0cc9; WSL via `wsl -d Ubuntu` -- the default
distro is docker-desktop and has no bash); full batteries ALL GATES GREEN
both platforms (suite 177/177 x2 + 53 probes x2 + sbom 46 + bench + kill
matrix) on stdlib 6727526 (pin 1271dd5) + packages 2e7c5524; L-0..L-5 all
landed (router, move/drain, replica incl. the durable reopen-write fix);
G-1 COMPLETE (natural module-level imported-type globals; the Int-handle
workaround is retired; cross-thread mailbox leg green); MOTE PUBLISHED:
`xiom.vectors` 0.2.0 in eco-v0.1.198 (sha256 130427a5..., carve from
c858ec1, 239 files, lattice modules excluded; owner greenlit). Open:
XVC-C-19 (v0.64.7 compiler HANG on module-level function-call/allocating
`var` initializers; repro docs/repro/xv-global-init-hang/, bus
REL-20261018-1518-xvector; the same shape in a larger module builds then
hangs before main -- never put call/allocate initializers at module level)
and the pulse 0.2.1 stale version identity (accepted, 0.2.2 queued; our
gate accepts the 0.2 series until then). The rc.1 GitHub release set
remains owner-gated (repo private); the release-notes refresh is OWED.

Do this, in order:
1) Relay bus FIRST: git -C E:\xiom-lang\xiom-relays fetch origin main;
   merge --ff-only; python tools/relay.py view --lane xvector. Handle
   anything new; watch for a compiler archive answering XVC-C-19, pulse
   0.2.2, and packages-lane mote follow-ups (the carve's primitives-split
   note is in section 1 item 0).
2) **Library type-check gate + portable fixes** (FIRST slice): apply the
   carve's four fixes (primitives module for internal imports; remove the
   dead `use xiom.core.ids;`; add the core.shim import in
   collection/schema.xi's contract; keep the xiom.http dep), then add a CI
   gate that type-checks `src/` as a LIBRARY (reproduce the carve's green
   45-module tree) so the next carve cannot find these.
3) **G-2b accept-loop threads** (`XVECTORD_THREADS`: accept in one thread,
   per-connection workers, ALL engine calls under one coarse mutex; gates =
   service probes + probe_http_fuzz x2 unchanged + a NEW concurrency probe
   (N clients x deterministic ops -> exact results) + quick_bench QPS delta
   + graceful shutdown joins). Then Q-a2b / M-P; L-6 (phase B) after.
4) **Release notes refresh** (`docs/RELEASE-NOTES-v1.0.0-rc.1.md` is dated
   2026-10-09; the owner reviews it before the rc.1 GitHub release): cover
   D5-D7 durability, SQ, filters/planner, multi-segment, lattice L-1..L-5,
   threads G-1, the package adoptions, the 53-probe batteries, the mote
   publication + lattice release ownership.
5) Keep a 2-4h doorbell armed (C-19 archive, pulse 0.2.2, trees, asks).
6) Latest-tree protocol EVERY pass: pull E:\xiom-lang\stdlib +
   E:\xiom-packages\packages; `xiom pkg info` each consumed package
   (wal/metrics/rate/http/vectors/ann/orbitdb/pulse) and install the latest
   into BOTH lane homes before gates; record hashes in section 0 at the
   wrap.

Standing owner items: rc.1 GitHub release greenlight (OWNER-HANDOFF ready);
ann-swap greenlight. Discipline: struct literals list every field; locals
initialized; Str by value (XVC-C-13); json.json_* qualified; bodies as
BYTES; copy nested map/vec data into locals before iterating (XVC-C-18);
NO module-level initializers that call or allocate (XVC-C-19); suite x2 +
WSL spot before any wrap; one verified slice at a time; signed commits;
keep edits scoped (a backstop session may share the tree); check free
memory before trusting reds; bench loops hard-capped; toolchain/package
homes are lane-local on purpose.
```

## 18. PASTE PROMPT for the next XVECTOR session (refresh 2026-10-18; supersedes 17)

> **NOTE:** the library-gate slice (section 1 item 0) is DONE. The carve's
> four fixes are ported; `scripts/libcheck.ps1`/`libcheck.sh` type-check every
> `src/` module against a carve manifest and enforce the internal-import rule,
> wired into both CIs. Windows full battery + WSL spot are green. Immediate
> work: **G-2b is BLOCKED on XVC-C-20** (2026-10-18: engine-global mutation
> loss; slice reverted, repro filed); next is **Q-a2b / M-P**, then the
> release-notes refresh (still owed).

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first: section 0 is
the state, section 1 the handoff + ordered next work, THIS section the work
order. Consumer lane: never edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom,
E:\xiom-packages\packages. Repo stays PRIVATE; no pushes except the private
xiom-relays bus. Identity "Lefteris Notas <lefterisnotas@gmail.com>";
conventional commits, DCO -s.

STATE (2026-10-18, after the library-gate slice): HEAD = the library-gate
commit (parent 995aa26; 8+ commits ahead of origin). Compiler v0.64.7 pinned
BOTH platforms (win sha 16a436c4 / linux 153f0cc9; WSL via `wsl -d Ubuntu` --
the default distro is docker-desktop and has no bash). This slice: Windows
full battery ALL GATES GREEN (suite 177/177 x2 + libcheck 47/47 + sbom 47
modules unsafe=0 + 53 probes x2 + bench smoke + kill matrix); WSL spot green
(libcheck 47/47 + suite 177/177 x2 + probe_vector_store x2 +
probe_mote_embedded x2) on stdlib 15495aa + packages 0574c0d6.
`xiom.vectors` 0.2.0 (MOTE, eco-v0.1.198) and `xiom.pulse` 0.3.1 are installed
in BOTH lane homes; the manifest pins vectors 0.1.0 + **pulse 0.3.1
(ADOPTED 2026-10-19: exact identity + HookCtx + fallback + HEAD trim,
16/16 x2 both platforms)**.
L-0..L-5 all landed; G-1 COMPLETE; MOTE PUBLISHED. **Compiler v0.64.8 is
pinned both platforms** (win `c31d9c46` / linux `a8c003c0`; v0.64.7
rollback kept); XVC-C-20 verified fixed (repro green both); **G-2b threaded
accept loop COMPLETE** (54th probe green x2 both; Windows full battery ALL
GATES GREEN; WSL suite + UI/concurrency/service probes green; WSL long
sweeps were environment-interrupted by VM restarts, so the full WSL re-run
is queued). **Station web UI MVP LANDED**:
`/ui` static admin + `GET /collections/{n}/sample` + Canvas 2D seeded
random-projection scatter, inspector, search highlighting; `probe_ui` is the
55th probe; a headless-Edge screenshot verified the rendered page. Editor /
three.js-WebGL later (`docs/UI.md`). **No XVECTOR compiler
findings are open** (XVC-C-19 and C-20 were verified fixed on v0.64.8; the
repros stay as regression gates). The rc.1
GitHub release set remains owner-gated (repo private); the release-notes
refresh is DONE (refreshed 2026-10-19 and updated for G-2b/v0.64.8/UI).

Do this, in order:
1) Relay bus FIRST: git -C E:\xiom-lang\xiom-relays fetch origin main;
   merge --ff-only; python tools/relay.py view --lane xvector. Handle
   anything new; watch for a compiler archive answering XVC-C-19, pulse
   follow-ups, and packages-lane carve/mote follow-ups. (XVC-C-20 is
   verified fixed on v0.64.8; no archive watch needed.)
2) **G-2b is COMPLETE (v0.64.8)** -- do not re-implement. **Station web UI
   MVP is DONE** (`/ui` + `/sample`; `probe_ui` 55th; editor/3D optional).
   **Q-a2b is DONE** (sealed Flat SQ coarse + exact rescore;
   `probe_sq_sealed` 56th; bit-identical). **P3 kernel seam is DONE**
   (`src/index/kernels.xi`, `probe_kernels` 57th; scalar default preserved).
   Next in-lane: **L-6 phase B** (router scatter-gather) or **G-3/G-4**;
   **P4 IVF/PQ is BLOCKED on XVC-C-22** (second `pq_train` crash / nested
   codebook corruption; repro `docs/repro/xv-pq-second-call/`; code
   reverted; bus `REL-20261021-1103-xvector`); P5 is stdlib-dependent.
   Keep the threaded path flag-gated (`XVECTORD_THREADS`,
   default sequential) and `probe_concurrency` + `probe_ui` +
   `probe_sq_sealed` + `probe_kernels` in both batteries.
3) **Release notes refresh: DONE 2026-10-19** -- `docs/RELEASE-NOTES-v1.0.0-rc.1.md`
   was refreshed from the 2026-10-09 draft (D5-D7, SQ8 Q-a1/Q-a2a,
   filters/planner, lattice L-1..L-5, G-1, package tiers, 177/53/47
   evidence) and updated for the v0.64.8 pin + G-2b landing. Owner review
   before the rc.1 GitHub release.
4) **Pulse 0.3.1 adoption: DONE 2026-10-19** -- `xiom.toml` pin 0.3.1;
   `probe_package_pulse` gates the exact identity + HookCtx pre->after
   mutation, limiter 429 short-circuit, idempotent clear, the 0.3.1
   unmatched-route fallback seam, and the HEAD wire trim (loopback);
   16/16 x2 Windows + WSL. Recorded in section 0.
5) Keep a 2-4h doorbell armed (C-19 archive watch, trees, asks).
6) Latest-tree protocol EVERY pass: pull E:\xiom-lang\stdlib +
   E:\xiom-packages\packages; `xiom pkg info` each consumed package
   (wal/metrics/rate/http/vectors/ann/orbitdb/pulse) and install the latest
   into BOTH lane homes before gates; record hashes in section 0 at the wrap.

Standing owner items: rc.1 GitHub release greenlight (OWNER-HANDOFF ready);
ann-swap greenlight. Discipline: struct literals list every field; locals
initialized; Str by value (XVC-C-13); json.json_* qualified; bodies as
BYTES; copy nested map/vec data into locals before iterating (XVC-C-18);
XVC-C-19 is fixed on v0.64.8 (module-level initializers are allowed again;
keep the repro as a regression gate); src/ modules
import `xiom.vector.primitives`, NEVER `xiom.vectors` (run
`scripts/libcheck.ps1` or `scripts/libcheck.sh` before a carve/wrap; the
import guard is the authoritative check -- negative-test it if edited); the
SBOM gate scans the literal token "unsafe" in comments too; suite x2 + WSL
spot before any wrap; one verified slice at a time; signed commits; keep
edits scoped (a backstop session may share the tree); check free memory
before trusting reds; bench loops hard-capped; toolchain/package homes are
lane-local on purpose.
```

## 19. PASTE PROMPT for the next XVECTOR session (refresh 2026-10-19 23:20Z; supersedes 18)

> **NOTE:** v0.64.8 re-pin, G-2b, the station web UI MVP, and Q-a2b all
> landed; the **Windows 56-probe battery is ALL GATES GREEN**. The only open
> verification is the WSL long sweep (the VM restarted repeatedly during the
> work window). Next in-lane: **M-P** and **L-6 phase B**; the UI editor /
> three.js upgrade is optional.

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first (section 0 =
state, section 1 = handoff, THIS section = work order). Consumer lane:
never edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom,
E:\xiom-packages\packages. Repo stays PRIVATE. Identity "Lefteris Notas
<lefterisnotas@gmail.com>"; conventional commits, DCO -s.

STATE (2026-10-21): HEAD = the P4 finding commit (parent `74db6c5`); 24
commits ahead of origin; tree clean. Compiler **v0.64.8 pinned both platforms** (win
`c31d9c46`, linux `a8c003c0`; v0.64.7 rollback kept; WSL via
`wsl -d Ubuntu`). Shared stdlib HEAD `750384f` (2026-10-21): the
`ee1a95c` block is **resolved** (bus `REL-20261020-1531-xvector` acked;
builds/checks/suite 177/177 x2 pass); `XVECTOR_STDLIB_BUNDLED=1` remains a
fallback; release tag `stdlib-v0.64.8` = `0bf5b75` (registry publish blocked
upstream `publisher_not_mapped`); packages `ca41d483`. Manifest pins:
vectors 0.1.0 + **pulse 0.3.1** (0.3.1
adopted: exact identity + HookCtx + fallback + HEAD trim). Latest packages
installed both homes: wal 0.1.0, metrics 0.2.0, rate 0.2.0, http 0.1.9,
vectors 0.2.0 (MOTE), ann 0.2.0, orbitdb 0.2.1, pulse 0.3.1.

P4 IVF/PQ is **BLOCKED on XVC-C-22**: a second `pq_train` call crashes
`0xC0000005`; one `ivf_pq_build` returns a corrupted nested codebook
(checksum 370608086 -> 534399819, recon 0.84 -> 4.48e28). Repro
`docs/repro/xv-pq-second-call/`; the prototype was reverted; bus
`REL-20261021-1103-xvector`. Flat/HNSW/SQ are unaffected.

Evidence: **Windows full 57-probe battery ALL GATES GREEN** at the P3 commit
(suite 177/177 x2 + libcheck 48/48 + SBOM 48/0 + 57 probes x2 incl.
probe_concurrency/ui/sq_sealed/kernels + bench smoke + kill matrix). WSL:
suite 177/177 x2 + probe_kernels + probe_ui/concurrency/service family
green; **WSL long sweeps were environment-interrupted** (VM 0-min uptime
restarts) -- re-run the targeted gates + full sweep in a quiet window. C-19
and C-20 are VERIFIED FIXED on v0.64.8; no XVECTOR compiler findings open.

Landed: G-2b `XVECTORD_THREADS` (flag-gated; accept thread + per-connection
workers, one coarse engine mutex, graceful joins; default sequential);
station web UI MVP `/ui` (read-only admin: sampled scatter, inspector,
search highlighting; `GET /collections/{n}/sample`; `docs/UI.md`);
Q-a2b sealed Flat SQ coarse scan + exact f32 rescore (`probe_sq_sealed`,
56th; filtered path stays exact); P3 kernel seam `src/index/kernels.xi`
(scalar default + unrolled same-order kind behind the `xiom.vectors`
contract; hot flat/HNSW/range/pagination/SQ paths branch once per scan;
`probe_kernels` 57th; scalar baseline preserved; no Float32 accelerated
binding yet); **resource guard** (8 GB hard cap for apps/probes via a
Windows Job Object + kill-on-close and WSL `ulimit -v`; compiler builds use
kill-on-close-only jobs because v0.64.8 hangs under a memory-limit job --
XVC-C-21; `run-capped` wrappers; bundled-stdlib fallback). L-1..L-5 landed;
G-1 complete; MOTE published (xiom.vectors 0.2.0, eco-v0.1.198).

Do this, in order:
1) Relay bus FIRST: git -C E:\xiom-lang\xiom-relays fetch origin main;
   merge --ff-only; python tools/relay.py view --lane xvector. Handle
   anything new; watch pulse/trees and any WSL/archive notes.
2) Re-run the WSL gates when the VM is stable: suite x2 + libcheck 48/48 +
   probe_ui/probe_concurrency/probe_sq_sealed/probe_kernels (and the full
   57-probe sweep if it can run uninterrupted; use `out/wsl-battery.log` and
   a quiet window -- do not fight VM restarts). The shared stdlib is fixed
   at `750384f`; `XVECTOR_STDLIB_BUNDLED=1` is the fallback. The frozen
   copies are reference only; the main tree is at the P4 finding commit.
3) **L-6 phase B** (router fan-out + k-way ranked merge + pagination-after-
   merge + strict/partial modes + probe_scatter_gather; name the recall
   definition per arm). **P4 IVF/PQ is BLOCKED on XVC-C-22** (repro
   `docs/repro/xv-pq-second-call/`; prototype reverted); **P5** is
   stdlib-dependent. P3 is done.
4) Optional: station-UI editor + three.js/WebGL upgrade (read-only MVP is
   in; see `docs/UI.md`).
5) Release notes: refreshed 2026-10-20 and current through P3/safety; owner
   review before the rc.1 GitHub release (owner-gated, repo private).

Standing owner items: rc.1 GitHub release greenlight; ann-swap greenlight.
Discipline: struct literals list every field; locals initialized; Str by
value (XVC-C-13); json.json_* qualified; bodies as BYTES; copy nested
map/vec data into locals before iterating (XVC-C-18); C-19 is fixed on
v0.64.8 (module-level initializers allowed again; keep the repro as a
regression gate); C-20 fixed; src/ modules import `xiom.vector.primitives`,
NEVER `xiom.vectors` (run `scripts/libcheck.ps1` / `.sh` before a
carve/wrap; the import guard is authoritative -- negative-test it if
edited); the SBOM gate scans the literal token "unsafe" in comments too;
suite x2 + WSL spot before any wrap; one verified slice at a time; signed
commits; keep edits scoped (a backstop session may share the tree); check
free memory before trusting reds; bench loops hard-capped; **cap every
app/probe run at 8 GB (`lib.ps1` / `run-capped`; WSL `ulimit -v`) and never
launch the app bare; compiler builds are watchdog + kill-on-close only
(XVC-C-21);** toolchain/package homes are lane-local on purpose.
```

## 20. PASTE PROMPT for the next XVECTOR session (refresh 2026-10-21 11:20Z; supersedes 19)

> **NOTE:** the shared stdlib is fixed (`750384f`). P4 IVF/PQ is **BLOCKED
> on XVC-C-22** (second `pq_train` call crashes `0xC0000005`; one
> `ivf_pq_build` returns a corrupted nested codebook; repro
> `docs/repro/xv-pq-second-call/`; prototype reverted). C-21 (compiler
> build hangs under a memory-limit Job Object) stays open. Next: **L-6
> phase B / G-3-G-4**. The WSL full 57-probe sweep is queued (VM
> restarts). The resource guard is active: 8 GB app/probe cap; compilers
> kill-on-close only; WSL `ulimit -v`.

```
You are the XVECTOR session for E:\xiom-projects\xiom-xvector -- the
production-grade XIOM vector database. Read SESSION.md first (section 0 =
state, section 1 = handoff, section 20 = this work order). Consumer lane:
never edit E:\xiom-lang\stdlib, E:\xiom-lang\xiom,
E:\xiom-packages\packages. Repo stays PRIVATE. Identity "Lefteris Notas
<lefterisnotas@gmail.com>"; conventional commits, DCO -s.

STATE (2026-10-21): HEAD = the handoff commit (parent `6b417b2`; ~25
commits ahead); tree clean. Compiler v0.64.8 both platforms (win
`c31d9c46`, linux `a8c003c0`; v0.64.7 rollback; WSL `wsl -d Ubuntu`).
stdlib shared `750384f` (fixed; `XVECTOR_STDLIB_BUNDLED=1` fallback; release
tag `stdlib-v0.64.8` = `0bf5b75`; registry publish blocked
`publisher_not_mapped`). packages `b133b1a7`. Manifest: vectors 0.1.0 +
pulse 0.3.1; installed both homes: wal 0.1.0, metrics/rate 0.2.0, http
0.1.9, vectors 0.2.0 (MOTE), ann 0.2.0, orbitdb 0.2.1, pulse 0.3.1.

EVIDENCE: Windows suite 177/177 x2 + libcheck 48/48 + SBOM 48/0 + 57 probes
x2 + bench smoke green under the 8 GB guard; the aggregate line did not
print because the newly capped kill matrix missed a lib.ps1 import -- fixed
and re-ran 4/4 PASS (the next full battery will print ALL GATES GREEN).
Shared stdlib 750384f: probe/libcheck/suite x2 green. WSL suite 177/177 x2
+ targeted UI/concurrency/SQ/kernel probes green; the full WSL 57-probe
sweep is queued (VM 0-min-uptime restarts).

LANDED: v0.64.8 re-pin; C-19/C-20 verified fixed; G-2b XVECTORD_THREADS;
station UI `/ui` + `/collections/{n}/sample`; Q-a2b sealed SQ; P3 kernel
seam; hard 8 GB resource guard (Job Object/kill-on-close; WSL `ulimit -v`);
pulse 0.3.1; shared-stdlib unblock.

BLOCKED/OPEN: **P4 IVF/PQ BLOCKED on XVC-C-22** -- the deterministic PQ
trainer + IVF-PQ prototype exposed: a second `pq_train` call crashes
`0xC0000005`; one `ivf_pq_build` returns a corrupted nested codebook
(checksum 370608086 -> 534399819, recon 0.84 -> 4.48e28; exact rescore
<1.0). Repro `docs/repro/xv-pq-second-call/`; prototype reverted; bus
`REL-20261021-1103-xvector` (high); reopens on a compiler fix.
**XVC-C-21 OPEN** (v0.64.8 compiler build hangs under a PROCESS/JOB
memory-limit Job Object; compiler builds use kill-on-close-only + watchdog;
bus `REL-20261020-1531-xvector-2`). No other compiler findings open.

FINDINGS/WISHLISTS (bus): C-21 `REL-20261020-1531-xvector-2`; C-22
`REL-20261021-1103-xvector`; stdlib `ee1a95c` break
`REL-20261020-1531-xvector` (acked; fixed at `750384f`); **Float32
BLAS/eigen kernel binding wish** `REL-20261021-1121-xvector` (P3 seam ready;
OpenBLAS 0.1.1 is Float64/native); **host WSL VM instability**
`REL-20261021-1121-xvector-2` (short gates + logs on `out/wsl-battery.log`).
P3's unrolled kind is bit-identical but not faster (the compiler vectorizes
the scalar loop; scalar default) -- documented in BENCHMARKS.

Do this, in order:
1) Relay bus FIRST: git -C E:\xiom-lang\xiom-relays fetch origin main;
   merge --ff-only; python tools/relay.py view --lane xvector. Check
   C-21/C-22 answers, stdlib/pulse/trees, asks.
2) WSL gates when the VM is stable: suite x2 + libcheck 48/48 +
   probe_ui/probe_concurrency/probe_sq_sealed/probe_kernels (full 57-probe
   if uninterrupted; log to `out/wsl-battery.log`; short gates during
   restarts; shared `750384f`; bundled fallback).
3) **L-6 phase B** (next station feature): range-vs-hash decision; router
   fan-out + k-way ranked merge (distance asc, id asc); offset/after_id
   after the merge; strict default / partial opt-in; `probe_scatter_gather`
   with named recall definitions; gates x2 + bench note.
4) G-3 read snapshots / G-4 metrics-under-concurrency; scale tuning.
5) P5 mmap/disk (stdlib-dependent); **P4 reopens on XVC-C-22** (PQ design
   and repro at `docs/repro/xv-pq-second-call/`; deterministic training +
   reconstruction-error budget; no lossy-only path).
6) Optional station-UI editor + three.js/WebGL upgrade (`docs/UI.md`).
7) Release notes current through P3/safety + the P4 blocked note; owner
   review before the rc.1 GitHub release (owner-gated, repo private);
   `xiom.ann` swap owner-gated.

Standing owner items: rc.1 GitHub release greenlight; ann-swap greenlight.
Discipline: struct literals list every field; locals initialized; Str by
value (XVC-C-13); json.json_* qualified; bodies as BYTES; copy nested
map/vec data into locals before iterating (XVC-C-18); C-19 fixed, C-20
fixed; src/ modules import `xiom.vector.primitives`, NEVER `xiom.vectors`
(run `scripts/libcheck.ps1` / `.sh` before a carve/wrap; the import guard is
authoritative -- negative-test it if edited); the SBOM gate scans the
literal token "unsafe" in comments too; suite x2 + WSL spot before any
wrap; one verified slice at a time; signed commits; keep edits scoped (a
backstop session may share the tree); check free memory before trusting
reds; bench loops hard-capped; **cap every app/probe run at 8 GB
(`lib.ps1`/`run-capped`; WSL `ulimit -v`) and never launch the app bare;
compiler builds are watchdog + kill-on-close only (XVC-C-21)**; toolchain/
package homes are lane-local on purpose.
```

## 21. PASTE PROMPT for the next XVECTOR session (refresh 2026-10-21 16:0xZ; supersedes 20)

```text
XIOM XVECTOR -- fresh-context continuation prompt (L-6 phase B landed).

REPO/STATE
- E:\xiom-projects\xiom-xvector; branch main; L-6 code `383c2d1` (phase B
  + negative-DotProduct cursor fix, parent `902be21`) with the docs/SESSION
  wrap commits on top; clean tree; tag v1.0.0-rc.1 = `530b041`. The
  isolated worktree used for the slice
  (C:\Users\lefte\AppData\Local\Temp\kilo\xvector-l6, branch
  feat/l6-scatter-gather) was fast-forward merged and removed after the wrap.
- Compiler v0.64.8 both (win `c31d9c46`, linux `a8c003c0`); shared stdlib
  `750384f` (release tag `0bf5b75`); packages `b133b1a7`. Lane-local homes.
- WSL: always `wsl -d Ubuntu`; VM restarts are environment noise; logs
  persist on /mnt/e.

LANDED (2026-10-21, 88th pass): L-6 PHASE B HASH SCATTER-GATHER
- `src/api/sharding.xi`: `shard_slot(id, n) = id mod n` (normalized for
  negatives), shared by the router and every shard.
- Mapping `"split": {collection: [shard...]}`: 2+ unique known parts in SLOT
  ORDER; first part = declared owner; strict loader/persist/view; round-trip.
- Create fan-out; batch upsert fan-out with `x-xvector-part-slot/count`
  headers (last-match wins: client hints cannot shadow router placement);
  point get/delete route by hash.
- Search: fan-out with oversample (`x-xvector-fanout-mult`,
  `x-xvector-ignore-offset`), k-way `(distance asc, id asc)` merge + dedupe,
  offset applied after merge; merged `after_id` resolves the cursor distance
  on its owner part and sends the exact Float32 bit pattern
  (`x-xvector-after-distance`); every part uses `engine_search_after_key`
  (active + sealed, tombstone-safe, exact). Presence is the explicit
  `after_distance_set` flag, so negative DotProduct cursor keys work.
- Strict default (503 + per-shard report); `"partial": true` -> live hits +
  `partial` (+ `failed_shards`); fully-live partial -> `partial:false`.
- Wire filter pushdown: `eq/range/exists/in/and/or/not`; malformed -> 400.
- Split stats sum parts (`split:true`, `parts`); `/cluster/stats` dedupes
  split collection names. `router_cluster_stats` total_collections is now
  unique-name based (existing semantics preserved for non-split).
- Explicit v1 limits: split batch/range search 501; split move 409; any
  drain touching a split part 501; split stats with a down part 503; part
  count fixed (reshard = rebuild); split mapping edits need reload/restart.

EVIDENCE
- Windows: `probe_scatter_gather` (51st; 58 total) 0 fails x2; suite
  177/177 x2; libcheck 49/49; affected probes green: router_2shards,
  move_under_load, pagination, search_request, http_service, http_fuzz,
  metrics, service_auth, service_limits.
- Flat exactness vs single-node oracle; offset reconstruction; 2/3 tie
  cursor; chained after-id ranks 0..27 exact; negative DotProduct cursor
  advances exactly (explicit presence flag).
- HNSW (120 points, dim 12, 3 parts, m=8/ef_construction=64/ef_search=8):
  ID-set/distance-threshold recall 0.9917/0.9917 at oversample 1;
  1.000/1.000 at 2 and 3. Filtered HNSW 1.000 at 1/2/3. Gate floors
  0.80/0.80 and 0.75 filtered. See BENCHMARKS.
- WSL baseline (pre-L-6) FULL BATTERY: ALL GATES GREEN -- suite 177/177 x2,
  libcheck 48/48, SBOM 48/0, 57 probes x2, bench smoke, kill matrix
  (`out/wsl-battery.log`, WSL_CI_EXIT:0).
- WSL L-6 suite 177/177 x2 + libcheck 49/49 + SBOM 49/0 green.
- **WSL L-6 full 58-probe battery: ALL GATES GREEN** -- 58 probes x2,
  bench smoke, kill matrix; `WSL_L6_CI_EXIT:0` (`out/wsl-battery-l6.log`).
- **Windows full 58-probe battery: ALL GATES GREEN** -- suite 177/177 x2,
  libcheck 49/49, SBOM 49/0, 58 probes x2, bench smoke, kill matrix
  (`out/win-battery-l6.log`).

BLOCKED/OPEN
- P4 IVF/PQ still BLOCKED on XVC-C-22 (second `pq_train` 0xC0000005 +
  corrupted nested codebook; repro `docs/repro/xv-pq-second-call/`; bus
  `REL-20261021-1103-xvector`). A backstop session was observed generating
  variant probes; they were cleaned up; no bus answer. P4 reopens on the
  compiler fix.
- XVC-C-21 open (v0.64.8 compiler build hang under a PROCESS/JOB memory
  limit; kill-on-close only + watchdog); bus
  `REL-20261020-1531-xvector-2`. No other compiler findings open.
- New finding/workaround: a header-sized JSON numeric read came back 0
  (likely the XVC-C-18 family). The after-distance header now carries the
  exact Float32 bit pattern, so L-6 is unaffected; filed as info
  `REL-20261021-1243-xvector` (compiler) asking whether it is C-18; isolate
  a repro before claiming a new C-id.
- P5 mmap/disk is stdlib-dependent.

NEXT (ordered)
1) Remove the temp worktree/branch; both full 58-probe batteries are green
   and the checklist/readiness/SESSION are updated.
2) G-3 read snapshots; G-4 metrics-under-concurrency; scale tuning.
3) P5 when stdlib unblocks; P4 on XVC-C-22.
4) Split resharding/rebalance (fixed part count is the v1 limit); optional
   UI editor/three.js upgrade (`docs/UI.md`).
5) Release notes through L-6; owner gates (rc.1 release, ann swap).

DO FIRST
1) Relay bus: `git -C E:\xiom-lang\xiom-relays fetch origin main`;
   `merge --ff-only`; `python tools/relay.py view --lane xvector`. Check
   C-21/C-22 answers, stdlib/pulse/trees, asks.
2) `git status`/`git log`; verify HEAD `383c2d1` + this wrap commit; check
   free memory; one battery at a time.
3) Re-run `probe_scatter_gather` x2 + suite x2 + libcheck before editing.

STANDING OWNER ITEMS: rc.1 GitHub release greenlight; ann-swap greenlight.

DISCIPLINE: struct literals list every field; locals initialized; Str by
value (XVC-C-13); json.json_* qualified; bodies as BYTES; copy nested
map/vec data into locals before iterating (XVC-C-18); C-19 fixed, C-20
fixed; src/ modules import `xiom.vector.primitives`, NEVER `xiom.vectors`
(run `scripts/libcheck.ps1` / `.sh` before a carve/wrap; the import guard is
authoritative -- negative-test it if edited); the SBOM gate scans the
literal token "unsafe" in comments too; suite x2 + WSL spot before any
wrap; one verified slice at a time; signed commits; keep edits scoped (a
backstop session may share the tree); check free memory before trusting
reds; bench loops hard-capped; **cap every app/probe run at 8 GB
(`lib.ps1`/`run-capped`; WSL `ulimit -v`) and never launch the app bare;
compiler builds are watchdog + kill-on-close only (XVC-C-21)**; toolchain/
package homes are lane-local on purpose.
```

## 22. PASTE PROMPT for the next XVECTOR session (refresh 2026-10-22 16:30Z; supersedes 21)

```text
XIOM XVECTOR -- fresh-context continuation (v0.64.9 verification; compiler + stdlib HELD).

STATE
- E:\xiom-projects\xiom-xvector; branch main; L-6 code `383c2d1` + docs and
  release-evidence wraps on top; clean tree; tag v1.0.0-rc.1 = `530b041`.
- Compiler pin stays **v0.64.8** both platforms (win `c31d9c46`, linux
  `a8c003c0`); **lane stdlib pin `out/stdlib-pin` = `750384f`** (dev-env
  prefers it; the shared `E:\xiom-lang\stdlib` checkout is live and moved
  to `06b0f4b`); packages `b133b1a7`. Do NOT bump `out\toolchain` /
  `~/.xvector-toolchain` or the stdlib pin until both v0.64.9 holds clear.
  Recreate the pin: `git -C E:\xiom-lang\stdlib archive --format=tar -o
  out\stdlib-pin.tar 750384f`, `mkdir out\stdlib-pin`, `tar -xf ...`.
- v0.64.9 test archives were used side-by-side only:
  Windows zip sha256 `1b759541...`, Linux x64 `b331dd4d...` (both match
  the release digests); extracted under temp/`/tmp`, never the lane pin.
- WSL: `wsl -d Ubuntu`; restarts are environment noise, logs persist.

v0.64.9 RELEASED BUT HELD
- compiler tag `v0.64.9` (`ffde5aa0...`) on `2bcf58db5`; release run
  39791522014; stdlib tag `stdlib-v0.64.9` at `aa8b656`; `xiom-std 0.64.9`
  live. Announcement `REL-20261022-1406-compiler`.
- HOLD `REL-20261022-1501-orbitdb`: official archives fail the 1451/1550
  release-mode fixes (stdlib items `REL-20261022-1410-stdlib` and
  `-1414-stdlib`). Stay on v0.64.8; do not treat the release as adoptable.
- **stdlib-v0.64.9 `aa8b656` is ALSO HELD for xvector**: HTTP/L-6 probes
  crash `0xC0000005` on **both** v0.64.8 and v0.64.9 with that stdlib;
  `probe_hello`, `probe_vector_store`, and `probe_pagination` pass, while
  `probe_http_service`, `probe_router_2shards`, and `probe_scatter_gather`
  crash. Filed `REL-20261022-1640-xvector` + narrowed update
  `REL-20261022-1702-xvector`; the lane is pinned to `750384f`, where the
  scatter gate is 0 failed checks x2.
- xvector rows, completed on the side-by-side archive with the pinned
  stdlib `750384f`:
  - **XVC-C-22 GREEN Windows + Linux** (`docs/repro/xv-pq-second-call/probe.xi`
    prints built 2000 / first ok m=8 / second ok m=8, exit 0; pinned
    stdlib 750384f). Bus `REL-20261021-1103-xvector` verified + committed
    (`926503e`). The nested P4 codebook arm still re-runs when P4 reopens.
  - **1531 GREEN x2** on Windows: `tests/test_conformance.xi` built under a
    real 16 GB PROCESS+JOB memory cap (`Invoke-XvectorProcess -MaxMemoryMB
    16384`), exit 0, no hang, exe produced; pinned stdlib 750384f. Info
    `REL-20261022-1616-xvector`.
  - **1243 reproduced**: `docs/repro/xv-json-read-min/probe.xi` shows
    `json_stringify` correct but `match JsonValue.Number(n)` / `json_get`
    reads 0 on v0.64.8 and v0.64.9, shared and bundled stdlib. This is the
    release-mode payload-read family, not JSON-specific; filed high as
    `REL-20261022-1615-xvector`. The L-6 exact-f32-bits workaround stays.
  - Release-check xvector row updated; `REL-20261022-1617-xvector` records
    that the scoped commit also carried the compiler's uncommitted hard-gate/
    stdlib/tag-log sections in the shared clone.
- P4: the compiler fix is verified (with the pinned stdlib), but the
  archive/pin is held and stdlib 0.64.9 is independently broken for the
  HTTP path; P4 code reopens only after both holds clear. The nested-codebook
  arm still needs a re-run then.

WSL BUILD BUDGET
- A cold pinned-stdlib scatter build is ~4m25 (commit-heavy monomorph);
  the 240 s `run-probe.sh` build watchdog kills it. Run targeted WSL gates
  with `XVECTOR_BUILD_TIMEOUT=600` (now honored). The lane also prefers
  `~/.xvector-stdlib-pin` (ext4) over `out/stdlib-pin`; both are 750384f.
- The prior full WSL 58-probe battery was green on the shared 750384f tree;
  the pin is content-identical but cold/slow. Use Windows for the full
  battery and WSL for targeted spots unless the cache is warmed.

NEW REPROS
- `docs/repro/xv-json-header-read/probe.xi` (HttpRequest -> http_header ->
  json_parse -> json_get shape).
- `docs/repro/xv-json-read-min/probe.xi` (minimal enum payload read; two
  arms: top-level number and one-key object; prints match_n=0).

NEXT (ordered)
1) Watch BOTH lanes: compiler release-mode fix / re-cut, and stdlib
   aa8b656 HTTP/L-6 crash. On a fixed pair re-run 1451/1550 + 1243 +
   HTTP/L-6, then bump both pins and run the full batteries. Do not adopt
   either held artifact.
2) In parallel on v0.64.8: **G-4 metrics-under-concurrency** first; G-3
   is design-gated on runtime Send/Sync + a snapshot handle + mutex-bottleneck
   data (G-PHASE-PLAN section 3), so evaluate it after G-4. Then scale tuning.
3) P5 when stdlib unblocks; P4 when the archive is fixed; split
   resharding/rebalance; optional UI editor/three.js.
4) Release notes/owner gates.

DO FIRST
1) Relay bus: fetch/merge, `view --lane xvector`; check 1406/1410/1414/
   1501/1615/1616/1617 and compiler answers.
2) Verify the lane compiler is v0.64.8 and `out/stdlib-pin` is 750384f;
   do not adopt stdlib 0.64.9 (HTTP/L-6 crash).
3) Re-run `probe_scatter_gather` x2 + suite x2 + libcheck before editing.

STANDING OWNER ITEMS: rc.1 GitHub release greenlight; ann-swap greenlight.

DISCIPLINE: struct literals list every field; locals initialized; Str by
value (XVC-C-13); json.json_* qualified; bodies as BYTES; copy nested
map/vec data into locals before iterating (XVC-C-18); C-19/C-20 fixed;
src/ modules import `xiom.vector.primitives`, NEVER `xiom.vectors`; run
`scripts/libcheck.ps1` / `.sh` before a carve/wrap; the SBOM gate scans the
literal token "unsafe" in comments too; suite x2 + WSL spot before any
wrap; one verified slice at a time; signed commits; keep edits scoped (a
backstop session may share the tree); check free memory before trusting
reds; bench loops hard-capped; **cap every app/probe run at 8 GB
(`lib.ps1`/`run-capped`; WSL `ulimit -v`) and never launch the app bare;
compiler builds are watchdog + kill-on-close only (XVC-C-21), except the
explicit 16 GB 1531 test**; toolchain/package homes are lane-local on
purpose.
```

## 23. PASTE PROMPT for the next XVECTOR session (refresh 2026-10-23 18:25Z; supersedes 22)

```text
XIOM XVECTOR -- fresh-context continuation (v0.64.9 withdrawn; v0.65.0 gate; stable v0.64.8 + stdlib 750384f).

STATE
- E:\xiom-projects\xiom-xvector; branch main; HEAD `b4f3d07` + this session
  wrap commit; clean tree; 34 commits ahead before this wrap (35 after);
  tag v1.0.0-rc.1 = `530b041`.
- Compiler **v0.64.8** both platforms (lane toolchain; win `c31d9c46`,
  linux `a8c003c0`); stdlib **pin `750384f`** (`out/stdlib-pin` on Windows,
  `~/.xvector-stdlib-pin` on WSL; `scripts/dev-env.*` prefer them); packages
  `b133b1a7`. Do NOT repin to v0.64.9/stdlib-v0.64.9.
- WSL: always `wsl -d Ubuntu`; VM restarts are environment noise. A cold
  pinned-stdlib scatter build is ~4m25, so targeted WSL gates use
  `XVECTOR_BUILD_TIMEOUT=600` (honored by `run-probe.sh`); the 240s default
  is too short for a cold pin. Prefer Windows for the full 58-probe battery.

RELEASE STATUS (2026-10-22/23)
- **v0.64.9 WITHDRAWN FROM ADOPTION** (2026-10-22T18:30Z,
  `REL-20261022-1826-compiler`); GitHub release is pre-release; assets/tag
  remain for audit only. Production remains v0.64.8. Do not pin/deploy.
- **v0.65.0 production gate opened**: P0 correctness (nested enum patterns,
  safe type-arg substitution, release-compiler parity, m1511 transitive
  port.args, C07) -> P1 hardening (debug+release batteries, negative/ASAN,
  reproducibility) -> P2 MCU first wave (thumbv6m/v7em/v8m.main,
  riscv32imc/imac, freestanding, QEMU) -> P3 cut. Gate:
  `docs/RELEASE_GATE_v0.65.0.md`; checklist `docs/checklists/v0.65.0.md`.
  No candidate/tag before the gate is green + owner GO.
- **stdlib-v0.64.9 `aa8b656` is not production**; the hotfix **0.64.10**
  is pending. v0.65.0 will pin stdlib-v0.65.0.
- Host incident (`REL-20261022-1622-engine`): accidental recursive delete in
  C:\Users\lefte removed `.cargo`; Rust works from
  `C:\Users\lefte\.rustup\toolchains\stable-x86_64-pc-windows-msvc\bin`
  (restore shims). The Windows package store was empty today
  (`REL-20261022-2058-pulse`); our package home is lane-local and intact.

OUR 89TH-PASS FINDINGS, NOW TRIAGED
- **1615 / 1243** (enum payload read 0, JSON minimal probe): **FIXED on
  compiler main** `ecd22a225` + `45804b195`; e2e `m1615_nested_enum_payloads`
  green debug+release, full e2e 2646/2646. Item `1615` is `fixed`; the
  reporter verification waits for the v0.65.0 archive. Repro:
  `docs/repro/xv-json-read-min/probe.xi`.
- **1640 / 1702** (stdlib HTTP/L-6 crash): root cause `72b2b4c` made JSON
  number rendering call `builder.sb_push_int`, whose `[20]UInt8` stack buffer
  miscompiles on v0.64.8 in the HTTP service chain. **Fixed on stdlib main
  `f436a5d`** (allocation-free digit loop); `probe_http_service`,
  `probe_router_2shards`, `probe_scatter_gather` all 0 fails on v0.64.8 +
  fixed main. **Hotfix tag 0.64.10 pending**; keep the 750384f pin until it
  is tagged. Items `1640` fixed, `1702` acked.
- **XVC-C-22** (P4 second `pq_train` AV): **fixed/verified** on the withdrawn
  v0.64.9 Windows+Linux archive with the pin; bus item
  `REL-20261021-1103-xvector` verified. The nested P4 codebook arm still
  re-runs when P4 reopens on v0.65.0.
- **1531** (16 GB PROCESS/JOB build): green x2 on v0.64.9 + pin; item
  `REL-20261022-1616-xvector`.
- **1617**: release-check row commit captured the compiler lane's
  uncommitted hard-gate/tag-log sections; recorded for audit.

STABLE-PIN EVIDENCE
- Windows: suite 177/177 x2; libcheck 49/49; `probe_scatter_gather` 0
  failed checks x2; full 58-probe battery prior green on the same
  code/stdlib content (`out/win-battery-l6.log`).
- WSL: targeted `probe_scatter_gather` 0 failed checks with
  `XVECTOR_BUILD_TIMEOUT=600`; the prior full 58-probe battery was green on
  the shared 750384f tree (`out/wsl-battery-l6.log`).
- L-6 phase B code `383c2d1` (mapping split, hash scatter-gather, merged
  after-id incl. negative DotProduct, filter pushdown) + docs wraps; full
  evidence in Â§21/Â§22.

NEXT (ordered)
1) Wait for the **v0.65.0 archive** and **stdlib hotfix 0.64.10**. Then
   re-pin both, re-run 1615/1243 + 1640/1702 + C-22/1531 + L-6, and the full
   batteries on both platforms. 1615/1640 are acceptance input.
2) On stable v0.64.8: **G-4 metrics-under-concurrency** (next implementable
   slice); G-3 read snapshots is design-gated on runtime Send/Sync + a
   snapshot handle + mutex-bottleneck data (G-PHASE-PLAN section 3/6);
   evaluate G-3 after G-4. Then scale tuning.
3) P4 when v0.65.0 + hotfix are adopted (nested codebook arm); P5
   stdlib-dependent; split resharding/rebalance; optional UI editor/three.js.
4) Release notes/owner gates.

DO FIRST
1) Bus: `git -C E:\xiom-lang\xiom-relays fetch origin main`, `merge
   --ff-only`, `python tools/relay.py view --lane xvector`; check 1826
   (withdrawal/gate), 1615, 1640, 1702, 1945 (bindings restored), 2058
   (host package store).
2) Verify the lane compiler is v0.64.8 and the stdlib pin is 750384f; do not
   adopt v0.64.9 or stdlib-v0.64.9.
3) Re-run suite x2 + libcheck + `probe_scatter_gather` x2 before editing;
   WSL targeted with `XVECTOR_BUILD_TIMEOUT=600`.

STANDING OWNER ITEMS: rc.1 GitHub release greenlight; ann-swap greenlight.

DISCIPLINE: struct literals list every field; locals initialized; Str by
value (XVC-C-13); json.json_* qualified; bodies as BYTES; copy nested
map/vec data into locals before iterating (XVC-C-18); C-19/C-20 fixed;
src/ modules import `xiom.vector.primitives`, NEVER `xiom.vectors`; run
`scripts/libcheck.ps1` / `.sh` before a carve/wrap; the SBOM gate scans the
literal token "unsafe" in comments too; suite x2 + WSL spot before any
wrap; one verified slice at a time; signed commits; keep edits scoped (a
backstop session may share the tree); check free memory before trusting
reds; bench loops hard-capped; **cap every app/probe run at 8 GB
(`lib.ps1`/`run-capped`; WSL `ulimit -v`) and never launch the app bare;
compiler builds are watchdog + kill-on-close only (XVC-C-21), except the
explicit 16 GB 1531 test**; toolchain/package homes are lane-local.
```
