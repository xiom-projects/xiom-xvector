<!--
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0
-->

# xiom-vector -- Architecture

## 1. Design model: shared core + vector layer

xiom-vector does **not** re-implement durable-systems plumbing. It adopts the
same model as the rest of the XIOM data ecosystem (xiom-db, xiom-vector):

```
+--------------------------------------------------------------+
|                         xiom-vector                            |
|   vector-specific layers: types, storage, indexes, query,      |
|   collections, payload/filtering, segments, durability, api    |
`-------------------------------+--------------------------------+
                                 | depends on (reuse, not fork)
+-------------------------------v--------------------------------+
|                          xiom-core                             |
|  error - ids - config - limits - contracts - wal - metrics -   |
|  storage(pager/page/buffer_pool) - txn                         |
`--------------------------------------------------------------+
```

**Why a shared core?** Errors, identifiers, the WAL record format, system limits,
and correctness predicates must be *identical* across every engine so that (a)
recovery only ever parses one WAL shape, (b) a `CoreError` means the same thing
everywhere, and (c) guardrails like `max_dimensions()` / `max_top_k()` cannot
drift between subsystems. The vector engine contributes only what is genuinely
vector-specific.

## 2. Module tree (file by file)

```
src/
|-- error.xi        module xiom.vector.error
|                     VectorError { DimensionMismatch, UnsupportedMetric,
|                     CollectionNotFound, InvalidVector, SegmentSealed,
|                     TopKExceeded } + to_str / to_core / code
|-- ids.xi          module xiom.vector.ids
|                     PointId (user id) + reuse of core CollectionId/VectorId/
|                     SegmentId + PointId<->VectorId bridges
|-- engine.xi       module xiom.vector.engine
|                     VectorEngine orchestrator -- engine_new,
|                     engine_create_collection, engine_upsert, engine_search,
|                     engine_delete (REAL dispatch to store + WAL + search)
|                     NOTE: engine.xi is the CONSOLIDATED working core being
|                     unwound layer by layer. EXTRACTED so far: payload/
|                     filter layer; types (dense_vector/metric/neighbor);
|                     storage/vector_store (+ vector WAL codec);
|                     query/search_service. Still inline: core-error/ids/
|                     counter/WAL types, recovery/checkpoint, VectorEngine +
|                     engine_* functions, API facade (next extraction
|                     targets; cross-file imports work on v0.64.0).
|
|-- types/
|   |-- dense_vector.xi   Vector + new/set/get + dot/magnitude          [EXTRACTED]
|   |-- metric.xi         DistanceMetric + cosine/dot/euclidean +
|   |                     vector_distance dispatch                   [EXTRACTED]
|   |-- neighbor.xi       Neighbor (id, distance) low-level edge      [EXTRACTED]
|   `-- dimension.xi      Dimension wrapper + validation              [DONE]
|
|-- collection/
|   |-- schema.xi         CollectionSchema (dim, metric, normalization,
|   |                     payload fields)                            [IN PROGRESS]
|   |-- collection.xi     Collection (schema + segment registry + index cfg) [SCAFFOLD]
|   `-- validator.xi      dimension/metric compatibility, typed errors [IN PROGRESS]
|
|-- payload/
|   |-- payload.xi        Payload + FieldValue + WAL codec + store      [EXTRACTED]
|   |-- filter_ast.xi     FilterExpr (Eq/Range/Exists/In/And/Or/Not)  [EXTRACTED]
|   `-- filter_eval.xi    typed eval + payload_store_matches          [EXTRACTED]
|
|-- storage/
|   |-- vector_store.xi   VectorIndex flat store + vector WAL codec   [EXTRACTED]
|   `-- id_map.xi         VectorId -> (segment, offset) mapping       [DONE-ish]
|
|-- segment/
|   |-- segment_state.xi  SegmentStateKind + transition table         [SCAFFOLD]
|   |-- segment.xi        Segment (store + state)                     [SCAFFOLD]
|   `-- manifest.xi       collection manifest of active segments      [SCAFFOLD]
|
|-- index/
|   |-- ann_index.xi      AnnIndexKind {Flat,Hnsw,Ivf} + AnnParams    [DONE]
|   |-- flat_index.xi     exact brute-force baseline (truth oracle)   [DONE]
|   `-- hnsw.xi           in-memory HNSW graph (insert + greedy search) [DONE]
|
|-- distance/
|   |-- cosine.xi         cosine kernel + similarity                  [DONE]
|   |-- dot.xi            dot distance + raw dot                      [DONE]
|   `-- l2.xi             l2 distance + l2_squared                    [DONE]
|
|-- query/
|   |-- search_request.xi SearchRequest (query, top_k, metric, filter) [DONE]
|   |-- topk_heap.xi      bounded top-K heap (invariant: <= k)         [DONE]
|   `-- search_service.xi search_knn / search_knn_filtered (exact)    [EXTRACTED]
|
|-- durability/
|   `-- write_ahead_events.xi vector WAL events on core WAL           [SCAFFOLD]
|
`-- api/
    `-- vector_api.xi     public facade (create/upsert/search/delete/get) [DONE]
```

### Dependency direction

Higher layers depend on lower layers; there are no upward dependencies:

```
api -> engine -> { query.search_service -> index.hnsw, storage.vector_store,
                 durability.write_ahead_events, metric }
index.flat_index -> query.search_service (delegates exact scan)
index.hnsw -> types.{dense_vector, neighbor, metric}   (no query dependency)
collection/* -> types, index.ann_index, core.ids
segment/* -> storage.vector_store, segment_state, core.ids
payload.filter_eval -> payload.filter_ast -> payload.payload
everything fallible -> core.error (CoreError)
```

`index.hnsw` deliberately returns `Neighbor` (not the query-layer
`SearchResult`) so the index layer never depends on the query layer. The query
layer lowers `Neighbor -> SearchResult`.

## 3. Write path (durable upsert)

```
api.upsert
  `-> engine_upsert
        1. validate: vec.dimension == collection.dimension   (reject early)
        2. WAL-before-ack: log_upsert -> wal_writer_append_payload
           (key = point id, value = collection id,
            payload = [dim, Float64-bits...] via vector_encode)
        3. apply: storage.index_add into the mutable store
        4. metrics: counter_inc(upserts)
        5. ack: Ok(true) to caller
```

Invariant: **no write is acknowledged before its WAL record exists.** The
vector payload is now serialized into the record, so a point can be
reconstructed on recovery. The WAL itself is still in memory and
`wal_writer_flush` is an LSN marker; on v0.64.0 the stdlib exposes no fsync
syscall (`xiom.os.fs_ffi.fsync` is a documented stub -- see
`docs/STDLIB-WISHLIST-XVECTOR.md`), so the file-backed, fsync'd log is the
next Phase 2 step.

## 3a. Recovery path (reopen)

```
engine_recover(w, dim, metric)
  `-> recover_state(w, dim)          replay in LSN order:
                                     Insert  -> store add (vector_decode)
                                     Delete  -> store + payload removal
                                     Update  -> payload set (payload_decode)
                                     malformed payloads skipped
      wal_writer_checkpoint_from(w, store, payloads)
                                     compacted checkpoint log: every live
                                     point + payload re-encoded with fresh
                                     monotonic LSNs
```

The checkpoint log alone reconstructs the store and its metadata, so a
recovered engine is itself recoverable (chained reopen is covered by
`test_recover_twice` / `test_recover_payloads_chained`); a durable manifest
will later persist it instead of rebuilding on every open.

## 3b. Metadata write path (payloads)

```
api.set_payload
  `-> engine_set_payload
        1. validate: the point exists (Ok(false) otherwise)
        2. WAL-before-ack: log_payload_set -> payload_encode -> Update record
        3. apply: PayloadStore put/overwrite
        4. ack: Ok(true)
```

Payloads never outlive their point: `engine_delete` removes both the vector
and the metadata record. Float32 payloads are diagnostic-only on v0.64.0
(compiler XVC-C-06).

## 4. Search path (top-k query)

```
api.search
  `-> engine_search
        1. validate: query.dimension == collection.dimension; is_valid_top_k(k)
        2. route (search_execute): AnnIndexKind selects the physical index
             Flat/Ivf -> search_service.search_knn  (exact scan, O(n))
             Hnsw     -> index.hnsw.hnsw_search      (approximate, greedy)
        3. filter (Phase 3): evaluate FilterExpr against each candidate payload
           BEFORE distance (pre-filter exact scan; selectivity planner later)
        4. rerank: bounded top-K heap keeps <= k best by distance
        5. (Phase 3) hydrate: attach payloads when with_payload = true
        6. return Ok(SearchHits{ items }) (items.len() <= k, guaranteed)
```

`SearchHits` is a struct wrapper around the result Vec: on compiler v0.64.0 a
`Result[Vec[non-scalar], E]` payload loses element fields at the caller
(finding XVC-C-04), so the public shape wraps it. Unwrap when the compiler
fix lands.

Multi-segment fan-out (Phase 5) inserts a step 2a: iterate the collection's live
segments from the manifest, search each, and merge into the same top-K heap.

## 5. Reuse-from-core table

| Vector-layer concern | Reuses from `xiom-core` | Why |
|----------------------|-------------------------|-----|
| Error channel        | `error.CoreError`, `core_error_to_str` | one error type across engines; no hidden failure channels |
| Identity             | `ids.CollectionId / VectorId / SegmentId` (+ local `PointId`) | shared id vocabulary; compile-time separation of id kinds |
| Guardrails           | `limits.max_dimensions / max_top_k / max_graph_degree` | ceilings can't drift between subsystems |
| Predicates           | `contracts.is_valid_dimension / is_valid_top_k` | `requires:`/`ensures:` stay in sync with runtime checks |
| Durability           | `wal.wal_writer` (`wal_writer_new/append`) | one WAL format -> one recovery parser |
| Observability        | `metrics.Counter`, `counter_inc` | uniform metrics registry |
| Config               | `config.CoreConfig`, `core_config_default` | single startup profile |

## 6. Contract hotspots

The places where correctness is enforced in code (and documented in
`docs/contracts-and-invariants.md`):

- **Dimension constancy** -- `collection.validator.validate_vector`,
  `engine_upsert`/`engine_search`, and every `vector_distance` kernel
  `requires: a.dimension == b.dimension`.
- **Bounded results** -- `search_knn` / `hnsw_search` / `search_execute`
  `ensures: result.len() <= k`; `topk_heap.topk_push`
  `ensures: items.len() <= capacity`.
- **Graph degree** -- HNSW neighbour selection bounds each node's adjacency by
  `max_neighbors` (<= `core.limits.max_graph_degree()`).
- **Segment lifecycle** -- `segment_state.segment_state_can_transition` is the
  single source of truth for legal state moves.
- **WAL-before-ack** -- `engine_upsert`/`engine_delete` append to the WAL before
  mutating the store.

## 7. Failure domains

| Domain | Failure | Handling |
|--------|---------|----------|
| Input validation | wrong dimension, bad top_k, unknown metric | reject with `CoreError.InvalidInput` / `VectorError` **before** any state change |
| Durability | WAL append/flush fault | surfaces as `CoreError.IOFailure` (retryable); write is **not** acked |
| Storage | duplicate id on insert | `index_add` returns `false` (idempotent upsert semantics in Phase 2) |
| Index | empty graph / cold search | returns an empty result set, never panics |
| Recovery | truncated/corrupt WAL tail | in-memory replay: malformed payloads are skipped (`vector_decode -> None`), later valid records still replayed; LSNs stay monotonic. File-backed torn-tail repair waits on `ftruncate` (stdlib wishlist). |
| Segment | write to a sealed segment | `VectorError.SegmentSealed` (enforced Phase 5) |

Each domain fails as an explicit `Result` value -- XIOM has no exceptions, so
every caller must handle the failure.
