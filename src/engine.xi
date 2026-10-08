// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.engine

use xiom.math;
use xiom.num.float;
use xiom.string.slice;

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

// ---- Vector (from dense_vector.xi) ----
pub type Vector = {
  data: Vec[Float32];
  dimension: Int;
} derive[Clone]

pub fn Vector.new(dimension: Int) -> Vector
  requires: dimension > 0
  ensures: result.data.len() == dimension
{
  var data_vec = Vec[Float32].new();
  var i: Int = 0;
  while i < dimension {
    data_vec.push(0.0);
    i = i + 1;
  }
  return Vector{ data: data_vec, dimension: dimension };
}

pub fn Vector.set(index: Int, value: Float32)
  requires: index < dimension
{
  data[index] = value;
}

pub fn Vector.get(index: Int) -> Float32
  requires: index < dimension
{
  return data[index];
}

pub fn vector_dot(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  var sum: Float32 = 0.0;
  var i: Int = 0;
  while i < a.dimension {
    sum = sum + a.data[i] * b.data[i];
    i = i + 1;
  }
  return sum;
}

pub fn vector_magnitude(v: &Vector) -> Float32 {
  var sum_sq: Float32 = 0.0;
  var i: Int = 0;
  while i < v.dimension {
    sum_sq = sum_sq + v.data[i] * v.data[i];
    i = i + 1;
  }
  return (xiom.math.sqrt(sum_sq as Float64) as Float32);
}

// ---- DistanceMetric + distance functions (from metric.xi) ----
pub enum DistanceMetric {
  Cosine,
  DotProduct,
  Euclidean,
}

pub fn dot_product_distance(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  var sum: Float32 = 0.0;
  var i: Int = 0;
  while i < a.dimension {
    sum = sum + a.data[i] * b.data[i];
    i = i + 1;
  }
  return -sum;
}

pub fn cosine_distance(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  var dot: Float32 = 0.0;
  var mag_a: Float32 = 0.0;
  var mag_b: Float32 = 0.0;
  var i: Int = 0;
  while i < a.dimension {
    var ai = a.data[i];
    var bi = b.data[i];
    dot = dot + ai * bi;
    mag_a = mag_a + ai * ai;
    mag_b = mag_b + bi * bi;
    i = i + 1;
  }
  if mag_a == 0.0 || mag_b == 0.0 { return 1.0; }
  var similarity = dot / ((xiom.math.sqrt(mag_a as Float64) as Float32) * (xiom.math.sqrt(mag_b as Float64) as Float32));
  return 1.0 - similarity;
}

pub fn euclidean_distance(a: &Vector, b: &Vector) -> Float32
  requires: a.dimension == b.dimension
{
  var sum_sq: Float32 = 0.0;
  var i: Int = 0;
  while i < a.dimension {
    var diff = a.data[i] - b.data[i];
    sum_sq = sum_sq + diff * diff;
    i = i + 1;
  }
  return (xiom.math.sqrt(sum_sq as Float64) as Float32);
}

pub fn vector_distance(a: &Vector, b: &Vector, metric: DistanceMetric) -> Float32
  requires: a.dimension == b.dimension
{
  match metric {
    Cosine => cosine_distance(a, b),
    DotProduct => dot_product_distance(a, b),
    Euclidean => euclidean_distance(a, b),
  }
}

// ---- Payload + metadata filtering (Phase 3) ----
// Tagged scalar carried by a payload field.
pub enum FieldValue {
  IntVal(v: Int),
  FloatVal(v: Float32),
  TextVal(v: Str),
  BoolVal(v: Bool),
}

pub type PayloadField = {
  key: Str;
  value: FieldValue;
}

pub type Payload = {
  fields: Vec[PayloadField];
}

pub fn payload_new() -> Payload {
  var fields = Vec[PayloadField].new();
  return Payload{ fields: fields };
}

// Set or OVERWRITE a field (linear scan; a sorted key index is a later
// Phase 3 deliverable).
pub fn payload_set(p: &mut Payload, key: Str, value: FieldValue) {
  var i: Int = 0;
  while i < p.fields.len() {
    if p.fields[i].key == key {
      p.fields[i].value = value;
      return;
    }
    i = i + 1;
  }
  p.fields.push(PayloadField{ key: key, value: value });
}

pub fn payload_has(p: &Payload, key: Str) -> Bool {
  var i: Int = 0;
  while i < p.fields.len() {
    if p.fields[i].key == key { return true; }
    i = i + 1;
  }
  return false;
}

pub fn payload_get(p: &Payload, key: Str) -> Option[FieldValue] {
  var i: Int = 0;
  while i < p.fields.len() {
    if p.fields[i].key == key { return Some(p.fields[i].value); }
    i = i + 1;
  }
  return None;
}

pub fn payload_len(p: &Payload) -> Int {
  return p.fields.len();
}

pub fn field_value_kind(v: &FieldValue) -> Str {
  match v {
    IntVal(_) => "int",
    FloatVal(_) => "float",
    TextVal(_) => "text",
    BoolVal(_) => "bool",
  }
}

// Exact equality within one type; cross-type comparisons are false.
pub fn field_value_eq(a: &FieldValue, b: &FieldValue) -> Bool {
  match a {
    IntVal(av) => {
      match b { IntVal(bv) => { return av == bv; } _ => { return false; } }
    }
    FloatVal(av) => {
      match b { FloatVal(bv) => { return av == bv; } _ => { return false; } }
    }
    TextVal(av) => {
      match b { TextVal(bv) => { return av == bv; } _ => { return false; } }
    }
    BoolVal(av) => {
      match b { BoolVal(bv) => { return av == bv; } _ => { return false; } }
    }
  }
}

// Numeric view for Range: Int promotes to Float32, non-numeric -> None.
pub fn field_value_as_float(v: &FieldValue) -> Option[Float32] {
  match v {
    FloatVal(f) => { return Some(f); }
    IntVal(i) => { return Some(i as Float32); }
    _ => { return None; }
  }
}

// ---- Payload WAL codec (durable metadata) ----
// Word layout: [version=1, field_count,
//   (key_len, key_bytes...), kind, value_words...
// kind 1=int (v), 2=float (f64 bit pattern of the f32), 3=text (len, bytes),
// 4=bool (0|1)]. Decode is strict; malformed -> None (torn-record tolerance).
fn push_str_words(out: &mut Vec[Int], s: Str) {
  var bytes = slice.str_bytes(s);
  out.push(bytes.len());
  var i: Int = 0;
  while i < bytes.len() {
    out.push(bytes[i] as Int);
    i = i + 1;
  }
}

pub fn payload_encode(p: &Payload) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(1);
  out.push(p.fields.len());
  var i: Int = 0;
  while i < p.fields.len() {
    push_str_words(&mut out, p.fields[i].key);
    var fv = p.fields[i].value;
    match fv {
      IntVal(v) => { out.push(1); out.push(v); }
      FloatVal(f) => { out.push(2); out.push(float.float_bits(f as Float64)); }
      TextVal(t) => { out.push(3); push_str_words(&mut out, t); }
      BoolVal(b) => {
        out.push(4);
        if b { out.push(1); } else { out.push(0); }
      }
    }
    i = i + 1;
  }
  return out;
}

pub fn payload_decode(words: &Vec[Int]) -> Option[Payload] {
  if words.len() < 2 { return None; }
  if words[0] != 1 { return None; }
  var count = words[1];
  if count < 0 { return None; }
  var out = payload_new();
  var pos: Int = 2;
  var i: Int = 0;
  while i < count {
    if pos >= words.len() { return None; }
    var klen = words[pos];
    pos = pos + 1;
    if klen < 0 || pos + klen > words.len() { return None; }
    var kb = Vec[UInt8].new();
    var j: Int = 0;
    while j < klen {
      kb.push(words[pos + j] as UInt8);
      j = j + 1;
    }
    pos = pos + klen;
    var key = Str::from_utf8(kb);
    if pos >= words.len() { return None; }
    var kind = words[pos];
    pos = pos + 1;
    if kind == 1 {
      if pos >= words.len() { return None; }
      var iv = words[pos];
      pos = pos + 1;
      payload_set(&mut out, key, FieldValue.IntVal(iv));
    } elif kind == 2 {
      if pos >= words.len() { return None; }
      var bits = words[pos];
      pos = pos + 1;
      payload_set(&mut out, key, FieldValue.FloatVal(float.bits_to_float(bits) as Float32));
    } elif kind == 3 {
      if pos >= words.len() { return None; }
      var tlen = words[pos];
      pos = pos + 1;
      if tlen < 0 || pos + tlen > words.len() { return None; }
      var tb = Vec[UInt8].new();
      var k: Int = 0;
      while k < tlen {
        tb.push(words[pos + k] as UInt8);
        k = k + 1;
      }
      pos = pos + tlen;
      payload_set(&mut out, key, FieldValue.TextVal(Str::from_utf8(tb)));
    } elif kind == 4 {
      if pos >= words.len() { return None; }
      var bv = words[pos];
      pos = pos + 1;
      payload_set(&mut out, key, FieldValue.BoolVal(bv != 0));
    } else {
      return None;
    }
    i = i + 1;
  }
  return Some(out);
}

pub enum FilterExpr {
  Eq(field: Str, value: FieldValue),
  Range(field: Str, lo: Float32, hi: Float32),
  Exists(field: Str),
  In(field: Str, values: Vec[FieldValue]),
  And(clauses: Vec[FilterExpr]),
  Or(clauses: Vec[FilterExpr]),
  Not(clauses: Vec[FilterExpr]),
}

pub fn filter_eq(field: Str, value: FieldValue) -> FilterExpr {
  return FilterExpr.Eq(field, value);
}

pub fn filter_range(field: Str, lo: Float32, hi: Float32) -> FilterExpr {
  return FilterExpr.Range(field, lo, hi);
}

pub fn filter_exists(field: Str) -> FilterExpr {
  return FilterExpr.Exists(field);
}

pub fn filter_in(field: Str, values: Vec[FieldValue]) -> FilterExpr {
  return FilterExpr.In(field, values);
}

pub fn filter_and(clauses: Vec[FilterExpr]) -> FilterExpr {
  return FilterExpr.And(clauses);
}

pub fn filter_or(clauses: Vec[FilterExpr]) -> FilterExpr {
  return FilterExpr.Or(clauses);
}

pub fn filter_not(clause: FilterExpr) -> FilterExpr {
  var clauses = Vec[FilterExpr].new();
  clauses.push(clause);
  return FilterExpr.Not(clauses);
}

// Evaluate a filter against a point payload. Value predicates on a missing
// field are false; boolean combinators keep their structure with the empty
// semantics: And([]) = true, Or([]) = false, Not([]) = true.
pub fn filter_matches(expr: &FilterExpr, p: &Payload) -> Bool {
  match expr {
    Eq(field, value) => {
      match payload_get(p, field) {
        Some(fv) => { return field_value_eq(&fv, &value); }
        None => { return false; }
      }
    }
    Range(field, lo, hi) => {
      match payload_get(p, field) {
        Some(fv) => {
          match field_value_as_float(&fv) {
            Some(f) => { return f >= lo && f <= hi; }
            None => { return false; }
          }
        }
        None => { return false; }
      }
    }
    Exists(field) => { return payload_has(p, field); }
    In(field, values) => {
      match payload_get(p, field) {
        Some(fv) => {
          var i: Int = 0;
          while i < values.len() {
            if field_value_eq(&fv, &values[i]) { return true; }
            i = i + 1;
          }
          return false;
        }
        None => { return false; }
      }
    }
    And(clauses) => {
      var i: Int = 0;
      while i < clauses.len() {
        if !filter_matches(&clauses[i], p) { return false; }
        i = i + 1;
      }
      return true;
    }
    Or(clauses) => {
      var i: Int = 0;
      while i < clauses.len() {
        if filter_matches(&clauses[i], p) { return true; }
        i = i + 1;
      }
      return false;
    }
    Not(clauses) => {
      if clauses.len() == 0 { return true; }
      return !filter_matches(&clauses[0], p);
    }
  }
}

// Same boolean structure as filter_matches but for a point with NO payload:
// every value predicate is false; combinators compose (And([]) = true etc.).
fn filter_matches_empty(expr: &FilterExpr) -> Bool {
  match expr {
    And(clauses) => {
      var i: Int = 0;
      while i < clauses.len() {
        if !filter_matches_empty(&clauses[i]) { return false; }
        i = i + 1;
      }
      return true;
    }
    Or(clauses) => {
      var i: Int = 0;
      while i < clauses.len() {
        if filter_matches_empty(&clauses[i]) { return true; }
        i = i + 1;
      }
      return false;
    }
    Not(clauses) => {
      if clauses.len() == 0 { return true; }
      return !filter_matches_empty(&clauses[0]);
    }
    _ => { return false; }
  }
}

// ---- Neighbor (from neighbor.xi) ----
pub type Neighbor = {
  id: UInt64;
  distance: Float32;
} derive[Clone]

pub fn neighbor_new(id: UInt64, distance: Float32) -> Neighbor {
  return Neighbor{ id: id, distance: distance };
}

// ---- VectorIndex (from vector_store.xi) ----
pub type VectorIndex = {
  vectors: Vec[Vector];
  ids: Vec[Int];
  dim: Int;
}

pub fn index_new(dim: Int) -> VectorIndex
  requires: dim > 0
{
  return VectorIndex{
    vectors: Vec[Vector].new(),
    ids: Vec[Int].new(),
    dim: dim,
  };
}

pub fn index_add(idx: &mut VectorIndex, id: Int, vec: Vector) -> Bool
  requires: idx.dim == vec.dimension
{
  var i: Int = 0;
  while i < idx.ids.len() {
    if idx.ids[i] == id {
      return false;
    }
    i = i + 1;
  }
  idx.vectors.push(vec);
  idx.ids.push(id);
  return true;
}

pub fn index_remove(idx: &mut VectorIndex, id: Int) -> Bool {
  var pos: Int = -1;
  var i: Int = 0;
  while i < idx.ids.len() {
    if idx.ids[i] == id {
      pos = i;
    }
    i = i + 1;
  }
  if pos == -1 {
    return false;
  }
  var last: Int = idx.ids.len() - 1;
  idx.vectors[pos] = idx.vectors[last];
  idx.ids[pos] = idx.ids[last];
  idx.vectors.pop();
  idx.ids.pop();
  return true;
}

pub fn index_get(idx: &VectorIndex, id: Int) -> Option[Vector] {
  var i: Int = 0;
  while i < idx.ids.len() {
    if idx.ids[i] == id {
      return Some(idx.vectors[i]);
    }
    i = i + 1;
  }
  return None;
}

pub fn index_size(idx: &VectorIndex) -> Int {
  return idx.ids.len();
}

// ---- Payload store: point id -> Payload (linear scan, swap-remove) ----
pub type PayloadEntry = {
  id: Int;
  payload: Payload;
}

pub type PayloadStore = {
  entries: Vec[PayloadEntry];
}

pub fn payload_store_new() -> PayloadStore {
  var entries = Vec[PayloadEntry].new();
  return PayloadStore{ entries: entries };
}

// Insert or replace the payload for `id`.
pub fn payload_store_put(s: &mut PayloadStore, id: Int, payload: Payload) {
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id {
      s.entries[i].payload = payload;
      return;
    }
    i = i + 1;
  }
  s.entries.push(PayloadEntry{ id: id, payload: payload });
}

pub fn payload_store_get(s: &PayloadStore, id: Int) -> Option[Payload] {
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id { return Some(s.entries[i].payload); }
    i = i + 1;
  }
  return None;
}

pub fn payload_store_remove(s: &mut PayloadStore, id: Int) -> Bool {
  var pos: Int = -1;
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id { pos = i; }
    i = i + 1;
  }
  if pos == -1 { return false; }
  var last: Int = s.entries.len() - 1;
  s.entries[pos] = s.entries[last];
  s.entries.pop();
  return true;
}

pub fn payload_store_len(s: &PayloadStore) -> Int {
  return s.entries.len();
}

// Filter check for a point id: uses its payload when present, otherwise the
// empty-payload semantics (value predicates false).
pub fn payload_store_matches(s: &PayloadStore, id: Int, expr: &FilterExpr) -> Bool {
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id {
      return filter_matches(expr, &s.entries[i].payload);
    }
    i = i + 1;
  }
  return filter_matches_empty(expr);
}

// ---- Durable vector codec: WAL payload = [dim, bits0, bits1, ...] ----
// Float32 -> Float64 -> IEEE-754 bits (exact: every Float32 is exactly
// representable in Float64; `float_bits` lowers to a true LLVM bitcast
// since v0.64.0/m194).
pub fn vector_encode(v: &Vector) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(v.dimension);
  var i: Int = 0;
  while i < v.dimension {
    out.push(float.float_bits(v.data[i] as Float64));
    i = i + 1;
  }
  return out;
}

// Rebuild a vector from a WAL payload; None on any malformed shape (short
// buffer, invalid dim, length mismatch) so recovery can skip torn records.
pub fn vector_decode(payload: &Vec[Int]) -> Option[Vector] {
  if payload.len() < 1 { return None; }
  var dim = payload[0];
  if !is_valid_dimension(dim) { return None; }
  if payload.len() != dim + 1 { return None; }
  var v = Vector.new(dim);
  var i: Int = 0;
  while i < dim {
    v.data[i] = float.bits_to_float(payload[i + 1]) as Float32;
    i = i + 1;
  }
  return Some(v);
}

// ---- SearchResult + search (from search_service.xi) ----
pub type SearchResult = {
  id: Int;
  distance: Float32;
} derive[Clone]

// Ok-payload wrapper for search results. Rationale: on compiler v0.64.0 a
// Result/Option whose payload is DIRECTLY a Vec[T] with non-scalar T loses
// element field data for the caller (len survives, fields read as zero /
// address-like; XVC-C-04, repro docs/repro/xv-result-vec-struct/).
// Wrapping the Vec in a struct preserves the payload. Unwrap this type when
// the compiler finding is fixed.
pub type SearchHits = {
  items: Vec[SearchResult];
}

// Push a hit into a distance-sorted bounded list (shared by the exact and
// filtered scans): insert sorted, then trim to k.
fn results_push_bounded(results: &mut Vec[SearchResult], item: SearchResult, k: Int) {
  results.push(item);
  var pos: Int = results.len() - 1;
  while pos > 0 && results[pos - 1].distance > results[pos].distance {
    var tmp = results[pos];
    results[pos] = results[pos - 1];
    results[pos - 1] = tmp;
    pos = pos - 1;
  }
  if results.len() > k {
    results.pop();
  }
}

pub fn search_knn(idx: &VectorIndex, query: &Vector, k: Int, metric: DistanceMetric) -> Vec[SearchResult]
  requires: k > 0
  requires: idx.dim == query.dimension
  ensures: result.len() <= k
{
  var results = Vec[SearchResult].new();
  var i: Int = 0;
  var total: Int = idx.ids.len();
  while i < total {
    var dist = vector_distance(&idx.vectors[i], query, metric);
    results_push_bounded(&mut results, SearchResult{ id: idx.ids[i], distance: dist }, k);
    i = i + 1;
  }
  return results;
}

// Filtered exact scan: evaluate the filter per candidate BEFORE the distance
// compute (a pre-filter plan for the exact engine; a selectivity-based
// pre/post planner is a later Phase 3 deliverable).
pub fn search_knn_filtered(idx: &VectorIndex, payloads: &PayloadStore, query: &Vector, k: Int, metric: DistanceMetric, filter: &FilterExpr) -> Vec[SearchResult]
  requires: k > 0
  requires: idx.dim == query.dimension
  ensures: result.len() <= k
{
  var results = Vec[SearchResult].new();
  var i: Int = 0;
  var total: Int = idx.ids.len();
  while i < total {
    if payload_store_matches(payloads, idx.ids[i], filter) {
      var dist = vector_distance(&idx.vectors[i], query, metric);
      results_push_bounded(&mut results, SearchResult{ id: idx.ids[i], distance: dist }, k);
    }
    i = i + 1;
  }
  return results;
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