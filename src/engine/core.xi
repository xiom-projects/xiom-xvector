// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.engine.core

// VectorEngine orchestrator: owns the flat store, the WAL, the collection
// config (dimension/metric), the counters and the payload store. The
// engine_* operations are the internal engine surface; the consumer-facing
// facade (xiom.vector.engine) delegates to them. Extracted from the
// consolidated engine in the final extraction wave (acyclic: core.shim <-
// engine.core <- engine facade).

use xiom.vector.core.shim;
use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;
use xiom.vector.storage.vector_store;
use xiom.vector.query.search_service;
use xiom.vector.query.search_request;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
use xiom.vector.durability.wal;
use xiom.vector.durability.recovery;
use xiom.vector.durability.write_ahead_events;

// ---- VectorEngine ----
pub type VectorEngine = {
  store: VectorIndex;
  metric: DistanceMetric;
  dimension: Int;
  created: Bool;
  wal: WalWriter;
  upserts: Counter;
  deletes: Counter;
  next_collection: Int;
  payloads: PayloadStore;
}

pub fn engine_new() -> VectorEngine {
  return VectorEngine{
    store: index_new(1),
    metric: DistanceMetric.Euclidean,
    dimension: 0,
    created: false,
    wal: wal_writer_new(),
    upserts: counter_new("vector.upserts"),
    deletes: counter_new("vector.deletes"),
    next_collection: 1,
    payloads: payload_store_new(),
  };
}

pub fn engine_create_collection(eng: &mut VectorEngine, dim: Int, metric: DistanceMetric) -> Result[CollectionId, CoreError]
  requires: dim >= 1
{
  if !is_valid_dimension(dim) {
    return Err(CoreError.InvalidInput("dimension out of range"));
  }
  eng.store = index_new(dim);
  eng.dimension = dim;
  eng.metric = metric;
  eng.created = true;
  eng.payloads = payload_store_new();
  var id = collection_id(eng.next_collection);
  eng.next_collection = eng.next_collection + 1;
  return Ok(id);
}

pub fn engine_upsert(eng: &mut VectorEngine, point: Int, vec: Vector) -> Result[Bool, CoreError]
  requires: eng.created
{
  if vec.dimension != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  var payload = vector_encode(&vec);
  log_upsert(&mut eng.wal, 1, point, payload);
  var ok = index_add(&mut eng.store, point, vec);
  counter_inc(&mut eng.upserts);
  return Ok(ok);
}

pub fn engine_search(eng: &VectorEngine, query: &Vector, k: Int) -> Result[SearchHits, CoreError]
  requires: eng.created
  requires: k > 0
{
  if query.dimension != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  if !is_valid_top_k(k) {
    return Err(CoreError.InvalidInput("top_k out of range"));
  }
  var hits = search_knn(&eng.store, query, k, eng.metric);
  return Ok(SearchHits{ items: hits });
}

pub fn engine_delete(eng: &mut VectorEngine, point: Int) -> Result[Bool, CoreError]
  requires: eng.created
{
  log_delete(&mut eng.wal, 1, point);
  var ok = index_remove(&mut eng.store, point);
  payload_store_remove(&mut eng.payloads, point);   // no orphan metadata
  counter_inc(&mut eng.deletes);
  return Ok(ok);
}

// Attach/replace metadata for an existing point (WAL-before-ack: the encoded
// payload record is appended before the in-memory store is touched).
// Returns Ok(false) when the point does not exist (payloads never outlive
// their point).
pub fn engine_set_payload(eng: &mut VectorEngine, point: Int, payload: Payload) -> Result[Bool, CoreError]
  requires: eng.created
{
  match index_get(&eng.store, point) {
    Some(_) => {
      var words = payload_encode(&payload);
      log_payload_set(&mut eng.wal, 1, point, words);
      payload_store_put(&mut eng.payloads, point, payload);
      return Ok(true);
    }
    None => { return Ok(false); }
  }
}

pub fn engine_get_payload(eng: &VectorEngine, point: Int) -> Option[Payload] {
  return payload_store_get(&eng.payloads, point);
}

// Filtered exact top-k: dimension/top_k validation, then a filtered scan.
pub fn engine_search_filtered(eng: &VectorEngine, query: &Vector, k: Int, filter: &FilterExpr) -> Result[SearchHits, CoreError]
  requires: eng.created
  requires: k > 0
{
  if query.dimension != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  if !is_valid_top_k(k) {
    return Err(CoreError.InvalidInput("top_k out of range"));
  }
  var hits = search_knn_filtered(&eng.store, &eng.payloads, query, k, eng.metric, filter);
  return Ok(SearchHits{ items: hits });
}

// Request-driven search: honors the request's top_k, filter, and
// with_payload hydration flag. The active collection's metric governs; a
// request whose metric differs from the collection is rejected. Returns
// HydratedHits (SearchHit carries id/distance + optional payload) so the
// same call serves both plain and hydrated searches.
pub fn engine_search_request(eng: &VectorEngine, req: &SearchRequest) -> Result[HydratedHits, CoreError]
  requires: eng.created
  requires: req.top_k > 0
{
  if req.query.dimension != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  if !is_valid_top_k(req.top_k) {
    return Err(CoreError.InvalidInput("top_k out of range"));
  }
  if req.metric != eng.metric {
    return Err(CoreError.InvalidInput("metric mismatch"));
  }
  if search_request_has_filter(req) {
    var hits = search_knn_filtered(&eng.store, &eng.payloads, &req.query, req.top_k, eng.metric, &req.filter[0]);
    return Ok(HydratedHits{ items: hydrate_hits(&hits, &eng.payloads, req.with_payload) });
  }
  var hits = search_knn(&eng.store, &req.query, req.top_k, eng.metric);
  return Ok(HydratedHits{ items: hydrate_hits(&hits, &eng.payloads, req.with_payload) });
}

// Point getter used by the facade's `get_point` -- keeps the facade from
// reaching into the store directly.
pub fn engine_get_point(eng: &VectorEngine, point: Int) -> Option[Vector] {
  return index_get(&eng.store, point);
}

pub fn engine_size(eng: &VectorEngine) -> Int {
  return index_size(&eng.store);
}

pub fn engine_durable_lsn(eng: &VectorEngine) -> Int {
  return wal_writer_current_lsn(&eng.wal);
}

// Rebuild an engine from its WAL: replay the log into a fresh store + payload
// store, then write a compacted checkpoint log (so the recovered engine is
// itself recoverable). LSNs stay monotonic; dimension/metric are restored.
pub fn engine_recover(w: &WalWriter, dim: Int, metric: DistanceMetric) -> VectorEngine
  requires: dim > 0
{
  var eng = engine_new();
  var st = recover_state(w, dim);
  eng.store = st.store;
  eng.payloads = st.payloads;
  eng.dimension = dim;
  eng.metric = metric;
  eng.created = true;
  eng.wal = wal_writer_checkpoint_from(w, &eng.store, &eng.payloads);
  return eng;
}
