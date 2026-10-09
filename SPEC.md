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
    |-- segment/{segment_state,segment,manifest}.xi
    |-- index/{ann_index,flat_index,hnsw}.xi
    |-- distance/{cosine,dot,l2}.xi
    |-- query/{search_request,filter_plan,topk_heap,search_service}.xi
    |-- durability/{wal,recovery,write_ahead_events}.xi
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
- `metric_name(m) -> Str`.

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
`enum AnnIndexKind { Flat, Hnsw, Ivf }`; `AnnParams { m; ef_construction; ef_search }`. `ann_params_default` (`m=16, efC=200, efS=64`), `ann_params_valid` (bounds `m` by `core.limits.max_graph_degree`), `ann_index_kind_name`.

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
`SearchRequest { query: Vector; top_k: Int; metric: DistanceMetric; filter: Vec[FilterExpr]; with_payload: Bool }` -- the wire shape for request-driven search (the pre-extraction file carried inline mirrors; now it imports the extracted types).
- `search_request_new(query, top_k, metric)` `requires: top_k > 0`; `with_payload` defaults false.
- `search_request_set_filter(req, expr)` -- single-clause replace (`[]` = no filter); `search_request_has_filter`, `search_request_top_k`.
- `search_request_set_with_payload(req, on)` -- toggle hydration.

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
  for Eq/Range/Exists (`[]` otherwise; the index plan is chosen only for those).
- `choose_filter_plan(payloads, expr, total, k) -> Int` -- `1` = pre-filter
  scan (default), `2` = post-filter (exact count >= k and a majority; compound
  shapes via the upper bound, with the scan fallback), `3` = index plan
  (exact count 0 or < total/4).
- `search_service.search_knn_filtered` executes the choice: post ranks the
  whole store and keeps the matching subset (provably exact when the subset
  fills k; otherwise falls back to the scan); index resolves each candidate
  through the store's O(log n) id -> slot map and computes distances only for
  matches (exact); equal-distance ties may select different ids across plans --
  distances and the k-bound are unaffected.

## `xiom.vector.query.search_service` (extracted module)
Implemented today: `SearchResult`/`SearchHits`/`SearchHit`/`HydratedHits` + `search_knn` + `search_knn_filtered` + `hydrate_hits` (search_range / search_execute pending).
`SearchResult { id: Int; distance: Float32 }`.
- Per-build pin for the Result/Option payload shapes (XVC-C-04): `tests/probes/probe_result_shapes.xi`.
- `search_knn(idx, query, k, metric)` `requires: k > 0, idx.dim == query.dimension` `ensures: result.len() <= k`.
- `search_range(idx, query, radius, metric)` `requires: radius > 0.0, idx.dim == query.dimension`.
- `search_execute(idx, graph, query, k, metric, kind)` -- routes by `AnnIndexKind` (Flat/Ivf -> exact scan, Hnsw -> graph), lowers `Neighbor -> SearchResult`, `ensures: result.len() <= k`.
- `hydrate_hits(items, payloads, with_payload) -> Vec[SearchHit]` -- attaches metadata when requested (`has_payload=false` + empty payload otherwise); `SearchHit { id; distance; payload; has_payload }`, wrapped as `HydratedHits { items }` for the request path (XVC-C-04 shape). NOTE (compiler XVC-C-08): the trailing `has_payload` field after the Vec-bearing `payload` field can read as garbage in affected compilation units; hydration flags are gated in the real-module probe only.
- `filter_results_by_payload(items, payloads, filter) -> Vec[SearchResult]` -- matching subset, order preserved (shared by the flat post-filter plan and the engine's HNSW+filter path).

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

## `xiom.vector.segment.{segment_state,segment,manifest}`
`enum SegmentStateKind { Mutable, Sealing, Sealed, Indexing, Immutable, Compacting, Dropped }` + `segment_state_is_writable/is_terminal/code/can_transition`.
`Segment { id; state; store }` + `segment_new/insert/transition/size/is_writable`.
`Manifest { collection; active_segments; last_lsn }` + `manifest_new/add_segment/remove_segment/set_lsn/segment_count`.

## `xiom.vector.durability.{wal,recovery,write_ahead_events}` (extracted modules)
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

## `xiom.vector.core.shim` (extracted module)
Local `xiom-core` stand-ins, the porter-flow mapping target: `CoreError` (the
same ten variants as `xiom.core.error`), `Counter` + `counter_new/inc`,
`CollectionId`/`VectorId`/`SegmentId` + `collection_id`/`vector_id`/
`vector_id_value`/`segment_id`/`segment_id_eq`, and the validity predicates
`is_valid_dimension` (1...65536) / `is_valid_top_k` (1...10000).

## `xiom.vector.engine.core` (extracted module)
`VectorEngine { store; graph; index_kind; ann; metric; dimension; created;
wal; upserts; deletes; next_collection; payloads }` -- the orchestrator that
owns the active collection, the WAL, the payload store, and (when
`index_kind = Hnsw`) the ANN graph mirroring the store.
- `engine_new()`; `engine_create_collection(eng, dim, metric) -> Result[CollectionId, CoreError]` `requires: dim >= 1` (resets to Flat; logs the collection manifest).
- `engine_set_index(eng, kind, params) -> Result[Bool, CoreError]` `requires: eng.created` -- Hnsw validates `ann_params_valid` and rebuilds the graph from the flat store; Flat resets the graph. Logs a manifest update, so the configuration survives `engine_recover` and checkpoints.
- `engine_compact_index(eng) -> Result[Int, CoreError]` `requires: eng.created` -- rebuilds the HNSW graph from live nodes (Flat -> `Ok(0)`); returns the reclaimed count.
- `engine_upsert(eng, point, vec) -> Result[Bool, CoreError]` `requires: eng.created` -- WAL-before-ack (payload-encoded) + store apply + (`Hnsw`) `hnsw_insert_ref` into the graph.
- `engine_search(eng, query, k) -> Result[SearchHits, CoreError]` `requires: eng.created, k > 0` -- routes by `index_kind`: Flat -> `search_knn`, Hnsw -> `hnsw_search` with `ef = ann.ef_search` (Neighbor -> SearchResult). `SearchHits { items: Vec[SearchResult] }`; the struct wrapper is required by compiler finding XVC-C-04.
- `engine_delete` -- store remove + (`Hnsw`) graph tombstone; `engine_set_payload`, `engine_get_payload -> Option[Payload]`, `engine_search_filtered` (`Hnsw`: ANN fetch `ef_search` wide + matching subset, exact flat filtered fallback when under-filled; `Flat`: the planner scan), `engine_get_point -> Option[Vector]`, `engine_size`, `engine_durable_lsn`.
- `engine_search_request(eng, req) -> Result[HydratedHits, CoreError]` -- request-driven search: validates dimension/top_k and that `req.metric` matches the active collection (`InvalidInput` otherwise), dispatches filtered vs plain (plain routes by index kind; filtered uses the ANN+fallback path on Hnsw), then hydrates when `req.with_payload`.
- `recover_store(w, dim) -> VectorIndex` `requires: dim > 0` -- replay the WAL: decode Inserts, apply Deletes, skip malformed payloads.
- `engine_recover(w, dim, metric) -> VectorEngine` `requires: dim > 0` -- replay of store + payloads, then compacted checkpoint WAL (carries store, payloads AND the latest collection manifest); LSNs stay monotonic. The latest `ManifestUpdate` record (`[version=1, dim, metric_code, kind_code, m, ef_construction, ef_search]`, logged by create_collection/set_index) governs dim/metric/index kind/params -- including rebuilding an Hnsw graph -- with the caller's dim/metric as the fallback for pre-manifest logs (Flat collection). Malformed manifests are ignored.

## `xiom.vector.engine` (facade)
Public facade over `engine.core` (acyclic: `core.shim <- engine.core <- engine`):
`create_collection`, `set_index`, `compact_index`, `upsert`, `search`,
`delete_point`, `get_point`, `set_payload`, `get_payload`,
`search_filtered`, `search_with_request` -- thin delegations.
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
