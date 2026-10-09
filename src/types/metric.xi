// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.types.metric

// Distance metrics over dense vectors + dispatch.
// Extracted from the consolidated engine (post-AUDIT module tree).

use xiom.math;
use xiom.vector.types.dense_vector;

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
  var similarity = dot / ((math.sqrt(mag_a as Float64) as Float32) * (math.sqrt(mag_b as Float64) as Float32));
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
  return (math.sqrt(sum_sq as Float64) as Float32);
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

// Stable wire/on-disk codes for the metric: 1 = Cosine, 2 = DotProduct,
// 3 = Euclidean. Shared by the WAL collection-manifest record and the
// durable manifest file (D2); the codes are part of the on-disk format.
pub fn metric_code(m: DistanceMetric) -> Int {
  if m == DistanceMetric.Cosine { return 1; }
  if m == DistanceMetric.DotProduct { return 2; }
  return 3;
}

pub fn metric_from_code(c: Int) -> DistanceMetric {
  if c == 1 { return DistanceMetric.Cosine; }
  if c == 2 { return DistanceMetric.DotProduct; }
  return DistanceMetric.Euclidean;
}
