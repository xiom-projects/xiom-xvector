// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.engine

use xiom.math;
use xiom.num.float;
use xiom.string.slice;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
use xiom.vector.payload.filter_eval;
use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;
use xiom.vector.storage.vector_store;
use xiom.vector.query.search_service;

// ============================================================================
// XIOM-Vector: Consolidated Engine -- Vector + Distances + Index + WAL + API
// ============================================================================

// ---- Inline CoreError (from xiom.core.error) ----
pub enum CoreError {
  NotFound,
  InvalidInput(msg: Str),
  OutOfBounds,
  Corruption(msg: Str),
  IOFailure(msg: Str),
  Unsupported(msg: Str),
  CapacityExceeded,
  InvalidState(msg: Str),
  ChecksumMismatch,
  VersionMismatch,
}

// ---- Inline WalOpKind, WalRecord, WalWriter (from xiom.core.wal) ----
pub enum WalOpKind {
  Insert,
  Update,
  Delete,
  SegmentSeal,
  ManifestUpdate,
  Checkpoint,
  SnapshotMarker,
}

pub type WalRecord = {
  lsn: Int;
  op: WalOpKind;
  key: Int;
  value: Int;
  payload: Vec[Int];
  timestamp: Int;
}

pub type WalWriter = {
  records: Vec[WalRecord];
  next_lsn: Int;
  synced_lsn: Int;
}

pub fn wal_writer_new() -> WalWriter {
  var records = Vec[WalRecord].new();
  return WalWriter{ records: records, next_lsn: 1, synced_lsn: 0 };
}

pub fn wal_writer_append(w: &mut WalWriter, op: WalOpKind, key: Int, value: Int) -> Int {
  var assigned = w.next_lsn;
  var payload = Vec[Int].new();
  var rec = WalRecord{
    lsn: assigned, op: op, key: key, value: value, payload: payload, timestamp: 0,
  };
  w.records.push(rec);
  w.next_lsn = w.next_lsn + 1;
  return assigned;
}

pub fn wal_writer_current_lsn(w: &WalWriter) -> Int {
  return w.next_lsn - 1;
}

pub fn wal_writer_flush(w: &mut WalWriter) -> Bool {
  w.synced_lsn = w.next_lsn - 1;
  return true;
}

// Append a record carrying an opaque payload (used for encoded vectors).
// key = point id, value = collection id (recovery replays by key).
pub fn wal_writer_append_payload(w: &mut WalWriter, op: WalOpKind, key: Int, value: Int, payload: Vec[Int]) -> Int {
  var assigned = w.next_lsn;
  var rec = WalRecord{
    lsn: assigned, op: op, key: key, value: value, payload: payload, timestamp: 0,
  };
  w.records.push(rec);
  w.next_lsn = w.next_lsn + 1;
  return assigned;
}

// Resume a WAL after recovery: empty record buffer, LSN continuity preserved
// so post-recovery appends never reuse an LSN.
pub fn wal_writer_resume(next_lsn: Int) -> WalWriter {
  var records = Vec[WalRecord].new();
  return WalWriter{ records: records, next_lsn: next_lsn, synced_lsn: next_lsn - 1 };
}

// Compacted checkpoint log: re-encode every live point of `idx` as an Insert
// record and every payload as an Update record, with fresh LSNs continuing
// after `w`. The returned log alone reconstructs the store + metadata, so a
// reopened engine can itself be reopened. This is the recovery-time
// compaction step; a durable manifest (Phase 2) will later persist it
// instead of rebuilding on every open.
pub fn wal_writer_checkpoint_from(w: &WalWriter, idx: &VectorIndex, payloads: &PayloadStore) -> WalWriter {
  var out = wal_writer_resume(w.next_lsn);
  var i: Int = 0;
  while i < idx.ids.len() {
    wal_writer_append_payload(&mut out, WalOpKind.Insert, idx.ids[i], 1, vector_encode(&idx.vectors[i]));
    i = i + 1;
  }
  var j: Int = 0;
  while j < payloads.entries.len() {
    wal_writer_append_payload(&mut out, WalOpKind.Update, payloads.entries[j].id, 1, payload_encode(&payloads.entries[j].payload));
    j = j + 1;
  }
  return out;
}

// ---- Inline Counter (from xiom.core.metrics) ----
pub type Counter = {
  name: Str;
  value: Int;
}

pub fn counter_new(name: Str) -> Counter {
  return Counter{ name: name, value: 0 };
}

pub fn counter_inc(c: &mut Counter) {
  c.value = c.value + 1;
}

// ---- Inline CollectionId, VectorId, SegmentId (from xiom.core.ids) ----
pub type CollectionId = { value: Int; } derive[Clone, Eq]
pub type VectorId = { value: Int; } derive[Clone, Eq]
pub type SegmentId = { value: Int; } derive[Clone, Eq]

pub fn collection_id(v: Int) -> CollectionId {
  return CollectionId{ value: v };
}

pub fn vector_id(v: Int) -> VectorId {
  return VectorId{ value: v };
}

pub fn vector_id_value(id: &VectorId) -> Int {
  return id.value;
}

pub fn segment_id(v: Int) -> SegmentId {
  return SegmentId{ value: v };
}

pub fn segment_id_eq(a: &SegmentId, b: &SegmentId) -> Bool {
  return a.value == b.value;
}

// ---- Validity predicates ----
pub fn is_valid_dimension(dim: Int) -> Bool {
  return dim >= 1 && dim <= 65536;
}

pub fn is_valid_top_k(k: Int) -> Bool {
  return k >= 1 && k <= 10000;
}

// ---- Write-ahead events (inline, from write_ahead_events.xi) ----
// Record layout for vectors: key = point id, value = collection id,
// payload = encoded vector ([dim, bits...]).
pub fn log_upsert(w: &mut WalWriter, collection: Int, point: Int, payload: Vec[Int]) -> Int {
  return wal_writer_append_payload(w, WalOpKind.Insert, point, collection, payload);
}

pub fn log_delete(w: &mut WalWriter, collection: Int, point: Int) -> Int {
  return wal_writer_append(w, WalOpKind.Delete, point, collection);
}

// Metadata update record: key = point id, payload = encoded Payload
// (payload_encode). WalOpKind.Update is the metadata record kind.
pub fn log_payload_set(w: &mut WalWriter, collection: Int, point: Int, words: Vec[Int]) -> Int {
  return wal_writer_append_payload(w, WalOpKind.Update, point, collection, words);
}

// ---- Recovery: replay a WAL into a fresh store + payload store ----
// Replay in LSN order: Insert -> store, Delete -> store+payload removal,
// Update -> payload set/overwrite. Malformed record payloads are skipped
// (torn-tail tolerance). Records of any other kind are ignored for now.
pub type RecoveredState = {
  store: VectorIndex;
  payloads: PayloadStore;
}

pub fn recover_state(w: &WalWriter, dim: Int) -> RecoveredState
  requires: dim > 0
{
  var idx = index_new(dim);
  var pls = payload_store_new();
  var i: Int = 0;
  while i < w.records.len() {
    var op = w.records[i].op;
    var key = w.records[i].key;
    match op {
      Insert => {
        match vector_decode(&w.records[i].payload) {
          Some(v) => {
            if v.dimension == dim { index_add(&mut idx, key, v); }
          }
          None => {}
        }
      }
      Delete => {
        index_remove(&mut idx, key);
        payload_store_remove(&mut pls, key);
      }
      Update => {
        match payload_decode(&w.records[i].payload) {
          Some(p) => { payload_store_put(&mut pls, key, p); }
          None => {}
        }
      }
      _ => {}
    }
    i = i + 1;
  }
  return RecoveredState{ store: idx, payloads: pls };
}

pub fn recover_store(w: &WalWriter, dim: Int) -> VectorIndex
  requires: dim > 0
{
  var st = recover_state(w, dim);
  return st.store;
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

// ---- VectorEngine (from engine.xi) ----
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

pub fn engine_size(eng: &VectorEngine) -> Int {
  return index_size(&eng.store);
}

pub fn engine_durable_lsn(eng: &VectorEngine) -> Int {
  return wal_writer_current_lsn(&eng.wal);
}

// ---- Vector API (from api/vector_api.xi) ----
pub fn create_collection(eng: &mut VectorEngine, dim: Int, metric: DistanceMetric) -> Result[CollectionId, CoreError] {
  return engine_create_collection(eng, dim, metric);
}

pub fn upsert(eng: &mut VectorEngine, point: Int, vec: Vector) -> Result[Bool, CoreError] {
  return engine_upsert(eng, point, vec);
}

pub fn search(eng: &VectorEngine, query: &Vector, k: Int) -> Result[SearchHits, CoreError] {
  return engine_search(eng, query, k);
}

pub fn delete_point(eng: &mut VectorEngine, point: Int) -> Result[Bool, CoreError] {
  return engine_delete(eng, point);
}

pub fn get_point(eng: &VectorEngine, point: Int) -> Option[Vector] {
  return index_get(&eng.store, point);
}

pub fn set_payload(eng: &mut VectorEngine, point: Int, payload: Payload) -> Result[Bool, CoreError] {
  return engine_set_payload(eng, point, payload);
}

pub fn get_payload(eng: &VectorEngine, point: Int) -> Option[Payload] {
  return engine_get_payload(eng, point);
}

pub fn search_filtered(eng: &VectorEngine, query: &Vector, k: Int, filter: &FilterExpr) -> Result[SearchHits, CoreError] {
  return engine_search_filtered(eng, query, k, filter);
}