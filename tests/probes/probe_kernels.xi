// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// P3 kernel-seam gate: the default (scalar) and the unrolled-same-order
// backend are bit-identical for dot/magnitude/distance over all three
// metrics, the install/restore switch works, and a bounded microbenchmark
// records scalar vs alternate ns/op for dims 128 and 768. The alternate is
// not an approximate tier; it exists to prove the seam and record the delta.
//
// Exit = failed checks (speed is recorded, not asserted).

module probe_kernels

use xiom.io;
use xiom.convert;
use xiom.time;
use xiom.vector.primitives;
use xiom.vector.index.kernels;

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  if num < 0 { return "-" + int_to_str(0 - num); }
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  return out;
}

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn lcg_next(state: &mut Int) -> Float32 {
  state = (state * 1103515245 + 12345) % 2147483647;
  if state < 0 { state = 0 - state; }
  return (state as Float32) / 2147483647.0;
}

fn make_vectors(count: Int, dim: Int) -> Vec[Vector] {
  var out = Vec[Vector].new();
  var state: Int = 777;
  var i: Int = 0;
  while i < count {
    var v = Vector.new(dim);
    var d: Int = 0;
    while d < dim {
      v.set(d, lcg_next(&mut state));
      d = d + 1;
    }
    out.push(v);
    i = i + 1;
  }
  return out;
}

type Bench = {
  ms: Int;
  checksum: Float32;
}

fn bench_dim(vecs: &Vec[Vector], kind: Int, iters: Int) -> Bench {
  kernels.kernels_install(0);
  var checksum: Float32 = 0.0;
  let t0 = time.monotonic_ms();
  var i: Int = 0;
  while i < iters {
    let a = i % vecs.len();
    let b = (i + 1) % vecs.len();
    if kind < 0 {
      checksum = checksum + vector_distance(&vecs[a], &vecs[b], DistanceMetric.Euclidean);
    } else {
      kernels.kernels_install(kind);
      checksum = checksum + kernels.kernels_distance(&vecs[a], &vecs[b], DistanceMetric.Euclidean);
    }
    i = i + 1;
  }
  let t1 = time.monotonic_ms();
  return Bench{ ms: t1 - t0, checksum: checksum };
}

fn bench_local(vecs: &Vec[Vector], use_alt: Int, iters: Int) -> Bench {
  let alt = use_alt == 1;
  var checksum: Float32 = 0.0;
  let t0 = time.monotonic_ms();
  var i: Int = 0;
  while i < iters {
    let a = i % vecs.len();
    let b = (i + 1) % vecs.len();
    var d: Float32 = 0.0;
    if alt {
      d = kernels.kernels_alt_distance(&vecs[a], &vecs[b], DistanceMetric.Euclidean);
    } else {
      d = vector_distance(&vecs[a], &vecs[b], DistanceMetric.Euclidean);
    }
    checksum = checksum + d;
    i = i + 1;
  }
  let t1 = time.monotonic_ms();
  return Bench{ ms: t1 - t0, checksum: checksum };
}

fn report(dim: Int, kind_name: Str, r: Bench, iters: Int) {
  let ns = (r.ms as Float64) * 1000000.0 / (iters as Float64);
  io.println("    " + kind_name + " dim=" + int_to_str(dim) + " ms=" + int_to_str(r.ms)
    + " ns/op=" + convert.float_to_string(ns) + " checksum=" + convert.float_to_string(r.checksum as Float64));
}

fn main() -> Int {
  io.println("=== xvector probe: P3 kernel seam (scalar vs unrolled) ===");
  var fails: Int = 0;

  let v128 = make_vectors(8, 128);
  let v768 = make_vectors(8, 768);

  // Bit-identical: kind 0 (default) and kind 1 against the scalar contract.
  kernels.kernels_install(0);
  fails = check(kernels.kernels_kind() == 0, "switch: default is the scalar kind", fails);
  kernels.kernels_install(1);
  fails = check(kernels.kernels_kind() == 1, "switch: install kind 1", fails);

  var eq: Bool = true;
  var pairs: Int = 0;
  var i: Int = 0;
  while i < 80 {
    let a = i % v128.len();
    let b = (i + 3) % v128.len();
    if vector_dot(&v128[a], &v128[b]) != kernels.kernels_dot(&v128[a], &v128[b]) { eq = false; }
    if vector_magnitude(&v128[a]) != kernels.kernels_magnitude(&v128[a]) { eq = false; }
    if vector_distance(&v128[a], &v128[b], DistanceMetric.Cosine) != kernels.kernels_distance(&v128[a], &v128[b], DistanceMetric.Cosine) { eq = false; }
    if vector_distance(&v128[a], &v128[b], DistanceMetric.DotProduct) != kernels.kernels_distance(&v128[a], &v128[b], DistanceMetric.DotProduct) { eq = false; }
    if vector_distance(&v128[a], &v128[b], DistanceMetric.Euclidean) != kernels.kernels_distance(&v128[a], &v128[b], DistanceMetric.Euclidean) { eq = false; }
    pairs = pairs + 1;
    i = i + 1;
  }
  fails = check(eq, "bit-identical: dot/magnitude/distance (3 metrics) x " + int_to_str(pairs) + " pairs", fails);

  kernels.kernels_install(0);
  var eq0: Bool = true;
  i = 0;
  while i < 40 {
    let a = i % v128.len();
    let b = (i + 5) % v128.len();
    if vector_distance(&v128[a], &v128[b], DistanceMetric.Euclidean) != kernels.kernels_distance(&v128[a], &v128[b], DistanceMetric.Euclidean) { eq0 = false; }
    i = i + 1;
  }
  fails = check(eq0 && kernels.kernels_kind() == 0, "restore: kind 0 stays bit-identical to the contract", fails);

  // Bounded microbenchmark (speed recorded, never asserted).
  io.println("  kernel microbench (Euclidean):");
  report(128, "direct  ", bench_dim(&v128, -1, 200000), 200000);
  report(128, "local-s ", bench_local(&v128, 0, 200000), 200000);
  report(128, "local-a ", bench_local(&v128, 1, 200000), 200000);
  report(128, "scalar  ", bench_dim(&v128, 0, 200000), 200000);
  report(128, "unrolled", bench_dim(&v128, 1, 200000), 200000);
  report(768, "direct  ", bench_dim(&v768, -1, 50000), 50000);
  report(768, "local-s ", bench_local(&v768, 0, 50000), 50000);
  report(768, "local-a ", bench_local(&v768, 1, 50000), 50000);
  report(768, "scalar  ", bench_dim(&v768, 0, 50000), 50000);
  report(768, "unrolled", bench_dim(&v768, 1, 50000), 50000);
  kernels.kernels_install(0);

  io.println("");
  io.println("probe_kernels: " + int_to_str(fails) + " failed checks");
  return fails;
}
