// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.storage.vector_store

// Flat columnar vector store (insert/search/delete by id) + the durable
// vector WAL codec. Extracted from the consolidated engine (post-AUDIT
// module tree).

use xiom.num.float;
use xiom.vector.types.dense_vector;
use xiom.vector.types.dimension;

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
  if !dimension.dimension_is_valid(dim) { return None; }
  if payload.len() != dim + 1 { return None; }
  var v = Vector.new(dim);
  var i: Int = 0;
  while i < dim {
    v.data[i] = float.bits_to_float(payload[i + 1]) as Float32;
    i = i + 1;
  }
  return Some(v);
}
