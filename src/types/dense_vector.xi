// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.types.dense_vector

// Dense vector primitive: fixed-dimension Float32 values + dot/magnitude.
// Extracted from the consolidated engine (post-AUDIT module tree).

use xiom.math;

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
  return (math.sqrt(sum_sq as Float64) as Float32);
}
