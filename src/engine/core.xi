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
use xiom.string.slice;
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
use xiom.vector.durability.write_ahead_events;
use xiom.vector.durability.manifest_file;

// ---- VectorEngine ----
// The flat store is always maintained (source of truth for ids/vectors);
// when `index_kind` is Hnsw, `graph` mirrors it for approximate search.
//
// D3 (multi-collection): the top-level fields materialize the ACTIVE
// collection; `collections` holds one full entry per collection in creation
// (cid) order -- the active collection's entry is refreshed from the live
// fields by `sync_active` before any registry-wide read or a switch. Data
// ops (upsert/search/...) only touch the live fields; `active_cid` is the
// collection id stamped into WAL data records and `active_name` names it in
// v2 manifest records.
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
  collections: Vec[CollectionEntry];
  active_idx: Int;
  active_cid: Int;
  active_name: Str;
}

// One named collection's full state (registry entry). The active collection
// is also materialized in the VectorEngine's top-level fields.
pub type CollectionEntry = {
  cid: Int;
  name: Str;
  store: VectorIndex;
  payloads: PayloadStore;
  graph: HNSWGraph;
  index_kind: AnnIndexKind;
  ann: AnnParams;
  dimension: Int;
  metric: DistanceMetric;
}

// The registry names list (struct wrapper, the SearchHits discipline:
// Result-free Vec[Str] payloads stay behind a named shape).
pub type CollectionList = {
  names: Vec[Str];
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
    collections: Vec[CollectionEntry].new(),
    active_idx: -1,
    active_cid: 0,
    active_name: "",
  };
}

// ---- Collection registry (durable config, D3) ----
// The registry maps collection ids to names + configuration. It travels in
// the WAL as ManifestUpdate records in three payload families:
//   v1 legacy: [1, dim, mc, kc, m, efc, efs]              (no name; cid 1)
//   v2 config: [2, name_len, name..., dim, mc, kc, m, efc, efs]
//                                                         (record value = cid)
//   v3 drop:   [3, name_len, name...]                     (record value = cid)
// and in the manifest file (D2) as one `<name> <dim> <mc> <kc> <m> <efc>
// <efs>` line per collection. Malformed records are ignored; legacy v1
// records upsert the canonical "default" collection (cid 1).
pub type ManifestInfo = {
  valid: Bool;
  version: Int;
  name: Str;
  dim: Int;
  metric: DistanceMetric;
  kind: AnnIndexKind;
  m: Int;
  ef_construction: Int;
  ef_search: Int;
}

fn empty_manifest_info() -> ManifestInfo {
  return ManifestInfo{
    valid: false,
    version: 0,
    name: "",
    dim: 0,
    metric: DistanceMetric.Euclidean,
    kind: AnnIndexKind.Flat,
    m: 0,
    ef_construction: 0,
    ef_search: 0,
  };
}

fn parse_manifest_info(words: &Vec[Int]) -> ManifestInfo {
  var mf = empty_manifest_info();
  if words.len() < 1 { return mf; }
  var ver: Int = words[0];
  if ver == 1 {
    if words.len() != 7 { return mf; }
    var d: Int = words[1];
    var mc: Int = words[2];
    var kc: Int = words[3];
    if d < 1 || mc < 1 || mc > 3 || kc < 1 || kc > 3 { return mf; }
    var p = AnnParams{ m: words[4], ef_construction: words[5], ef_search: words[6] };
    if !ann_params_valid(&p) { return mf; }
    mf.name = "default";
    mf.dim = d;
    mf.metric = metric_from_code(mc);
    mf.kind = ann_kind_from_code(kc);
    mf.m = p.m;
    mf.ef_construction = p.ef_construction;
    mf.ef_search = p.ef_search;
    mf.valid = true;
    mf.version = 1;
    return mf;
  }
  if ver == 2 {
    if words.len() < 3 { return mf; }
    var nlen: Int = words[1];
    if nlen < 1 || nlen > 64 { return mf; }
    if words.len() != 8 + nlen { return mf; }
    var nb = Vec[UInt8].new();
    var i: Int = 0;
    while i < nlen {
      var b: Int = words[2 + i];
      if b < 0 || b > 255 { return mf; }
      nb.push(b as UInt8);
      i = i + 1;
    }
    var nm = Str::from_utf8(&nb);
    if !manifest_name_valid(nm) { return mf; }
    var d2: Int = words[2 + nlen];
    var mc2: Int = words[3 + nlen];
    var kc2: Int = words[4 + nlen];
    if d2 < 1 || mc2 < 1 || mc2 > 3 || kc2 < 1 || kc2 > 3 { return mf; }
    var p2 = AnnParams{ m: words[5 + nlen], ef_construction: words[6 + nlen], ef_search: words[7 + nlen] };
    if !ann_params_valid(&p2) { return mf; }
    mf.name = nm;
    mf.dim = d2;
    mf.metric = metric_from_code(mc2);
    mf.kind = ann_kind_from_code(kc2);
    mf.m = p2.m;
    mf.ef_construction = p2.ef_construction;
    mf.ef_search = p2.ef_search;
    mf.valid = true;
    mf.version = 2;
    return mf;
  }
  if ver == 3 {
    if words.len() < 3 { return mf; }
    var nlen3: Int = words[1];
    if nlen3 < 1 || nlen3 > 64 { return mf; }
    if words.len() != 2 + nlen3 { return mf; }
    var nb3 = Vec[UInt8].new();
    var i3: Int = 0;
    while i3 < nlen3 {
      var b3: Int = words[2 + i3];
      if b3 < 0 || b3 > 255 { return mf; }
      nb3.push(b3 as UInt8);
      i3 = i3 + 1;
    }
    var nm3 = Str::from_utf8(&nb3);
    if !manifest_name_valid(nm3) { return mf; }
    mf.name = nm3;
    mf.valid = true;
    mf.version = 3;
    return mf;
  }
  return mf;
}

// v2 config record words (record value carries the collection id).
fn manifest_words(name: Str, dim: Int, metric: DistanceMetric, kind: AnnIndexKind, params: AnnParams) -> Vec[Int] {
  var words = Vec[Int].new();
  words.push(2);
  var nb = slice.str_bytes(name);
  words.push(nb.len());
  var i: Int = 0;
  while i < nb.len() {
    words.push(nb[i] as Int);
    i = i + 1;
  }
  words.push(dim);
  words.push(metric_code(metric));
  words.push(ann_kind_code(kind));
  words.push(params.m);
  words.push(params.ef_construction);
  words.push(params.ef_search);
  return words;
}

fn log_manifest(eng: &mut VectorEngine, kind: AnnIndexKind, params: AnnParams) {
  var words = manifest_words(eng.active_name, eng.dimension, eng.metric, kind, params);
  wal_writer_append_payload(&mut eng.wal, WalOpKind.ManifestUpdate, 0, eng.active_cid, words);
}

// Snapshot the live (active) collection into its registry entry. Called
// before any registry-wide read and before switching away; entry reads are
// copies (validated on v0.64.2), so this is a plain read-modify-write-back.
fn sync_active(eng: &mut VectorEngine) {
  if eng.active_idx < 0 { return; }
  var i: Int = eng.active_idx;
  var e = eng.collections[i];
  e.cid = eng.active_cid;
  e.name = eng.active_name;
  e.store = eng.store;
  e.payloads = eng.payloads;
  e.graph = eng.graph;
  e.index_kind = eng.index_kind;
  e.ann = eng.ann;
  e.dimension = eng.dimension;
  e.metric = eng.metric;
  eng.collections[i] = e;
}

// Materialize registry entry `idx` as the live active collection.
fn load_active(eng: &mut VectorEngine, idx: Int) {
  var e = eng.collections[idx];
  eng.store = e.store;
  eng.payloads = e.payloads;
  eng.graph = e.graph;
  eng.index_kind = e.index_kind;
  eng.ann = e.ann;
  eng.dimension = e.dimension;
  eng.metric = e.metric;
  eng.created = true;
  eng.active_idx = idx;
  eng.active_cid = e.cid;
  eng.active_name = e.name;
}

// Forget the live view (dropping the last collection leaves an engine that
// is ready for a fresh create).
fn reset_active(eng: &mut VectorEngine) {
  eng.store = index_new(1);
  eng.graph = hnsw_new(16, 4.0);
  eng.index_kind = AnnIndexKind.Flat;
  eng.ann = ann_params_default();
  eng.metric = DistanceMetric.Euclidean;
  eng.dimension = 0;
  eng.created = false;
  eng.payloads = payload_store_new();
  eng.active_idx = -1;
  eng.active_cid = 0;
  eng.active_name = "";
}

fn collection_find(eng: &VectorEngine, name: Str) -> Int {
  var i: Int = 0;
  while i < eng.collections.len() {
    if eng.collections[i].name == name { return i; }
    i = i + 1;
  }
  return -1;
}

pub fn engine_collection_count(eng: &VectorEngine) -> Int {
  return eng.collections.len();
}

pub fn engine_list_collections(eng: &VectorEngine) -> CollectionList {
  var names = Vec[Str].new();
  var i: Int = 0;
  while i < eng.collections.len() {
    names.push(eng.collections[i].name);
    i = i + 1;
  }
  return CollectionList{ names: names };
}

// Create a named collection (empty), make it active, and append its v2
// manifest record first (WAL-before-ack). Rejects invalid or duplicate
// names and invalid dimensions; the previous active collection is parked
// with its state intact.
pub fn engine_create_named(eng: &mut VectorEngine, name: Str, dim: Int, metric: DistanceMetric) -> Result[CollectionId, CoreError] {
  if !is_valid_dimension(dim) {
    return Err(CoreError.InvalidInput("dimension out of range"));
  }
  if !manifest_name_valid(name) {
    return Err(CoreError.InvalidInput("invalid collection name"));
  }
  if collection_find(eng, name) >= 0 {
    return Err(CoreError.InvalidInput("collection exists"));
  }
  var cid: Int = eng.next_collection;
  eng.next_collection = eng.next_collection + 1;
  var params = ann_params_default();
  var words = manifest_words(name, dim, metric, AnnIndexKind.Flat, params);
  wal_writer_append_payload(&mut eng.wal, WalOpKind.ManifestUpdate, 0, cid, words);
  sync_active(eng);
  var e = CollectionEntry{
    cid: cid,
    name: name,
    store: index_new(dim),
    payloads: payload_store_new(),
    graph: hnsw_new(16, 4.0),
    index_kind: AnnIndexKind.Flat,
    ann: params,
    dimension: dim,
    metric: metric,
  };
  eng.collections.push(e);
  load_active(eng, eng.collections.len() - 1);
  return Ok(collection_id(cid));
}

// Make a named collection active (no-op when it already is).
pub fn engine_select(eng: &mut VectorEngine, name: Str) -> Result[Bool, CoreError] {
  var idx = collection_find(eng, name);
  if idx < 0 {
    return Err(CoreError.InvalidInput("collection not found"));
  }
  if idx == eng.active_idx {
    return Ok(true);
  }
  sync_active(eng);
  load_active(eng, idx);
  return Ok(true);
}

// Drop a named collection: log the v3 drop record first (WAL-before-ack),
// remove the entry, and fix the active view (select the first remaining
// collection when the dropped one was active).
pub fn engine_drop(eng: &mut VectorEngine, name: Str) -> Result[Bool, CoreError] {
  var idx = collection_find(eng, name);
  if idx < 0 {
    return Err(CoreError.InvalidInput("collection not found"));
  }
  var cid: Int = eng.collections[idx].cid;
  var words = Vec[Int].new();
  words.push(3);
  var nb = slice.str_bytes(name);
  words.push(nb.len());
  var i: Int = 0;
  while i < nb.len() {
    words.push(nb[i] as Int);
    i = i + 1;
  }
  wal_writer_append_payload(&mut eng.wal, WalOpKind.ManifestUpdate, 0, cid, words);
  var j: Int = idx;
  while j < eng.collections.len() - 1 {
    eng.collections[j] = eng.collections[j + 1];
    j = j + 1;
  }
  eng.collections.pop();
  if idx == eng.active_idx {
    reset_active(eng);
    if eng.collections.len() > 0 {
      load_active(eng, 0);
    }
  } elif idx < eng.active_idx {
    eng.active_idx = eng.active_idx - 1;
  }
  return Ok(true);
}

// Persist the whole registry (one entry per collection, cid order): whole-
// file + atomic rename via the D2 manifest-file codec. False on IO error.
pub fn engine_manifest_save(eng: &mut VectorEngine, path: Str) -> Bool {
  sync_active(eng);
  var reg = registry_new();
  var i: Int = 0;
  while i < eng.collections.len() {
    var e = eng.collections[i];
    registry_add(&mut reg, registry_entry_new(e.name, e.dimension, e.metric, e.index_kind, e.ann));
    i = i + 1;
  }
  return manifest_persist(&reg, path);
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

// The registry-entry form of the same operation (used for parked
// collections during recovery).
fn entry_apply_index(e: &mut CollectionEntry, kind: AnnIndexKind, params: AnnParams) {
  if kind == AnnIndexKind.Hnsw {
    var g = hnsw_new(params.m, 4.0);
    hnsw_set_ef_construction(&mut g, params.ef_construction);
    var i: Int = 0;
    while i < e.store.ids.len() {
      var pid = e.store.ids[i];
      var pv = e.store.vectors[i];
      hnsw_insert_ref(&mut g, pid, &pv, e.metric);
      i = i + 1;
    }
    e.graph = g;
  } else {
    e.graph = hnsw_new(16, 4.0);
  }
  e.index_kind = kind;
  e.ann = params;
}

// Legacy single-collection entry point: (re)creates the canonical "default"
// collection through the registry path. Multi-collection callers use
// engine_create_named.
pub fn engine_create_collection(eng: &mut VectorEngine, dim: Int, metric: DistanceMetric) -> Result[CollectionId, CoreError]
  requires: dim >= 1
{
  if !is_valid_dimension(dim) {
    return Err(CoreError.InvalidInput("dimension out of range"));
  }
  if collection_find(eng, "default") >= 0 {
    match engine_drop(eng, "default") {
      Ok(_) => {}
      Err(_) => {}
    }
  }
  return engine_create_named(eng, "default", dim, metric);
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
  log_upsert(&mut eng.wal, eng.active_cid, point, payload);
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
  log_delete(&mut eng.wal, eng.active_cid, point);
  var ok = index_remove(&mut eng.store, point);
  if eng.index_kind == AnnIndexKind.Hnsw {
    hnsw_delete(&mut eng.graph, point);
  }
  payload_store_remove(&mut eng.payloads, point);   // no orphan metadata
  counter_inc(&mut eng.deletes);
  return Ok(ok);
}

// Batch upsert (M-Q2): all-or-nothing per call. The whole batch is validated
// BEFORE anything is applied (non-empty, equal lengths, every vector matches
// the collection dimension), then each point goes through the same
// WAL-before-ack path as engine_upsert. Returns the number of records
// applied (duplicate ids collapse in the store, like single upserts).
pub fn engine_upsert_many(eng: &mut VectorEngine, ids: &Vec[Int], vecs: &Vec[Vector]) -> Result[Int, CoreError]
  requires: eng.created
{
  if ids.len() == 0 {
    return Err(CoreError.InvalidInput("empty batch"));
  }
  if ids.len() != vecs.len() {
    return Err(CoreError.InvalidInput("batch length mismatch"));
  }
  var i: Int = 0;
  while i < vecs.len() {
    if vecs[i].dimension != eng.dimension {
      return Err(CoreError.InvalidInput("dimension mismatch"));
    }
    i = i + 1;
  }
  i = 0;
  while i < ids.len() {
    match engine_upsert(eng, ids[i], vecs[i]) {
      Ok(_) => {}
      Err(e) => { return Err(e); }
    }
    i = i + 1;
  }
  return Ok(ids.len());
}

// Batch delete (M-Q2): idempotent per id (missing ids are skipped, not an
// error); returns the number of points actually removed. Empty batches are
// rejected loudly.
pub fn engine_delete_many(eng: &mut VectorEngine, ids: &Vec[Int]) -> Result[Int, CoreError]
  requires: eng.created
{
  if ids.len() == 0 {
    return Err(CoreError.InvalidInput("empty batch"));
  }
  var removed: Int = 0;
  var i: Int = 0;
  while i < ids.len() {
    match engine_delete(eng, ids[i]) {
      Ok(ok) => { if ok { removed = removed + 1; } }
      Err(e) => { return Err(e); }
    }
    i = i + 1;
  }
  return Ok(removed);
}

// Batch search (M-Q2): one result set per query, order preserved.
// All-or-nothing validation (non-empty, k in range, every query dimension
// matches) happens before any search runs. Returns `BatchHits` (struct
// wrapper; a Result whose payload is a Vec of Vec-bearing structs is the
// XVC-C-04/C-08 shape family).
pub fn engine_search_many(eng: &VectorEngine, queries: &Vec[Vector], k: Int) -> Result[BatchHits, CoreError]
  requires: eng.created
{
  if queries.len() == 0 {
    return Err(CoreError.InvalidInput("empty batch"));
  }
  if !is_valid_top_k(k) {
    return Err(CoreError.InvalidInput("top_k out of range"));
  }
  var i: Int = 0;
  while i < queries.len() {
    if queries[i].dimension != eng.dimension {
      return Err(CoreError.InvalidInput("dimension mismatch"));
    }
    i = i + 1;
  }
  var sets = Vec[SearchHits].new();
  i = 0;
  while i < queries.len() {
    match engine_search(eng, &queries[i], k) {
      Ok(h) => { sets.push(h); }
      Err(e) => { return Err(e); }
    }
    i = i + 1;
  }
  return Ok(BatchHits{ sets: sets });
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
      log_payload_set(&mut eng.wal, eng.active_cid, point, words);
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

// Exact range search: points within `radius` (inclusive) on the active
// collection, distance-sorted ascending, at most `limit` items (the closest
// ones). Exact for both index kinds (raw-store scan); ANN widening is M-P
// tuning. Negative radius and out-of-range limit are rejected loudly.
pub fn engine_search_range(eng: &VectorEngine, query: &Vector, radius: Float32, limit: Int) -> Result[SearchHits, CoreError]
  requires: eng.created
{
  if query.dimension != eng.dimension {
    return Err(CoreError.InvalidInput("dimension mismatch"));
  }
  if !is_valid_top_k(limit) {
    return Err(CoreError.InvalidInput("limit out of range"));
  }
  if radius < 0.0 {
    return Err(CoreError.InvalidInput("radius out of range"));
  }
  var hits = search_range_scan(&eng.store, query, radius, limit, eng.metric);
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

// ---- Multi-collection recovery (D3) ----

// Recovery-time registry entry (ManifestInfo + cid + liveness).
pub type MetaEntry = {
  cid: Int;
  name: Str;
  alive: Bool;
  dim: Int;
  metric: DistanceMetric;
  kind: AnnIndexKind;
  m: Int;
  ef_construction: Int;
  ef_search: Int;
}

fn meta_find_cid(metas: &Vec[MetaEntry], cid: Int) -> Int {
  var i: Int = 0;
  while i < metas.len() {
    if metas[i].cid == cid { return i; }
    i = i + 1;
  }
  return -1;
}

fn meta_find_name(metas: &Vec[MetaEntry], name: Str) -> Int {
  var i: Int = 0;
  while i < metas.len() {
    if metas[i].name == name { return i; }
    i = i + 1;
  }
  return -1;
}

fn meta_upsert(metas: &mut Vec[MetaEntry], m: MetaEntry) {
  var idx = meta_find_cid(metas, m.cid);
  if idx < 0 {
    metas.push(m);
  } else {
    metas[idx] = m;
  }
}

fn meta_from_info(mi: &ManifestInfo, cid: Int) -> MetaEntry {
  return MetaEntry{
    cid: cid,
    name: mi.name,
    alive: true,
    dim: mi.dim,
    metric: mi.metric,
    kind: mi.kind,
    m: mi.m,
    ef_construction: mi.ef_construction,
    ef_search: mi.ef_search,
  };
}

// Replay a WAL across the collection registry: manifest records build the
// set (v1 legacy -> "default"/cid 1; v2 upsert; v3 drop), data records route
// by collection id when the log carries v2/v3 records (D3 strict mode) and
// land in the single collection otherwise (legacy logs, where the value
// field is not meaningful). A valid manifest file (`file_reg`) overrides
// configs by collection name -- with the D2 first-entry migration rule for
// single-collection logs. Returns an engine with the first alive collection
// active and a fresh checkpoint WAL carrying every alive collection.
fn engine_recover_registry(w: &WalWriter, dim: Int, metric: DistanceMetric, file_reg: &CollectionRegistry) -> VectorEngine {
  // 1. Metas from manifest records.
  var metas = Vec[MetaEntry].new();
  var strict: Bool = false;
  var i: Int = 0;
  while i < w.records.len() {
    if w.records[i].op == WalOpKind.ManifestUpdate {
      var mi = parse_manifest_info(&w.records[i].payload);
      if mi.valid {
        if mi.version == 1 {
          meta_upsert(&mut metas, meta_from_info(&mi, 1));
        } elif mi.version == 2 {
          strict = true;
          var cid2: Int = w.records[i].value;
          if cid2 < 1 { cid2 = 1; }
          meta_upsert(&mut metas, meta_from_info(&mi, cid2));
        } elif mi.version == 3 {
          strict = true;
          var di = meta_find_cid(&metas, w.records[i].value);
          if di >= 0 {
            var md = metas[di];
            md.alive = false;
            metas[di] = md;
          }
        }
      }
    }
    i = i + 1;
  }
  if metas.len() == 0 {
    var lm = MetaEntry{
      cid: 1,
      name: "default",
      alive: true,
      dim: dim,
      metric: metric,
      kind: AnnIndexKind.Flat,
      m: 16,
      ef_construction: 200,
      ef_search: 64,
    };
    metas.push(lm);
  }
  // 2. Manifest-file overrides (by name; D2 migration for single logs).
  if file_reg.valid && file_reg.entries.len() >= 1 {
    var fi: Int = 0;
    while fi < file_reg.entries.len() {
      var fe = file_reg.entries[fi];
      var oi = meta_find_name(&metas, fe.name);
      if oi < 0 && metas.len() == 1 { oi = 0; }
      if oi >= 0 {
        var mm = metas[oi];
        mm.name = fe.name;
        mm.dim = fe.dim;
        mm.metric = fe.metric;
        mm.kind = fe.kind;
        mm.m = fe.m;
        mm.ef_construction = fe.ef_construction;
        mm.ef_search = fe.ef_search;
        metas[oi] = mm;
      }
      fi = fi + 1;
    }
  }
  // 3. Per-collection stores + routed replay.
  var stores = Vec[VectorIndex].new();
  var pls = Vec[PayloadStore].new();
  var mi3: Int = 0;
  while mi3 < metas.len() {
    stores.push(index_new(metas[mi3].dim));
    pls.push(payload_store_new());
    mi3 = mi3 + 1;
  }
  var ri: Int = 0;
  while ri < w.records.len() {
    var op = w.records[ri].op;
    var si: Int = -1;
    if strict {
      si = meta_find_cid(&metas, w.records[ri].value);
      if si >= 0 && !metas[si].alive { si = -1; }
    } else {
      si = 0;
    }
    if si >= 0 {
      if op == WalOpKind.Insert {
        match vector_decode(&w.records[ri].payload) {
          Some(v) => {
            if v.dimension == metas[si].dim {
              index_add(&mut stores[si], w.records[ri].key, v);
            }
          }
          None => {}
        }
      } elif op == WalOpKind.Delete {
        index_remove(&mut stores[si], w.records[ri].key);
        payload_store_remove(&mut pls[si], w.records[ri].key);
      } elif op == WalOpKind.Update {
        match payload_decode(&w.records[ri].payload) {
          Some(p) => { payload_store_put(&mut pls[si], w.records[ri].key, p); }
          None => {}
        }
      }
    }
    ri = ri + 1;
  }
  // 4. Entries for every alive meta; the first alive becomes active.
  var eng = engine_new();
  var entries = Vec[CollectionEntry].new();
  var ai: Int = -1;
  var k: Int = 0;
  while k < metas.len() {
    var mk = metas[k];
    if mk.alive {
      var e = CollectionEntry{
        cid: mk.cid,
        name: mk.name,
        store: stores[k],
        payloads: pls[k],
        graph: hnsw_new(16, 4.0),
        index_kind: mk.kind,
        ann: AnnParams{ m: mk.m, ef_construction: mk.ef_construction, ef_search: mk.ef_search },
        dimension: mk.dim,
        metric: mk.metric,
      };
      var params = AnnParams{ m: mk.m, ef_construction: mk.ef_construction, ef_search: mk.ef_search };
      entry_apply_index(&mut e, mk.kind, params);
      if ai < 0 { ai = entries.len(); }
      entries.push(e);
    }
    k = k + 1;
  }
  eng.collections = entries;
  if ai >= 0 {
    load_active(&mut eng, ai);
  }
  // 5. Checkpoint: every alive collection's data + its v2 manifest.
  var out = wal_writer_resume(w.next_lsn);
  var c: Int = 0;
  while c < eng.collections.len() {
    var ce = eng.collections[c];
    var di2: Int = 0;
    while di2 < ce.store.ids.len() {
      wal_writer_append_payload(&mut out, WalOpKind.Insert, ce.store.ids[di2], ce.cid, vector_encode(&ce.store.vectors[di2]));
      di2 = di2 + 1;
    }
    var pi: Int = 0;
    while pi < ce.payloads.entries.len() {
      wal_writer_append_payload(&mut out, WalOpKind.Update, ce.payloads.entries[pi].id, ce.cid, payload_encode(&ce.payloads.entries[pi].payload));
      pi = pi + 1;
    }
    c = c + 1;
  }
  var c2: Int = 0;
  while c2 < eng.collections.len() {
    var ce2 = eng.collections[c2];
    var words2 = manifest_words(ce2.name, ce2.dimension, ce2.metric, ce2.index_kind, ce2.ann);
    wal_writer_append_payload(&mut out, WalOpKind.ManifestUpdate, 0, ce2.cid, words2);
    c2 = c2 + 1;
  }
  eng.wal = out;
  return eng;
}

// Rebuild an engine from its WAL: manifest records define the collection
// registry (legacy v1 -> "default"; no manifest -> caller config), data
// records replay into their collection, and a fresh checkpoint carries every
// alive collection. LSNs stay monotonic.
pub fn engine_recover(w: &WalWriter, dim: Int, metric: DistanceMetric) -> VectorEngine
  requires: dim > 0
{
  var empty_reg = CollectionRegistry{ valid: false, version: 0, entries: Vec[RegistryEntry].new() };
  return engine_recover_registry(w, dim, metric, &empty_reg);
}

// Open from disk (M-D2/D3): the manifest file's registry overrides per-
// collection configs by name (registry of record); without it (or when a
// name is absent) the in-WAL manifests govern, and the caller's dim/metric
// are the last resort for logs with no manifest at all.
pub fn engine_recover_file(w: &WalWriter, path: Str, dim: Int, metric: DistanceMetric) -> VectorEngine
  requires: dim > 0
{
  var reg = manifest_load(path);
  return engine_recover_registry(w, dim, metric, &reg);
}
