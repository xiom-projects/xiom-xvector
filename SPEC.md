<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# xiom-vector -- SPEC

Module-by-module reference for the layered vector engine. For the design
rationale see [`ARCHITECTURE.md`](ARCHITECTURE.md); for status see
[`ROADMAP.md`](ROADMAP.md).

## Layout

```
packages/xiom-vector/
|-- package.xi                  Manifest (deps: xiom-std, xiom.math, xiom-core)
|-- README.md - ARCHITECTURE.md - ROADMAP.md - COLLECTIONS.md - SPEC.md
|-- docs/                       Deep-dive design docs
`-- src/
    |-- core/shim.xi
    |-- error.xi - ids.xi - engine.xi - engine/core.xi
    |-- types/{dense_vector,metric,neighbor,dimension}.xi
    |-- collection/{schema,collection,validator}.xi
    |-- payload/{payload,filter_ast,filter_eval}.xi
    |-- storage/{vector_store,id_map}.xi
    |-- segment/{segment_state,segment,manifest,segment_file}.xi
    |-- index/{ann_index,flat_index,hnsw}.xi
    |-- distance/{cosine,dot,l2}.xi
    |-- query/{search_request,filter_plan,topk_heap,search_service,pagination}.xi
    |-- durability/{wal,recovery,write_ahead_events,wal_file,manifest_file}.xi
    `-- api/vector_api.xi
```

---

## `xiom.vector.types.dense_vector` (extracted module)
Implemented today: `Vector`, `new/set/get`, `vector_dot`, `vector_magnitude` (normalize/add/sub/scale pending).
`Vector { data: Vec[Float32]; dimension: UInt }` -- the fundamental value type.
- `Vector.new(dimension)` `requires: dimension > 0` `ensures: result.data.len() == dimension`
- `Vector.set(index, value)` / `Vector.get(index)` `requires: index < dimension`
- `vector_dot`, `vector_magnitude`, `vector_normalize`, `vector_add`, `vector_sub`, `vector_scale`, `vector_dimension`
- Binary ops `requires: a.dimension == b.dimension`.

## `xiom.vector.types.metric` (extracted module)
Implemented today: `DistanceMetric` + the three distances + `vector_distance` (metric_name pending).
`enum DistanceMetric { Cosine, DotProduct, Euclidean }`.
- `dot_product_distance` -> `-Sigma(aibi)`; `cosine_distance` -> `1 - costheta` (zero vectors -> 1.0); `euclidean_distance` -> `sqrtSigma(ai-bi)2`.
- `vector_distance(a, b, metric)` dispatches (`requires: a.dimension == b.dimension`).
- `metric_code(m) -> Int` / `metric_from_code(c)` -- stable on-disk codes
  (1 = Cosine, 2 = DotProduct, 3 = Euclidean), shared by the WAL collection
  manifest and the manifest file (D2). `Str` parameters are always by value
  (`&Str` mislowers on v0.64.2 -- XVC-C-13).
- `metric_name(m) -> Str`.
- Reference oracle (M-G1, `tests/probes/probe_reference_oracle.xi`): an
  INDEPENDENT Float64 oracle (its own loops over the raw Float32 storage,
  `math.sqrt` in Float64, no `vector_distance` calls) cross-checks all
  three kernels pairwise (780 seeded pairs each; per-build deviation
  reports -- cosine ~1.7e-7, dot ~9.8e-7, euclidean ~5.1e-7 on v0.64.2,
  bit-identical Windows/WSL), the metric axioms (exact symmetry,
  self-distance `l2==0` / `cosine~0` / `dot==-|v|^2`, euclidean triangle
  inequality, cosine bounds `[0,2]` + exact x2 scale invariance,
  zero-vector guard `== 1.0`), and the ranked/paged/cursor/range/Hnsw
  search paths vs the oracle ranking on deterministic seeded vectors
  (top-5 rank exact per metric, inclusive-range subset at a midpoint
  radius, engine-distance boundary inclusion, Hnsw recall@5 == 5/5 +
  oracle distance fidelity).

## `xiom.vector.types.neighbor` (extracted module)
Implemented today: `Neighbor` + `neighbor_new` (neighbor_closer pending).
`Neighbor { id: UInt64; distance: Float32 }` -- low-level result edge used inside indexes/graph adjacency. `neighbor_new`, `neighbor_closer`.

## `xiom.vector.types.dimension`
`Dimension { value: Int }` wrapper. `dimension(v)`, `dimension_value`, `dimension_eq`, `dimension_is_valid` (delegates to `core.contracts.is_valid_dimension`), `dimension_within_limit` (uses `core.limits.max_dimensions`).

## `xiom.vector.error`
`enum VectorError { DimensionMismatch(expected, got), UnsupportedMetric(name), CollectionNotFound(id), InvalidVector(msg), SegmentSealed(id), TopKExceeded(requested, max) }`.
- `vector_error_to_str`, `vector_error_to_core` (-> `CoreError`), `vector_error_code` (stable numeric codes).

## `xiom.vector.ids`
Reuses `CollectionId`/`VectorId`/`SegmentId` from `xiom.core.ids`. Adds `PointId { value: Int }` (user id) with `point_id`, `point_id_value`, `point_id_eq`, and `point_to_vector_id` / `vector_to_point_id` bridges.

## `xiom.vector.storage.vector_store` (extracted module)
Implemented today: `VectorIndex` + `index_new/add/remove/get/size` + the vector WAL codec.
`VectorIndex { vectors: Vec[Vector]; ids: Vec[Int]; id_keys: Vec[Int]; id_vals: Vec[Int]; dim: Int }` -- flat columnar store plus a sorted id -> slot map (parallel vectors, binary search; no Vec-of-struct shapes).
- `index_new(dim)` `requires: dim > 0`
- `index_add(idx, id, vec)` `requires: idx.dim == vec.dimension` -- insert, or **update in place** when the id exists (upsert semantics; true when the store holds the id afterwards). Earlier revisions rejected duplicates and kept the old vector, diverging from the HNSW graph; fixed 2026-10-08.
- `index_remove` (swap-with-last; the moved element's map slot is updated), `index_get -> Option[Vector]`, `index_add`/`index_get`/`index_remove` are O(log n) via the map, `index_size`.

## Durable vector codec (WAL payload)
- `vector_encode(v) -> Vec[Int]` -- layout `[dim, Float64-bits0, ...]` (exact:
  every Float32 is exactly representable in Float64; `xiom.num.float.float_bits`
  lowers to a true bitcast since v0.64.0/m194).
- `vector_decode(payload) -> Option[Vector]` -- `None` on any malformed shape
  (short buffer, invalid dim, length mismatch) so recovery can skip torn
  records.

## `xiom.vector.storage.id_map`
`IdMap` of `IdMapEntry { vector_id; segment; offset }`. `id_map_new/put/lookup/remove/len`. Maps logical id -> physical location for compaction stability.

## `xiom.vector.index.ann_index`
`enum AnnIndexKind { Flat, Hnsw, Ivf }`; `AnnParams { m; ef_construction; ef_search }`. `ann_params_default` (`m=16, efC=200, efS=64`), `ann_params_valid` (bounds `m` by `core.limits.max_graph_degree`), `ann_index_kind_name`, and the stable on-disk codes `ann_kind_code(k) -> Int` / `ann_kind_from_code(c)` (1 = Flat, 2 = Hnsw, 3 = Ivf).

## `xiom.vector.index.flat_index`
`FlatIndex { store: VectorIndex }` -- exact brute-force baseline / correctness oracle. `flat_index_new/add/remove/size`; `flat_index_search(idx, query, k, metric)` `ensures: result.len() <= k` (delegates to `search_service.search_knn`).

## `xiom.vector.index.hnsw` (working multi-layer graph)
Flat parallel arrays (no nested `Vec[Struct-with-Vec]` -- the AUDIT T001
family): `HNSWGraph { ids; vectors; levels; adj; deg; m; ml; entry }` with a
fixed 8-layer capacity per node; `row(pos, layer) = pos*8 + layer` indexes
`deg`, adjacency blocks are `row*m` row-major (live slots `0..deg[row]`).
- `hnsw_new(m, ml)` `requires: m > 0, ml > 0.0`; `hnsw_set_ef_construction(graph, ef)` sets the build beam (default 200; values < 1 ignored).
- `hnsw_insert(graph, id, vec, metric)` -- deterministic geometric level assignment (`ml`), greedy descent, per-layer beam construction honouring `ef_construction` (clamped to >= `m`) with diversified neighbour selection, bidirectional edges; the entry tracks the highest-level node. Re-inserting an existing id updates the vector in place, revives a tombstone, and refreshes the node's edges for the new vector (per-layer re-link).
- `hnsw_search(graph, query, k, ef, metric)` `requires: k > 0` `ensures: result.len() <= k` -- greedy descent above layer 0, then a best-first beam (breadth = `max(k, ef)`); `Vec[Neighbor]` with user ids; empty graph / dimension mismatch -> empty.
- `hnsw_search_visited` (visited-node count, latency proxy), `hnsw_build_ops` (construction distance-op counter; metric only -- not persisted by the codec), `hnsw_size`, `hnsw_level_of`, `hnsw_layer_capacity`, `hnsw_find_node_pos` (O(log n) over the sorted `id_keys`/`id_vals` map; duplicates rejected on insert).
- `hnsw_insert_ref(graph, id, vec_ref, metric)` -- copy-insert for callers that must keep their vector (one engine upsert feeds store + graph).
- `hnsw_compact(graph, metric) -> HNSWGraph` -- fresh graph from the live nodes only (same `m`/`ml`, insertion order preserved): tombstone compaction + edge rebuild; engine wrapper `compact_index`.
- `hnsw_encode(graph) -> Vec[Int]` / `hnsw_decode(words) -> Option[HNSWGraph]` -- deterministic persistence codec: `[version=2, m, ml_bits, ef_construction, layer_capacity, entry, node_count, per node: id, level, deleted, vector words..., per layer row: degree + neighbor positions]` (vectors via `storage.vector_store.vector_encode`). Decode is strict: malformed/truncated/tampered input returns `None`, `m > 512` (AnnParams max degree) or `count > words.len()` is rejected, duplicate ids are rejected (the id map is unique), and the map is rebuilt on decode; trailing junk rejected. The pad step runs behind `pad_adj_slots` (XVC-C-10 workaround: the inline loop segfaulted at larger `m`).
- `hnsw_delete(graph, id) -> Bool` -- tombstone: the node keeps routing traffic but is never returned (idempotent; false for unknown/already-deleted). `hnsw_live_count` reports non-deleted nodes. Re-inserting an id updates the vector in place, revives the node, and refreshes its edges for the new vector (re-linking landed 2026-10-09).
- Recall harness (`tests/probes/probe_hnsw_recall.xi`): n=200 recall@10 300/300 (ef=64) and 296/300 (ef=8), cosine 100/100, top level 4; n=800 200/200 at ef=64 (avg visited 299/800); after deleting id 42 recall 300/300 with stray42=0, revive restores live 200, delete-all -> empty; beam construction honours ef_construction (setter semantics checked).

## `xiom.vector.distance.{cosine,dot,l2}`
Kernel seam (SIMD drop-in point, Phase 10). `cosine_kernel`/`cosine_similarity`, `dot_distance`/`dot_raw`, `l2_distance`/`l2_squared`. Delegate to `types.metric` today.

## `xiom.vector.query.search_request` (rewritten against real types)
`SearchRequest { query: Vector; top_k: Int; metric: DistanceMetric; filter: Vec[FilterExpr]; with_payload: Bool; mode: SearchMode; radius: Float32; offset: Int; after_id: Int }` -- the wire shape for request-driven search (the pre-extraction file carried inline mirrors; now it imports the extracted types). `SearchMode { Knn, Range }` (M-Q6).
- `search_request_new(query, top_k, metric)` `requires: top_k > 0`; defaults: `with_payload=false`, `mode=Knn`, `radius=0.0`, `offset=0`, `after_id=-1` (plain-knn behavior -- existing consumers unchanged).
- `search_request_set_filter(req, expr)` -- single-clause replace (`[]` = no filter); `search_request_has_filter`, `search_request_top_k`.
- `search_request_set_with_payload(req, on)` -- toggle hydration.
- M-Q6 setters: `search_request_set_mode(req, mode)`; `search_request_set_range(req, radius)` (sugar: mode=Range + radius; `top_k` acts as the inclusive-radius limit); `search_request_set_page(req, offset)` (knn offset ranks); `search_request_set_after(req, after_id)` (knn cursor; -1 = none).
- `SearchBatchRequest { requests: Vec[SearchRequest] }` + `search_batch_request_new/add/len` -- an ordered batch of requests.

## `xiom.vector.query.topk_heap`
`TopKHeap { capacity; items: Vec[Neighbor] }`. `topk_new(capacity)` `requires: capacity > 0` `ensures: items.len() == 0`; `topk_push` `ensures: items.len() <= capacity`; `topk_len`, `topk_is_full`, `topk_worst`.

## `xiom.vector.query.filter_plan` (planner)
Selectivity-based plan choice for filtered search.
- `filter_matching_count(payloads, expr) -> Int` -- exact matching-point count
  from the sorted payload index for Eq/Range/Exists; `-1` for unknown shapes
  (In, And/Or/Not).
- `filter_matching_upper(payloads, expr, total) -> Int` -- upper bound for
  compound shapes: And = min of the known child bounds (intersection is
  contained in every child), Or = sum when every child bound is known (clamped
  to total), Not = `total - exact` when the child is a single predicate,
  otherwise `-1`.
- `filter_plan_candidates(payloads, expr) -> Vec[Int]` -- exact candidate ids
  for Eq/Range/Exists, and for And of those (per-clause candidates
  intersected with a nested membership scan; `[]` otherwise -- the planner
  only chooses the index for answerable shapes).
- `filter_index_answerable(expr) -> Bool` -- every leaf predicate is
  Eq/Range/Exists (`And([])` deliberately not answerable).
- `choose_filter_plan(payloads, expr, total, k) -> Int` -- `1` = pre-filter
  scan (default), `2` = post-filter (exact count >= k and a majority;
  compound shapes via the upper bound, with the scan fallback), `3` = index
  plan (exact count 0 or < total/4; answerable compounds when the upper
  bound is selective or < k).
- `search_service.search_knn_filtered` executes the choice: post ranks the
  whole store and keeps the matching subset (provably exact when the subset
  fills k; otherwise falls back to the scan); index resolves each candidate
  through the store's O(log n) id -> slot map and computes distances only for
  matches (exact); equal-distance ties may select different ids across plans --
  distances and the k-bound are unaffected.

## `xiom.vector.query.search_service` (extracted module)
Implemented today: `SearchResult`/`SearchHits`/`SearchHit`/`HydratedHits`/`BatchHits` + `search_knn` + `search_knn_filtered` + `search_range_scan` + `hydrate_hits` (search_execute pending).
`SearchResult { id: Int; distance: Float32 }`; `BatchHits { sets: Vec[SearchHits] }` is the batch-search wrapper (one set per query, order preserved; struct wrapper because a Result whose payload is a Vec of Vec-bearing structs is the XVC-C-04/C-08 shape family).
- Per-build pin for the Result/Option payload shapes (XVC-C-04): `tests/probes/probe_result_shapes.xi`.
- `search_knn(idx, query, k, metric)` `requires: k > 0, idx.dim == query.dimension` `ensures: result.len() <= k`.
- `search_range_scan(idx, query, radius, limit, metric)` `requires: limit > 0, radius >= 0.0, idx.dim == query.dimension` `ensures: result.len() <= limit` -- exact range scan (M-Q1): keeps every `distance <= radius` (inclusive), distance-sorted ascending, bounded by `limit` (the closest ones); runs on the raw store for BOTH index kinds (exact by construction; ANN widening is M-P tuning). A NaN radius yields an empty result.
- `search_execute(idx, graph, query, k, metric, kind)` -- routes by `AnnIndexKind` (Flat/Ivf -> exact scan, Hnsw -> graph), lowers `Neighbor -> SearchResult`, `ensures: result.len() <= k`.
- `hydrate_hits(items, payloads, with_payload) -> Vec[SearchHit]` -- attaches metadata when requested (`has_payload=false` + empty payload otherwise); `SearchHit { id; distance; payload; has_payload }`, wrapped as `HydratedHits { items }` for the request path (XVC-C-04 shape). The trailing `has_payload` after the Vec-bearing `payload` field was compiler finding XVC-C-08 (fixed in v0.64.2; the suite asserts the flags again, and the real-module probe stays the independent gate).
- `filter_results_by_payload(items, payloads, filter) -> Vec[SearchResult]` -- matching subset, order preserved (shared by the flat post-filter plan and the engine's HNSW+filter path).

## `xiom.vector.query.pagination` (M-Q3)
Cursor pagination over exact search results. The paginated **total order** is
`(distance ascending, id ascending)`: pages are stable within a fixed engine
state (page N + page N+1 + ... reconstructs the ordered result set with no
gaps or duplicates) and equal-distance ties are ordered by id ascending. The
plain `search` path sorts by distance only (tie order unspecified); the
paginated order is the documented contract, on Flat AND Hnsw alike (both
kernels scan the raw store; ANN widening is M-P tuning).
- `search_page_scan(idx, query, k, offset, metric) -> SearchHits` `requires: k > 0, offset >= 0, idx.dim == query.dimension` `ensures: result.items.len() <= k` -- ranks `[offset, offset+k)` of the ordered result set (bounded collector with the id tie-break; O(n * (offset+k)) scan).
- `search_after_scan(idx, query, k, after_id, metric) -> Option[SearchHits]` `requires: k > 0, idx.dim == query.dimension` -- the next k ranks strictly after the CURRENT position of `after_id` (its live vector defines the cursor distance); `None` when the cursor id does not exist (e.g. deleted between pages). Gate: `tests/probes/probe_pagination.xi` (22 checks: page reconstruction, tie clusters, cursor walks, refusals, Flat/Hnsw parity, recovery).

## `xiom.vector.collection.schema`
`enum NormalizationMode { Raw, L2Normalized }`; `PayloadFieldSpec { name; indexed }`; `CollectionSchema { dimension; metric; normalization; payload_fields }`. `schema_new(dim, metric)` `requires: is_valid_dimension(dim)` `ensures: result.dimension == dim`; `schema_set_normalization`, `schema_add_field`, `schema_dimension`.

## `xiom.vector.collection.collection`
`Collection { id: CollectionId; schema; segments: Vec[SegmentId]; index_kind; index_params }`. `collection_new`, `collection_register_segment`, `collection_segment_count`, `collection_dimension`.

## `xiom.vector.collection.validator`
`validate_dimension(schema, dim) -> Bool`; `validate_vector(schema, v) -> Result[Bool, VectorError]` (enforces dimension constancy); `validate_metric(schema, metric) -> Result[Bool, VectorError]`.

## `xiom.vector.payload.{payload,filter_ast,filter_eval}` (extracted modules)
Real modules since 2026-10-08 (first layer of the post-AUDIT module tree);
`xiom.vector.engine.core` imports them (`use xiom.vector.payload.payload/filter_ast/filter_eval`),
and consumers of payload/filter symbols import the submodules directly.
`enum FieldValue { IntVal, FloatVal, TextVal, BoolVal }`; `Payload` +
`payload_new/set/has/get/len`, `field_value_kind`, `field_value_eq` (exact
within type; cross-type false), `field_value_as_float` (Int promotes).
`enum FilterExpr { Eq, Range, Exists, In, And, Or, Not }` + constructors.
`filter_matches(expr, payload) -> Bool` -- full typed evaluation: Eq exact
within type; Range inclusive with Int->Float32 promotion; In membership;
Exists; And/Or/Not combinators. No-payload semantics: value predicates false,
`And([])=true`, `Or([])=false`, `Not([])=true`.
`PayloadStore` (id -> Payload, swap-remove) + `payload_store_put/get/remove/len/matches`.
Sorted key index (Phase 3 refinement): rows kept sorted by
`(field, kind, num, text, id)` in parallel vectors (deliberately not a
`Vec[Struct]` -- that shape is compiler finding XVC-C-08), maintained by
put/overwrite/remove.
- `payload_store_index_len`; `payload_store_index_exists(field)`;
  `payload_store_index_field_count(field)` (selectivity stat for the planner).
- `payload_store_index_eq(field, value) -> Vec[Int]` -- exact tuple search
  for Int/Bool/Text; Float32 values scan the field window and compare
  semantically (IEEE +-0.0 / NaN stay consistent with `field_value_eq`).
- `payload_store_index_range(field, lo, hi) -> Vec[Int]` -- numeric rows of
  the field window (Int promotes to Float32); results come in value order.
- `payload_store_index_count_eq` / `_count_range` -- allocation-free match
  counts for the planner estimates (same semantics as the id-list walks).
- `payload_store_index_field_ids(field) -> Vec[Int]` -- ids carrying the
  field (any value), in index row order (Exists candidates).
NOTE (compiler XVC-C-06): Float32 enum payloads can read as 0 in affected
builds; lane gates avoid FloatVal assertions until fixed.

## `xiom.vector.payload` engine integration
`engine_set_payload(eng, point, payload) -> Result[Bool, CoreError]`
(WAL-before-ack: the encoded record is appended before the store is touched;
`Ok(false)` for a missing point; payloads never outlive their point),
`engine_get_payload -> Option[Payload]`, `engine_search_filtered(eng, query, k, filter) -> Result[SearchHits, CoreError]`
(pre-filter exact scan, `k`-bounded; facade `search_filtered`). `engine_delete`
removes the point's payload.

## Payload WAL codec (durable metadata)
- `payload_encode(p) -> Vec[Int]` -- `[version=1, field_count, (key_len,
  key_bytes...), kind, value_words...]` with kind 1=int, 2=float (Float64 bit
  pattern), 3=text (len, bytes), 4=bool; strings are UTF-8 bytes as Ints.
- `payload_decode(words) -> Option[Payload]` -- strict; malformed -> `None`
  (torn-record tolerance).
- Records are appended as `WalOpKind.Update` (key = point id); `recover_state`
  replays them after Insert/Delete; `wal_writer_checkpoint_from` re-encodes
  live payloads so chained reopen keeps metadata. NOTE (compiler XVC-C-06):
  Float32 payloads can read as 0 in affected builds; lane gates use
  Int/Text/Bool.

## `xiom.vector.segment.{segment_state,segment,manifest,segment_file}`
`enum SegmentStateKind { Mutable, Sealing, Sealed, Indexing, Immutable, Compacting, Dropped }` + `segment_state_is_writable/is_terminal/code/can_transition/from_code`.
`Segment { id; state; store }` + `segment_new/insert/transition/size/is_writable`.
`Manifest { collection; active_segments; last_lsn }` + `manifest_new/add_segment/remove_segment/set_lsn/segment_count`.
- `segment_file.xi` (2026-10-09, M-D4): the sealed-segment codec. Text format
  (LF; CRLF accepted on load): header `xvector-segment 1`, a required meta
  line `meta <seg_id> <cid> <state_code> <dim> <metric_code> <kind_code> <m>
  <efc> <efs>`, then `v <id> <vector_encode words...>` per vector,
  `p <id> <payload_encode words...>` per payload, and an optional
  `g <hnsw_encode words...>` (Hnsw segments). Rules: seg_id >= 1, cid >= 1,
  state 0..6 (persist accepts only Sealed/Immutable -- the engine drives
  Mutable -> Sealing -> Sealed through the real transition table first),
  dim >= 1, stable metric/kind codes, valid params. `SealedSegment {
  valid; seg_id; cid; state; dim; metric; kind; m; ef_construction;
  ef_search; store; payloads; has_graph; graph }` +
  `sealed_segment_new/sealed_segment_seal`. `segment_file_persist(ss,
  path)` is whole-file + atomic (`<path>.tmp` -> `io.rename`; invalid meta /
  non-sealed state / IO error -> false, target untouched). `segment_file_load(path)`
  is byte-level (never a Str) and torn-tail tolerant: missing/garbage/
  headerless files are invalid; a truncated or malformed tail yields the
  longest prefix of complete records (a malformed line stops the prefix);
  the meta line is required; the graph is best-effort (undecodable ->
  dropped, it is rebuildable); reads under 41 bytes are skipped
  (`file_size` guard, XVC-C-12 defense). Engine wiring:
  `engine_seal_segment(eng, seg_id, path)` seals the ACTIVE collection
  (vectors + payloads + graph) and `engine_restore_segment(eng, path)`
  loads a sealed file back into the active collection when cid/dim/metric
  match (else Err, engine untouched) and re-checkpoints the WAL so a reopen
  replays the restored state. Gate: `tests/probes/probe_segment_file.xi`
  (38 checks: degradation, roundtrip, atomic staged/partial temp injection,
  14-point truncation sweep, malformed prefixes, seal/restore with
  bit-exact search, WAL durability after restore, refusals, Flat/empty).

## `xiom.vector.durability.{wal,recovery,write_ahead_events,wal_file,manifest_file}` (extracted modules)
Real modules since 2026-10-08 (wave 3). `wal.xi` holds
`WalOpKind/WalRecord/WalWriter` + `wal_writer_new/append/append_payload/
current_lsn/flush/resume`; `recovery.xi` holds replay + compaction;
`write_ahead_events.xi` holds the event constructors. Record layout
for vectors: **key = point id, value = collection id, payload = encoded
vector**.
- `log_upsert(w, collection, point, payload)`, `log_delete(w, collection, point)`,
  `log_payload_set(w, collection, point, words)` map onto the WAL appends.
- `wal_writer_resume(next_lsn) -> WalWriter` -- empty buffer, LSN continuity.
- `wal_writer_checkpoint_from(w, idx, payloads) -> WalWriter` -- compacted
  checkpoint log: every live point re-encoded as an Insert and every payload
  as an Update with fresh LSNs continuing after `w`; the returned log alone
  reconstructs store + metadata.
- `recover_state(w, dim) -> RecoveredState { store; payloads }` -- replay in
  LSN order (Insert -> store, Delete -> store+payload removal, Update ->
  payload set/overwrite, malformed records skipped); `recover_store` returns
  just the store for compatibility. `engine_recover` uses both and checkpoints
  them.
- `wal_file.xi` (2026-10-09; atomic since the M-D1 slice): whole-file
  persistence on the stdlib APIs available today (`write_file_bytes`/
  `read_file_bytes`/`file_exists`/`file_size`/`rename`). `wal_persist(w,
  path)` builds the text checkpoint (header + one line per record: `lsn op
  key value timestamp payload_len [words...]`), writes it to `<path>.tmp`,
  then swaps it over the target with `io.rename` -- a crash at any point
  leaves either the previous or the new complete file, never a torn one.
  `wal_load(path)` parses byte-wise (never as a Str; defense in depth) and
  returns the longest prefix of complete valid records (torn-tail tolerant;
  missing/garbage/empty files -> empty). Reads shorter than the shortest
  valid WAL are skipped via a `file_size < 25` guard (also semantically
  exact). No fsync/append yet (stdlib gap), so this is a checkpoint rewrite,
  not a delta log. The checkpoint bytes are built LINEARLY (`append_bytes`
  into a `Vec[UInt8]`; the earlier string-concat builder was O(L^2) and
  thrashed the allocator at ~150 KB -- M-G finding). Gate:
  `tests/probes/probe_wal_file.xi` (roundtrip equality vs the live WAL,
  kill/reopen with Hnsw config, overwrite persistence, atomic
  kill-before/during-rename injection, a 9-point byte-truncation sweep with
  per-cut prefix checks, record-boundary cuts, missing/garbage/empty files,
  and a 1200-record scale roundtrip).
- `manifest_file.xi` (2026-10-09, M-D2): the durable collection registry.
  Text format: the header line `xvector-manifest 1` plus one line per entry,
  `<name> <dim> <metric_code> <kind_code> <m> <ef_construction> <ef_search>`;
  names are 1..64 chars from `[A-Za-z0-9_.-]` (no spaces). Types:
  `RegistryEntry { name; dim; metric; kind; m; ef_construction; ef_search }`,
  `CollectionRegistry { valid; version; entries }` +
  `registry_new/registry_add/registry_entry_new`.
  `manifest_persist(reg, path)` validates every entry BEFORE writing
  (invalid name/dim/params -> false, target untouched) and swaps
  `<path>.tmp` over the target with `io.rename` (atomic, the M-D1
  discipline). `manifest_load(path)` parses byte-wise (never as a Str) and
  is torn-tail tolerant: missing/garbage/headerless files are invalid
  (`valid=false`); a truncated or malformed tail yields the longest prefix
  of complete valid entries; a header-only file is a valid empty registry.
  Reads shorter than the 19-byte header are skipped (`file_size` guard,
  XVC-C-12 defense). Names are rebuilt from token bytes; all `Str`
  parameters are by value (XVC-C-13: `&Str` params mislowered to i64).
  Gate: `tests/probes/probe_manifest_file.xi` (38 checks: multi-entry
  roundtrip, overwrite, valid-empty, invalid refusals, atomic
  staged/partial temp injection, a 10-point truncation sweep,
  malformed-line prefixes, the save/open matrix, 500-entry scale).

## `xiom.vector.core.shim` (extracted module)
Local `xiom-core` stand-ins, the porter-flow mapping target: `CoreError` (the
same ten variants as `xiom.core.error`), `Counter` + `counter_new/inc`,
`CollectionId`/`VectorId`/`SegmentId` + `collection_id`/`vector_id`/
`vector_id_value`/`segment_id`/`segment_id_eq`, and the validity predicates
`is_valid_dimension` (1...65536) / `is_valid_top_k` (1...10000).

## `xiom.vector.engine.core` (extracted module)
`VectorEngine { store; graph; index_kind; ann; metric; dimension; created;
wal; upserts; deletes; next_collection; payloads; collections; active_idx;
active_cid; active_name }` -- the orchestrator. D3: the top-level fields
materialize the ACTIVE collection; `collections` holds one full
`CollectionEntry { cid; name; store; payloads; graph; index_kind; ann;
dimension; metric }` per collection in creation order, refreshed from the
live fields by `sync_active` before switches and registry-wide reads
(entry reads/writes are snapshot copies -- shape-validated on v0.64.2;
data ops only touch the live fields). `CollectionList { names: Vec[Str] }`
wraps the names (SearchHits discipline).
- `engine_new()`; `engine_create_collection(eng, dim, metric) -> Result[CollectionId, CoreError]` `requires: dim >= 1` -- legacy path: (re)creates the canonical "default" collection through the registry (existing consumers unchanged).
- Registry (M-D3): `engine_create_named(eng, name, dim, metric) -> Result[CollectionId, CoreError]` -- validates `is_valid_dimension` and `manifest_name_valid` (1..64 chars of `[A-Za-z0-9_.-]`), rejects duplicates, appends the v2 manifest record WAL-first (record value = new cid), parks the previous active and makes the new collection active. `engine_select(eng, name) -> Result[Bool, CoreError]` -- parks the active and materializes the target. `engine_drop(eng, name) -> Result[Bool, CoreError]` -- v3 drop record WAL-first; removing the active selects the first remaining collection (or leaves the engine uncreated, ready for a fresh create). `engine_collection_count`, `engine_list_collections -> CollectionList` (creation order).
- `engine_set_index(eng, kind, params) -> Result[Bool, CoreError]` `requires: eng.created` -- Hnsw validates `ann_params_valid` and rebuilds the graph from the flat store; Flat resets the graph. Logs a v2 manifest update for the ACTIVE collection, so the configuration survives `engine_recover` and checkpoints.
- `engine_compact_index(eng) -> Result[Int, CoreError]` `requires: eng.created` -- rebuilds the HNSW graph from live nodes (Flat -> `Ok(0)`); returns the reclaimed count.
- `engine_upsert(eng, point, vec) -> Result[Bool, CoreError]` `requires: eng.created` -- WAL-before-ack (payload-encoded; **record value = the active collection id**) + store apply + (`Hnsw`) `hnsw_insert_ref` into the graph.
- `engine_search(eng, query, k) -> Result[SearchHits, CoreError]` `requires: eng.created, k > 0` -- routes by `index_kind`: Flat -> `search_knn`, Hnsw -> `hnsw_search` with `ef = ann.ef_search` (Neighbor -> SearchResult). `SearchHits { items: Vec[SearchResult] }`; the struct wrapper is required by compiler finding XVC-C-04.
- `engine_delete` -- store remove + (`Hnsw`) graph tombstone; `engine_set_payload`, `engine_get_payload -> Option[Payload]`, `engine_search_filtered` (`Hnsw`: ANN fetch `ef_search` wide + matching subset, exact flat filtered fallback when under-filled; `Flat`: the planner scan), `engine_get_point -> Option[Vector]`, `engine_size`, `engine_durable_lsn`. Delete/Update records also carry the active collection id.
- `engine_search_range(eng, query, radius, limit) -> Result[SearchHits, CoreError]` `requires: eng.created` -- exact range path (M-Q1): raw-store scan keeping `distance <= radius` (inclusive), distance-sorted ascending, bounded by `limit`; validates dim/limit/radius (negative radius or out-of-range limit -> `InvalidInput`); exact for both index kinds (ANN widening is M-P tuning). Gate `tests/probes/probe_range_search.xi`.
- Pagination (M-Q3): `engine_search_page(eng, query, k, offset) -> Result[SearchHits, CoreError]` -- ranks `[offset, offset+k)` of the paginated total order (distance asc, id asc); validates dim/k/offset (negative offset / out-of-range k -> `InvalidInput`). `engine_search_after(eng, query, k, after_id) -> Result[SearchHits, CoreError]` -- the next k ranks strictly after the current position of `after_id`; a missing cursor id -> `Err(NotFound)`. Exact for both index kinds. Gate `tests/probes/probe_pagination.xi`.
- Batch ops (M-Q2): `engine_upsert_many(eng, ids, vecs) -> Result[Int, CoreError]` (all-or-nothing validation BEFORE applying: non-empty, equal lengths, every dim matches; returns records applied; duplicate ids collapse); `engine_delete_many(eng, ids) -> Result[Int, CoreError]` (idempotent per id; returns actual removals; empty -> `InvalidInput`); `engine_search_many(eng, queries, k) -> Result[BatchHits, CoreError]` (validates all queries first; one result set per query, order preserved). Gate `tests/probes/probe_batch_ops.xi`.
- Selective delete (M-Q4): `engine_delete_filter(eng, filter) -> Result[Int, CoreError]` -- removes every live point whose payload matches `filter`, planner-driven: index-answerable shapes (Eq/Range/Exists/And-of-those) resolve candidates from the sorted payload index (each verified with `payload_store_matches`); every other shape (In/Or/Not) scans the live store. Ids are collected before deletion (store shifts cannot skip points) and applied in ascending order (plan-independent WAL), each through the gated single-delete path: WAL record, graph tombstone (Hnsw), payload + index cleanup. Nothing matching -> `Ok(0)`, never an error. Gate `tests/probes/probe_delete_filter.xi` (26 checks).
- Index admin (M-Q5): `CollectionStats { name; cid; dimension; metric; index_kind; m; ef_construction; ef_search; points; payloads; nodes; tombstones; wal_lsn }` + `engine_collection_stats(eng, name) -> Result[CollectionStats, CoreError]` -- the active collection reports from the live fields, a parked collection from its registry entry (synced at park time); unknown name -> `Err(NotFound)`. `IndexStats { kind; points; nodes_before; nodes_after; reclaimed }` + `engine_rebuild_index(eng) -> Result[IndexStats, CoreError]` `requires: eng.created` -- admin rebuild from the flat store (Hnsw: fresh graph over live nodes only, tombstones reclaimed; Flat: no-op with zeroed graph stats); `compact_index` remains the Int-returning wrapper. Gate `tests/probes/probe_index_admin.xi` (20 checks).
- `engine_search_request(eng, req) -> Result[HydratedHits, CoreError]` -- request-driven search: validates dimension/top_k and that `req.metric` matches the active collection (`InvalidInput` otherwise). M-Q6 dispatch: `mode=Range` runs the exact range path (top_k as inclusive-radius limit; filters and pagination are Knn-only and rejected loudly in range mode; negative radius -> `InvalidInput`); knn `after_id >= 0` continues after the cursor (`Err(NotFound)` for a missing id; mutually exclusive with `offset`); knn `offset > 0` returns those ranks; pagination does not combine with filters yet (loud `InvalidInput`). Otherwise dispatches filtered vs plain (plain routes by index kind; filtered uses the ANN+fallback path on Hnsw), then hydrates when `req.with_payload`. Gate `tests/probes/probe_search_request.xi` (24 checks).
- `engine_search_batch_request(eng, batch) -> Result[HydratedBatch, CoreError]` -- one `HydratedHits` per request, order preserved (all-or-nothing: empty -> `InvalidInput`; the first failing request aborts the batch). `HydratedBatch { sets: Vec[HydratedHits] }` is the C-04 family wrapper. Facade `search_batch_with_request`.
- `recover_store(w, dim) -> VectorIndex` `requires: dim > 0` -- legacy single-collection replay (kept in `durability.recovery`; the engine now uses the registry path).
- Multi-collection recovery (M-D3): `engine_recover(w, dim, metric) -> VectorEngine` `requires: dim > 0` -- builds the collection set from `ManifestUpdate` records (v1 legacy `[1, dim, mc, kc, m, efc, efs]` -> "default"/cid 1; v2 config `[2, name_len, name..., dim, mc, kc, m, efc, efs]` upserted by record value = cid; v3 drop `[3, name_len, name...]`), replays data records **routed by collection id** when the log carries v2/v3 records (D3 strict mode) or into the single collection otherwise (legacy logs, where the value field is not meaningful), applies each collection's index (Hnsw graphs rebuilt), and writes a compacted checkpoint WAL carrying every alive collection's data + its v2 manifest. No manifest at all -> caller dim/metric as the single "default" collection. Malformed records are ignored; LSNs stay monotonic. Prefix exactness (crash guarantee at the WAL model level) is gated by `tests/probes/probe_kill_recovery.xi`.
- `engine_manifest_save(eng, path) -> Bool` -- persist the WHOLE registry (one entry per collection, cid order; whole-file + atomic rename via the D2 codec). `engine_recover_file(w, path, dim, metric) -> VectorEngine` `requires: dim > 0` -- the same recovery, with the manifest file's entries overriding configs **by collection name** (the registry of record; the D2 first-entry rule applies to single-collection logs); names absent from the file keep the in-WAL config, and a missing/corrupt file falls back entirely to the WAL. Gates: `tests/probes/probe_manifest_file.xi`, `tests/probes/probe_collections.xi`.
- Segments (M-D4): `engine_seal_segment(eng, seg_id, path) -> Result[Bool, CoreError]` `requires: eng.created` -- write the active collection as a sealed segment file (vectors + payloads + Hnsw graph codec; lifecycle driven Mutable -> Sealing -> Sealed through `segment_state_can_transition` before the write; atomic temp+rename). `engine_restore_segment(eng, path) -> Result[Bool, CoreError]` `requires: eng.created` -- load a sealed file into the active collection when cid/dim/metric match (else Err, engine untouched) and re-checkpoint the WAL through the shared `engine_checkpoint_from(eng, base_lsn)` (whole-registry compacted checkpoint with LSN continuity), so a reopen replays the restored state. Gate `tests/probes/probe_segment_file.xi`.

## `xiom.vector.engine` (facade)
Public facade over `engine.core` (acyclic: `core.shim <- engine.core <- engine`):
`create_collection`, `create_named_collection`, `select_collection`,
`drop_collection`, `list_collections`, `collection_count`, `set_index`,
`compact_index`, `upsert`, `upsert_many`, `search`, `search_many`,
`delete_point`, `delete_many`, `delete_filter`, `get_point`, `set_payload`, `get_payload`,
`collection_stats`, `rebuild_index`,
`search_filtered`, `search_range`, `search_page`, `search_after`,
`search_with_request`, `search_batch_with_request`, `save_manifest`,
`open_engine`, `seal_segment`, `restore_segment` -- thin delegations.
Consumers that call `engine_*` symbols (engine_new/engine_size/engine_recover/
...) import `xiom.vector.engine.core` in addition to this module.

## `xiom.vector.api.vector_api`
Merged stub (`// MERGED into xiom.vector.engine`); the public facade lives in
`src/engine.xi`.

---

## Distance formulas

| Metric | Formula | Range | Notes |
|--------|---------|-------|-------|
| Euclidean (L2) | `sqrtSigma(ai-bi)2` | `[0, inf)` | magnitude-sensitive; `l2_squared` skips the sqrt |
| Dot product | `-Sigma(aibi)` | `(-inf, inf)` | negated so closer = smaller |
| Cosine | `1 - (a-b)/(||a||||b||)` | `[0, 2]` | angular; zero vectors -> 1.0 |
