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
use xiom.vector.types.neighbor;
use xiom.vector.storage.vector_store;
use xiom.vector.index.ann_index;
use xiom.vector.index.hnsw;
use xiom.vector.query.search_service;
use xiom.vector.query.search_request;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
use xiom.vector.durability.wal;
use xiom.vector.durability.recovery;
use xiom.vector.durability.write_ahead_events;

// ---- VectorEngine ----
// The flat store is always maintained (source of truth for ids/vectors);
// when `index_kind` is Hnsw, `graph` mirrors it for approximate search.
pub type VectorEngine = {
  store: VectorIndex;
  graph: HNSWGraph;
  index_kind: AnnIndexKind;
  ann: AnnParams;
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
    graph: hnsw_new(16, 4.0),
    index_kind: AnnIndexKind.Flat,
    ann: ann_params_default(),
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

// ---- Collection manifest (durable config) ----
// The active collection's configuration travels in the WAL as a
// ManifestUpdate record so engine_recover restores it without a manual
// set_index. Layout: [version=1, dim, metric_code, kind_code, m,
// ef_construction, ef_search]. Malformed / pre-manifest logs fall back to
// the caller's dim/metric with a Flat collection.
pub type CollectionManifest = {
  valid: Bool;
  dim: Int;
  metric: DistanceMetric;
  kind: AnnIndexKind;
  m: Int;
  ef_construction: Int;
  ef_search: Int;
}

fn empty_manifest() -> CollectionManifest {
  return CollectionManifest{
    valid: false,
    dim: 0,
    metric: DistanceMetric.Euclidean,
    kind: AnnIndexKind.Flat,
    m: 0,
    ef_construction: 0,
    ef_search: 0,
  };
}

fn metric_code(m: DistanceMetric) -> Int {
  if m == DistanceMetric.Cosine { return 1; }
  if m == DistanceMetric.DotProduct { return 2; }
  return 3;
}

fn kind_code(k: AnnIndexKind) -> Int {
  if k == AnnIndexKind.Flat { return 1; }
  if k == AnnIndexKind.Hnsw { return 2; }
  return 3;
}

fn parse_manifest(words: &Vec[Int]) -> CollectionManifest {
  var mf = empty_manifest();
  if words.len() != 7 { return mf; }
  if words[0] != 1 { return mf; }
  var d: Int = words[1];
  if d < 1 { return mf; }
  var mc: Int = words[2];
  if mc < 1 || mc > 3 { return mf; }
  var kc: Int = words[3];
  if kc < 1 || kc > 3 { return mf; }
  var p = AnnParams{ m: words[4], ef_construction: words[5], ef_search: words[6] };
  if !ann_params_valid(&p) { return mf; }
  mf.dim = d;
  if mc == 1 { mf.metric = DistanceMetric.Cosine; } elif mc == 2 { mf.metric = DistanceMetric.DotProduct; } else { mf.metric = DistanceMetric.Euclidean; }
  if kc == 1 { mf.kind = AnnIndexKind.Flat; } elif kc == 2 { mf.kind = AnnIndexKind.Hnsw; } else { mf.kind = AnnIndexKind.Ivf; }
  mf.m = p.m;
  mf.ef_construction = p.ef_construction;
  mf.ef_search = p.ef_search;
  mf.valid = true;
  return mf;
}

fn last_manifest(w: &WalWriter) -> CollectionManifest {
  var out = empty_manifest();
  var i: Int = w.records.len() - 1;
  var found: Bool = false;
  while i >= 0 && !found {
    if w.records[i].op == WalOpKind.ManifestUpdate {
      out = parse_manifest(&w.records[i].payload);
      found = true;
    }
    i = i - 1;
  }
  return out;
}

fn log_manifest(eng: &mut VectorEngine, kind: AnnIndexKind, params: AnnParams) {
  var words = Vec[Int].new();
  words.push(1);
  words.push(eng.dimension);
  words.push(metric_code(eng.metric));
  words.push(kind_code(kind));
  words.push(params.m);
  words.push(params.ef_construction);
  words.push(params.ef_search);
  wal_writer_append_payload(&mut eng.wal, WalOpKind.ManifestUpdate, 0, 0, words);
}

// Apply an index configuration to the (already created) collection: Hnsw
// builds the graph from the flat store; anything else resets the graph.
// Build into a local then assign once (XVC-C-09: repeated cross-module
// access to eng.graph inside the loop crashed the WSL build).
fn apply_index(eng: &mut VectorEngine, kind: AnnIndexKind, params: AnnParams) {
  if kind == AnnIndexKind.Hnsw {
    var g = hnsw_new(params.m, 4.0);
    hnsw_set_ef_construction(&mut g, params.ef_construction);
    var i: Int = 0;
    while i < eng.store.ids.len() {
      var pid = eng.store.ids[i];
      var pv = eng.store.vectors[i];
      hnsw_insert_ref(&mut g, pid, &pv, eng.metric);
      i = i + 1;
    }
    eng.graph = g;
  } else {
    eng.graph = hnsw_new(16, 4.0);
  }
  eng.index_kind = kind;
  eng.ann = params;
}

pub fn engine_create_collection(eng: &mut VectorEngine, dim: Int, metric: DistanceMetric) -> Result[CollectionId, CoreError]
  requires: dim >= 1
{
  if !is_valid_dimension(dim) {
    return Err(CoreError.InvalidInput("dimension out of range"));
  }
  eng.store = index_new(dim);
  eng.graph = hnsw_new(16, 4.0);
  eng.index_kind = AnnIndexKind.Flat;
  eng.ann = ann_params_default();
  eng.dimension = dim;
  eng.metric = metric;
  eng.created = true;
  eng.payloads = payload_store_new();
  log_manifest(eng, AnnIndexKind.Flat, ann_params_default());
  var id = collection_id(eng.next_collection);
  eng.next_collection = eng.next_collection + 1;
  return Ok(id);
}

// Select the ANN index for the active collection. Hnsw validates its params
// and (re)builds the graph from the flat store; Flat resets the graph to
// empty. The choice is in-memory only (collection metadata persistence is
// future work), so callers re-apply it after engine_recover.
pub fn engine_set_index(eng: &mut VectorEngine, kind: AnnIndexKind, params: AnnParams) -> Result[Bool, CoreError]
  requires: eng.created
{
  if kind == AnnIndexKind.Hnsw {
    if !ann_params_valid(&params) {
      return Err(CoreError.InvalidInput("invalid ann params"));
    }
  }
  apply_index(eng, kind, params);
  log_manifest(eng, kind, params);
  return Ok(true);
}

// Compact the ANN graph: rebuild it from the live nodes, reclaiming
// tombstoned slots (no-op returning 0 for a Flat collection). The flat
// store is untouched. Returns the number of reclaimed graph nodes.
pub fn engine_compact_index(eng: &mut VectorEngine) -> Result[Int, CoreError]
  requires: eng.created
{
  if eng.index_kind != AnnIndexKind.Hnsw {
    return Ok(0);
  }
  var before: Int = hnsw_size(&eng.graph);
  var fresh = hnsw_compact(&eng.graph, eng.metric);
  eng.graph = fresh;
  var after: Int = hnsw_size(&eng.graph);
  return Ok(before - after);
}

pub fn engine_upsert(eng: &mut VectorEngine, point: Int, vec: Vector) -> Result[Bool, CoreError]
  requires: eng.created
{
  if vec.dimension != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  var payload = vector_encode(&vec);
  log_upsert(&mut eng.wal, 1, point, payload);
  if eng.index_kind == AnnIndexKind.Hnsw {
    hnsw_insert_ref(&mut eng.graph, point, &vec, eng.metric);
  }
  var ok = index_add(&mut eng.store, point, vec);
  counter_inc(&mut eng.upserts);
  return Ok(ok);
}

// HNSW results are Neighbor(id: UInt64, distance); the engine surface uses
// SearchResult(id: Int, distance).
fn neighbors_to_results(items: &Vec[Neighbor]) -> Vec[SearchResult] {
  var out = Vec[SearchResult].new();
  var i: Int = 0;
  while i < items.len() {
    out.push(SearchResult{ id: items[i].id as Int, distance: items[i].distance });
    i = i + 1;
  }
  return out;
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
  if eng.index_kind == AnnIndexKind.Hnsw {
    var neighbors = hnsw_search(&eng.graph, query, k, eng.ann.ef_search, eng.metric);
    return Ok(SearchHits{ items: neighbors_to_results(&neighbors) });
  }
  var hits = search_knn(&eng.store, query, k, eng.metric);
  return Ok(SearchHits{ items: hits });
}

pub fn engine_delete(eng: &mut VectorEngine, point: Int) -> Result[Bool, CoreError]
  requires: eng.created
{
  log_delete(&mut eng.wal, 1, point);
  var ok = index_remove(&mut eng.store, point);
  if eng.index_kind == AnnIndexKind.Hnsw {
    hnsw_delete(&mut eng.graph, point);
  }
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

// Filtered search on an Hnsw collection: ANN fetch (ef_search wide), keep
// the matching subset (order preserved), and fall back to the exact flat
// filtered scan when the ANN pass under-fills -- selective filters stay
// exact and k-filled at the cost of one scan. Approximation semantics match
// the unfiltered ANN path.
fn hnsw_search_filtered(eng: &VectorEngine, query: &Vector, k: Int, filter: &FilterExpr) -> Vec[SearchResult] {
  var fetch: Int = eng.ann.ef_search;
  if fetch < k { fetch = k; }
  var neighbors = hnsw_search(&eng.graph, query, fetch, fetch, eng.metric);
  var raw = neighbors_to_results(&neighbors);
  var matched = filter_results_by_payload(&raw, &eng.payloads, filter);
  if matched.len() >= k {
    var out = Vec[SearchResult].new();
    var i: Int = 0;
    while i < k {
      out.push(SearchResult{ id: matched[i].id, distance: matched[i].distance });
      i = i + 1;
    }
    return out;
  }
  return search_knn_filtered(&eng.store, &eng.payloads, query, k, eng.metric, filter);
}

// Filtered exact top-k: dimension/top_k validation, then the exact flat
// filtered scan (the planner picks the pre/post plan). ANN + filter is
// future work, so this path is always exact even on an Hnsw collection.
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
  if eng.index_kind == AnnIndexKind.Hnsw {
    var hits = hnsw_search_filtered(eng, query, k, filter);
    return Ok(SearchHits{ items: hits });
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
    if eng.index_kind == AnnIndexKind.Hnsw {
      var hits0 = hnsw_search_filtered(eng, &req.query, req.top_k, &req.filter[0]);
      return Ok(HydratedHits{ items: hydrate_hits(&hits0, &eng.payloads, req.with_payload) });
    }
    var hits = search_knn_filtered(&eng.store, &eng.payloads, &req.query, req.top_k, eng.metric, &req.filter[0]);
    return Ok(HydratedHits{ items: hydrate_hits(&hits, &eng.payloads, req.with_payload) });
  }
  if eng.index_kind == AnnIndexKind.Hnsw {
    var nn = hnsw_search(&eng.graph, &req.query, req.top_k, eng.ann.ef_search, eng.metric);
    var hh = neighbors_to_results(&nn);
    return Ok(HydratedHits{ items: hydrate_hits(&hh, &eng.payloads, req.with_payload) });
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

// Rebuild an engine from its WAL: the latest collection manifest (when
// present) governs dim/metric/index kind/params -- the caller's dim/metric
// are the fallback for pre-manifest logs -- then the log replays into a
// fresh store + payload store, the configured index is applied, and a
// compacted checkpoint log (inserts + updates + the manifest) is written so
// the recovered engine is itself recoverable. LSNs stay monotonic.
pub fn engine_recover(w: &WalWriter, dim: Int, metric: DistanceMetric) -> VectorEngine
  requires: dim > 0
{
  var mf = last_manifest(w);
  var eff_dim: Int = dim;
  var eff_metric: DistanceMetric = metric;
  if mf.valid {
    eff_dim = mf.dim;
    eff_metric = mf.metric;
  }
  var eng = engine_new();
  var st = recover_state(w, eff_dim);
  eng.store = st.store;
  eng.payloads = st.payloads;
  eng.dimension = eff_dim;
  eng.metric = eff_metric;
  eng.created = true;
  if mf.valid {
    var params = AnnParams{ m: mf.m, ef_construction: mf.ef_construction, ef_search: mf.ef_search };
    apply_index(&mut eng, mf.kind, params);
  }
  eng.wal = wal_writer_checkpoint_from(w, &eng.store, &eng.payloads);
  return eng;
}
