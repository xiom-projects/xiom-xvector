// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.core.shim

// Local xiom-core stand-ins: error type, metrics counter, the shared id
// vocabulary, and the validity predicates used by contracts/runtime guards.
// The porter flow later maps these onto the real xiom.core package (same
// surface: error - ids - contracts - metrics). Extracted from the
// consolidated engine in the final extraction wave.

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

// ---- Validity predicates (from xiom.core.contracts) ----
pub fn is_valid_dimension(dim: Int) -> Bool {
  return dim >= 1 && dim <= 65536;
}

pub fn is_valid_top_k(k: Int) -> Bool {
  return k >= 1 && k <= 10000;
}
