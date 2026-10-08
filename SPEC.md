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
    |-- query/{search_request,topk_heap,search_service}.xi
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
`VectorIndex { vectors: Vec[Vector]; ids: Vec[Int]; dim: Int }` -- flat columnar store.
- `index_new(dim)` `requires: dim > 0`
- `index_add(idx, id, vec)` `requires: idx.dim == vec.dimension` (returns false on duplicate id)
- `index_remove` (O(1) swap-with-last), `index_get -> Option[Vector]`, `index_size`.

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

## `xiom.vector.index.hnsw`
`HNSWNode { id: UInt64; neighbors: Vec[Neighbor] }`, `HNSWLayer`, `HNSWGraph { layers; max_neighbors; ml }`.
- `hnsw_new(max_neighbors, ml)` `requires: max_neighbors > 0`, `ml > 0.0`.
- `hnsw_insert(graph, id, vec)` -- level assignment, greedy descent, in-layer neighbour selection, bidirectional edges bounded by `max_neighbors`.
- `hnsw_search(graph, query, k)` `requires: k > 0` `ensures: result.len() <= k` -- returns `Vec[Neighbor]`.
- `hnsw_layer_count`, `hnsw_node_count`.

## `xiom.vector.distance.{cosine,dot,l2}`
Kernel seam (SIMD drop-in point, Phase 10). `cosine_kernel`/`cosine_similarity`, `dot_distance`/`dot_raw`, `l2_distance`/`l2_squared`. Delegate to `types.metric` today.

## `xiom.vector.query.search_request`
`SearchRequest { query: Vector; top_k: Int; metric: DistanceMetric; filter: Vec[FilterExpr]; with_payload: Bool }`. `search_request_new` `requires: top_k > 0`, `search_request_set_filter`, `search_request_has_filter`, `search_request_top_k`.

## `xiom.vector.query.topk_heap`
`TopKHeap { capacity; items: Vec[Neighbor] }`. `topk_new(capacity)` `requires: capacity > 0` `ensures: items.len() == 0`; `topk_push` `ensures: items.len() <= capacity`; `topk_len`, `topk_is_full`, `topk_worst`.

## `xiom.vector.query.search_service` (extracted module)
Implemented today: `SearchResult`/`SearchHits` + `search_knn` + `search_knn_filtered` (search_range / search_execute pending).
`SearchResult { id: Int; distance: Float32 }`.
- `search_knn(idx, query, k, metric)` `requires: k > 0, idx.dim == query.dimension` `ensures: result.len() <= k`.
- `search_range(idx, query, radius, metric)` `requires: radius > 0.0, idx.dim == query.dimension`.
- `search_execute(idx, graph, query, k, metric, kind)` -- routes by `AnnIndexKind` (Flat/Ivf -> exact scan, Hnsw -> graph), lowers `Neighbor -> SearchResult`, `ensures: result.len() <= k`.

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
`VectorEngine { store; metric; dimension; created; wal; upserts; deletes;
next_collection; payloads }` -- the orchestrator that owns the active
collection, the WAL, and the payload store.
- `engine_new()`; `engine_create_collection(eng, dim, metric) -> Result[CollectionId, CoreError]` `requires: dim >= 1`.
- `engine_upsert(eng, point, vec) -> Result[Bool, CoreError]` `requires: eng.created` -- WAL-before-ack (payload-encoded) + store apply + metric.
- `engine_search(eng, query, k) -> Result[SearchHits, CoreError]` `requires: eng.created, k > 0`, `SearchHits { items: Vec[SearchResult] }`. The struct wrapper is required by compiler finding XVC-C-04 (`Result[Vec[non-scalar]]` loses element fields on v0.64.0).
- `engine_delete`, `engine_set_payload`, `engine_get_payload -> Option[Payload]`, `engine_search_filtered`, `engine_get_point -> Option[Vector]`, `engine_size`, `engine_durable_lsn`.
- `recover_store(w, dim) -> VectorIndex` `requires: dim > 0` -- replay the WAL: decode Inserts, apply Deletes, skip malformed payloads.
- `engine_recover(w, dim, metric) -> VectorEngine` `requires: dim > 0` -- replay of store + payloads, then compacted checkpoint WAL (carries both); LSNs stay monotonic.

## `xiom.vector.engine` (facade)
Public facade over `engine.core` (acyclic: `core.shim <- engine.core <- engine`):
`create_collection`, `upsert`, `search`, `delete_point`, `get_point`,
`set_payload`, `get_payload`, `search_filtered` -- thin delegations.
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
