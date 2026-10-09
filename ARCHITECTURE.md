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
|-- core/
|   `-- shim.xi      module xiom.vector.core.shim
|                     xiom-core stand-ins (porter-flow mapping target):
|                     CoreError, Counter + counter_new/inc,
|                     CollectionId/VectorId/SegmentId + helpers, and the
|                     validity predicates is_valid_dimension/is_valid_top_k [EXTRACTED]
|-- error.xi        module xiom.vector.error
|                     VectorError { DimensionMismatch, UnsupportedMetric,
|                     CollectionNotFound, InvalidVector, SegmentSealed,
|                     TopKExceeded } + to_str / to_core / code
|-- ids.xi          module xiom.vector.ids
|                     PointId (user id) + reuse of core CollectionId/VectorId/
|                     SegmentId + PointId<->VectorId bridges
|-- engine.xi       module xiom.vector.engine
|                     public facade ONLY -- create_collection, set_index,
|                     compact_index, upsert, search, delete_point,
|                     get_point, set_payload, get_payload,
|                     search_filtered, search_with_request; thin
|                     delegation to engine.core (no shims here)          [EXTRACTED]
|-- engine/
|   `-- core.xi      module xiom.vector.engine.core
|                     VectorEngine + engine_* orchestration -- engine_new,
|                     engine_create_collection, engine_set_index,
|                     engine_compact_index, engine_upsert, engine_search
|                     (routes Flat/Hnsw), engine_delete,
|                     engine_set_payload, engine_get_payload,
|                     engine_search_filtered, engine_search_request,
|                     engine_get_point, engine_size, engine_durable_lsn,
|                     engine_recover + the durable collection manifest
|                     (REAL dispatch to store + graph + WAL
|                     + search + payloads + recovery)                     [EXTRACTED]
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
|   |-- payload.xi        Payload + FieldValue + WAL codec + store +
|   |                     sorted key index (parallel-vector rows)       [EXTRACTED]
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
|   `-- hnsw.xi           multi-layer graph (geometric levels, greedy
|                         descent + layer-0 beam; word codec; recall
|                         harness)                                      [DONE]
|
|-- distance/
|   |-- cosine.xi         cosine kernel + similarity                  [DONE]
|   |-- dot.xi            dot distance + raw dot                      [DONE]
|   `-- l2.xi             l2 distance + l2_squared                    [DONE]
|
|-- query/
|   |-- search_request.xi SearchRequest (query, top_k, metric, filter) [DONE]
|   |-- filter_plan.xi   selectivity estimates + pre/post plan choice [EXTRACTED]
|   |-- topk_heap.xi      bounded top-K heap (invariant: <= k)         [DONE]
|   `-- search_service.xi search_knn / search_knn_filtered (planned)   [EXTRACTED]
|
|-- durability/
|   |-- wal.xi            WalOpKind/WalRecord/WalWriter + append/resume  [EXTRACTED]
|   |-- recovery.xi       recover_state/store + checkpoint compaction    [EXTRACTED]
|   `-- write_ahead_events.xi log_upsert/log_delete/log_payload_set      [EXTRACTED]
|
`-- api/
    `-- vector_api.xi     merged stub -- the facade lives in engine.xi  [MERGED]
```

### Dependency direction

Higher layers depend on lower layers; there are no upward dependencies:

```
engine (facade) -> engine.core + core.shim (signature types) + value types
engine.core -> { core.shim, query.search_service -> storage.vector_store /
                 payload.filter_eval / query.filter_plan,
                 query.filter_plan -> payload.index (counts),
                 index.ann_index (kind/params), index.hnsw (graph upkeep +
                 search), storage.vector_store, durability.*,
                 payload.*, types.* }
index.flat_index -> query.search_service (delegates exact scan)
index.hnsw -> types.{dense_vector, neighbor, metric} + storage.vector_store
               (graph codec; no query dependency)
collection/* -> types, index.ann_index, core.shim ids
segment/* -> storage.vector_store, segment_state, core.shim ids
payload.filter_eval -> payload.filter_ast -> payload.payload
everything fallible -> core.shim (CoreError; the local stand-in until the
                       xiom.core porter flow maps it onto the package)
```

The extraction chain is acyclic: **core.shim <- engine.core <- engine**
(facade). The facade never reaches into the store, and the shim imports
nothing from the vector tree.

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
        2. route by the collection's index kind (set_index):
             Flat/Ivf -> search_service.search_knn  (exact scan, O(n))
             Hnsw     -> index.hnsw.hnsw_search      (multi-layer greedy
                         descent + beam, ef = ann.ef_search)
        3. filter (Phase 3): Hnsw -> ANN fetch (ef_search wide) then keep the
           matching subset; under-filled -> exact flat filtered scan. Flat ->
           the planner (pre/post/index):
             scan  -> evaluate FilterExpr per candidate BEFORE distance
             post  -> rank all via the flat scan, keep the matching subset;
                      if it does not fill k, fall back to the scan
             index -> Eq/Range/Exists candidates from the sorted payload
                      index; distances only for matches (store id map)
           (post for an exact k-or-more majority or a compound upper bound;
            index for an exact count 0 or < total/4; query/filter_plan.xi)
        4. rerank: bounded top-K heap keeps <= k best by distance
        5. (Phase 3) hydrate: attach payloads when with_payload = true
        6. return Ok(SearchHits{ items }) (items.len() <= k, guaranteed)
```

`SearchHits` is a struct wrapper around the result Vec: on compiler v0.64.0 a
`Result[Vec[non-scalar], E]` payload loses element fields at the caller
(finding XVC-C-04), so the public shape wraps it. Unwrap when the compiler
fix lands.

Request-driven variant (Phase 3): `search_with_request` ->
`engine_search_request` takes top_k/filter/with_payload from a
`SearchRequest`, validates the request metric against the active collection,
and optionally hydrates payloads (`hydrate_hits` -> `HydratedHits`,
`SearchHit { id; distance; payload; has_payload }`). NOTE (XVC-C-08): the
trailing `has_payload` after the Vec-bearing payload field can misread in
affected compilation units -- hydration flags are gated in the real-module
probe only (repro: `docs/repro/xv-trailing-field-vec/`).

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
