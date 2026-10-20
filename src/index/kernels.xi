// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// P3 kernel seam: distance/dot/magnitude dispatch behind the xiom.vectors
// contract. Kind 0 is the vendored scalar surface (the exact default); kind 1
// is an unrolled same-order implementation that is bit-identical to the
// scalar path and exists to prove the seam + record a benchmark delta. A
// future accelerated binding (e.g. a Float32 BLAS/eigen wrapper) plugs in as
// another kind; OpenBLAS 0.1.1 is Float64/native and is deliberately not in
// this Float32 hot path.
//
// The seam is engine-internal (xiom.vector.index.kernels); consumers keep
// calling the xiom.vectors surface. `kernels_install` is a runtime switch,
// not a per-call allocation; the default is always scalar.

module xiom.vector.index.kernels

use xiom.math;
use xiom.vector.primitives;

// Scalar-only module global (C-19/C-20 fixed on v0.64.8): 0 = scalar,
// 1 = unrolled-same-order.
var G_KERNEL: Int = 0;

pub fn kernels_install(kind: Int) {
  if kind == 1 { G_KERNEL = 1; } else { G_KERNEL = 0; }
}

pub fn kernels_kind() -> Int {
  return G_KERNEL;
}

// ---- kind 1: unrolled, same accumulation order --------------------------

fn dot_u(a: &Vector, b: &Vector) -> Float32 {
  var sum: Float32 = 0.0;
  var i: Int = 0;
  let n = a.dimension;
  while i + 3 < n {
    sum = sum + a.data[i] * b.data[i];
    sum = sum + a.data[i + 1] * b.data[i + 1];
    sum = sum + a.data[i + 2] * b.data[i + 2];
    sum = sum + a.data[i + 3] * b.data[i + 3];
    i = i + 4;
  }
  while i < n {
    sum = sum + a.data[i] * b.data[i];
    i = i + 1;
  }
  return sum;
}

fn magnitude_u(v: &Vector) -> Float32 {
  var sum_sq: Float32 = 0.0;
  var i: Int = 0;
  let n = v.dimension;
  while i + 3 < n {
    sum_sq = sum_sq + v.data[i] * v.data[i];
    sum_sq = sum_sq + v.data[i + 1] * v.data[i + 1];
    sum_sq = sum_sq + v.data[i + 2] * v.data[i + 2];
    sum_sq = sum_sq + v.data[i + 3] * v.data[i + 3];
    i = i + 4;
  }
  while i < n {
    sum_sq = sum_sq + v.data[i] * v.data[i];
    i = i + 1;
  }
  return (math.sqrt(sum_sq as Float64) as Float32);
}

fn dot_distance_u(a: &Vector, b: &Vector) -> Float32 {
  return 0.0 - dot_u(a, b);
}

fn euclidean_u(a: &Vector, b: &Vector) -> Float32 {
  var sum_sq: Float32 = 0.0;
  var i: Int = 0;
  let n = a.dimension;
  while i + 3 < n {
    var d0 = a.data[i] - b.data[i];
    sum_sq = sum_sq + d0 * d0;
    var d1 = a.data[i + 1] - b.data[i + 1];
    sum_sq = sum_sq + d1 * d1;
    var d2 = a.data[i + 2] - b.data[i + 2];
    sum_sq = sum_sq + d2 * d2;
    var d3 = a.data[i + 3] - b.data[i + 3];
    sum_sq = sum_sq + d3 * d3;
    i = i + 4;
  }
  while i < n {
    var d = a.data[i] - b.data[i];
    sum_sq = sum_sq + d * d;
    i = i + 1;
  }
  return (math.sqrt(sum_sq as Float64) as Float32);
}

fn cosine_u(a: &Vector, b: &Vector) -> Float32 {
  var dot: Float32 = 0.0;
  var mag_a: Float32 = 0.0;
  var mag_b: Float32 = 0.0;
  var i: Int = 0;
  let n = a.dimension;
  while i + 3 < n {
    var a0 = a.data[i]; var b0 = b.data[i];
    dot = dot + a0 * b0; mag_a = mag_a + a0 * a0; mag_b = mag_b + b0 * b0;
    var a1 = a.data[i + 1]; var b1 = b.data[i + 1];
    dot = dot + a1 * b1; mag_a = mag_a + a1 * a1; mag_b = mag_b + b1 * b1;
    var a2 = a.data[i + 2]; var b2 = b.data[i + 2];
    dot = dot + a2 * b2; mag_a = mag_a + a2 * a2; mag_b = mag_b + b2 * b2;
    var a3 = a.data[i + 3]; var b3 = b.data[i + 3];
    dot = dot + a3 * b3; mag_a = mag_a + a3 * a3; mag_b = mag_b + b3 * b3;
    i = i + 4;
  }
  while i < n {
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

fn distance_u(a: &Vector, b: &Vector, metric: DistanceMetric) -> Float32 {
  match metric {
    DistanceMetric.Cosine => cosine_u(a, b),
    DistanceMetric.DotProduct => dot_distance_u(a, b),
    DistanceMetric.Euclidean => euclidean_u(a, b),
  }
}

// ---- public seam ---------------------------------------------------------

pub fn kernels_dot(a: &Vector, b: &Vector) -> Float32 {
  if G_KERNEL == 1 { return dot_u(a, b); }
  return vector_dot(a, b);
}

pub fn kernels_magnitude(v: &Vector) -> Float32 {
  if G_KERNEL == 1 { return magnitude_u(v); }
  return vector_magnitude(v);
}

pub fn kernels_distance(a: &Vector, b: &Vector, metric: DistanceMetric) -> Float32 {
  if G_KERNEL == 1 { return distance_u(a, b, metric); }
  return vector_distance(a, b, metric);
}

// Direct-call variants for hot loops that branch once per scan (the local
// `alt` boolean) instead of paying the seam dispatch per distance.
pub fn kernels_scalar_distance(a: &Vector, b: &Vector, metric: DistanceMetric) -> Float32 {
  return vector_distance(a, b, metric);
}

pub fn kernels_alt_distance(a: &Vector, b: &Vector, metric: DistanceMetric) -> Float32 {
  return distance_u(a, b, metric);
}
