// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XVC-C-22 repro (compiler v0.64.8): the SECOND call to `pq_train` (a
// function returning Option[PQ], PQ has a Vec[Float32] field) crashes with
// 0xC0000005; the first call succeeds. The same program with one call is
// green; `ivf_pq_build` (one internal pq_train) also returns a corrupted
// nested codebook in the P4 probe (checksum changes between runs and the
// reconstruction error explodes), so the P4 IVF-PQ prototype is blocked.
//
// Build:
//   .\scripts\build.ps1 docs\repro\xv-pq-second-call\probe.xi -Name repro_pq_second_call
//   .\out\repro_pq_second_call.exe
// Expected (bug): prints "first ok", then crashes (exit -1073741819) before
// "second ok". Fixed compiler: prints both and exits 0.

module repro_pq_second_call

use xiom.io;
use xiom.convert;
use xiom.vector.primitives;

pub type PQ = {
  m: Int;
  dsub: Int;
  ksub: Int;
  dim: Int;
  centroids: Vec[Float32];
}

fn slice_dist(v: &Vector, base: Int, cents: &Vec[Float32], cbase: Int, dsub: Int) -> Float32 {
  var s: Float32 = 0.0;
  var j: Int = 0;
  while j < dsub {
    var d = v.data[base + j] - cents[cbase + j];
    s = s + d * d;
    j = j + 1;
  }
  return s;
}

fn kmeans_centroids(vectors: &Vec[Vector], base: Int, dsub: Int, ksub: Int, iters: Int, seed: Int) -> Vec[Float32] {
  var cents = Vec[Float32].new();
  let n = vectors.len();
  if n == 0 || ksub <= 0 || dsub <= 0 || ksub > n { return cents; }
  let stride = n / ksub;
  var k: Int = 0;
  while k < ksub {
    var src = (seed + k * stride) % n;
    if src < 0 { src = 0; }
    var j: Int = 0;
    while j < dsub { cents.push(vectors[src].data[base + j]); j = j + 1; }
    k = k + 1;
  }
  var it: Int = 0;
  while it < iters {
    var sums = Vec[Float32].new();
    var counts = Vec[Int].new();
    var q: Int = 0;
    while q < ksub * dsub { sums.push(0.0); q = q + 1; }
    q = 0;
    while q < ksub { counts.push(0); q = q + 1; }
    var i: Int = 0;
    while i < n {
      var best: Int = 0;
      var best_d = slice_dist(&vectors[i], base, &cents, 0, dsub);
      var c: Int = 1;
      while c < ksub {
        var d = slice_dist(&vectors[i], base, &cents, c * dsub, dsub);
        if d < best_d { best_d = d; best = c; }
        c = c + 1;
      }
      var j: Int = 0;
      while j < dsub {
        var slot = best * dsub + j;
        sums[slot] = sums[slot] + vectors[i].data[base + j];
        j = j + 1;
      }
      counts[best] = counts[best] + 1;
      i = i + 1;
    }
    var c2: Int = 0;
    while c2 < ksub {
      if counts[c2] > 0 {
        var j2: Int = 0;
        while j2 < dsub {
          cents[c2 * dsub + j2] = sums[c2 * dsub + j2] / (counts[c2] as Float32);
          j2 = j2 + 1;
        }
      }
      c2 = c2 + 1;
    }
    it = it + 1;
  }
  return cents;
}

fn pq_train(vectors: &Vec[Vector], m: Int, ksub: Int, iters: Int, seed: Int) -> Option[PQ] {
  if vectors.len() == 0 || m <= 0 || ksub <= 0 || ksub > vectors.len() { return None; }
  let dim = vectors[0].dimension;
  if dim <= 0 || dim % m != 0 { return None; }
  let dsub = dim / m;
  var cents = Vec[Float32].new();
  var s: Int = 0;
  while s < m {
    let part = kmeans_centroids(vectors, s * dsub, dsub, ksub, iters, seed + s);
    var j: Int = 0;
    while j < part.len() { cents.push(part[j]); j = j + 1; }
    s = s + 1;
  }
  return Some(PQ{ m: m, dsub: dsub, ksub: ksub, dim: dim, centroids: cents });
}

fn lcg_next(state: &mut Int) -> Float32 {
  state = (state * 1103515245 + 12345) % 2147483647;
  if state < 0 { state = 0 - state; }
  return (state as Float32) / 2147483647.0;
}

fn main() -> Int {
  var vs = Vec[Vector].new();
  var state: Int = 4242;
  var i: Int = 0;
  while i < 2000 {
    var v = Vector.new(32);
    var d: Int = 0;
    while d < 32 { v.set(d, lcg_next(&mut state)); d = d + 1; }
    vs.push(v);
    i = i + 1;
  }
  io.println("built " + convert.int_to_string(vs.len()));
  io.flush_stdout();
  match pq_train(&vs, 8, 16, 8, 42) {
    Some(a) => {
      io.println("first ok m=" + convert.int_to_string(a.m));
      io.flush_stdout();
      match pq_train(&vs, 8, 16, 8, 42) {
        Some(b) => { io.println("second ok m=" + convert.int_to_string(b.m)); io.flush_stdout(); }
        None => { io.println("second none"); }
      }
    }
    None => { io.println("first none"); }
  }
  return 0;
}
