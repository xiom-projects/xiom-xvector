// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Q-a2b gate: sealed Flat segments with SQ codes are read through the
// quantized coarse scan + exact f32 rescore, and the union result is
// bit-identical to the pre-seal exact top-k. The segment is produced by the
// real roll path (`engine_roll_segment` trains and arms SQ when possible).
//
// Exit = failed checks.

module probe_sq_sealed

use xiom.io;
use xiom.convert;
use xiom.vector.primitives;
use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.query.search_service;

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

// Deterministic corpus (same style as probe_quantization; no RNG dep).
fn lcg_next(state: &mut Int) -> Float32 {
  state = (state * 1103515245 + 12345) % 2147483647;
  if state < 0 { state = 0 - state; }
  return (state as Float32) / 2147483647.0;
}

fn main() -> Int {
  io.println("=== xvector probe: sealed SQ8 read path (Q-a2b) ===");
  var fails: Int = 0;
  let pa = "out/probe_sq_sealed.seg";
  let _r0 = io.remove_file(pa);
  let _r1 = io.remove_file("out/sealed-1-1.seg");

  var eng = engine_new();
  match engine_create_named(&mut eng, "sq", 8, DistanceMetric.Euclidean) {
    Ok(_) => {}
    Err(e) => { io.println("  [FAIL] create: " + e.msg); return 2; }
  }

  var state: Int = 12345;
  var corpus = Vec[Vector].new();
  var i: Int = 0;
  while i < 200 {
    var v = Vector.new(8);
    var d: Int = 0;
    while d < 8 {
      v.set(d, lcg_next(&mut state));
      d = d + 1;
    }
    corpus.push(v);
    match engine_upsert(&mut eng, i + 1, v) {
      Ok(_) => {}
      Err(e) => { io.println("  [FAIL] upsert " + int_to_str(i + 1) + ": " + e.msg); fails = fails + 1; }
    }
    i = i + 1;
  }
  fails = check(engine_size(&eng) == 200, "setup: 200 active points", fails);

  var before = Vec[SearchResult].new();
  var qi: Int = 0;
  while qi < 10 {
    match engine_search(&eng, &corpus[qi], 10) {
      Ok(h) => {
        var j: Int = 0;
        while j < h.items.len() {
          before.push(SearchResult{ id: h.items[j].id, distance: h.items[j].distance });
          j = j + 1;
        }
      }
      Err(e) => { io.println("  [FAIL] pre-seal search: " + e.msg); fails = fails + 1; }
    }
    qi = qi + 1;
  }
  fails = check(before.len() == 100, "setup: 10 exact pre-seal queries x top-10", fails);

  match engine_roll_segment(&mut eng, pa) {
    Ok(_) => {}
    Err(e) => { io.println("  [FAIL] roll: " + e.msg); return 2; }
  }

  var has_sq: Bool = false;
  var sealed_points: Int = 0;
  var si: Int = 0;
  while si < eng.sealed.len() {
    if eng.sealed[si].has_sq { has_sq = true; }
    sealed_points = sealed_points + eng.sealed[si].points;
    si = si + 1;
  }
  fails = check(has_sq, "seal: the rolled segment carries SQ codes", fails);
  fails = check(sealed_points == 200, "seal: 200 points in the sealed segment", fails);
  fails = check(engine_size(&eng) == 0, "seal: active store cleared", fails);

  var after = Vec[SearchResult].new();
  qi = 0;
  while qi < 10 {
    match engine_search(&eng, &corpus[qi], 10) {
      Ok(h) => {
        var j: Int = 0;
        while j < h.items.len() {
          after.push(SearchResult{ id: h.items[j].id, distance: h.items[j].distance });
          j = j + 1;
        }
      }
      Err(e) => { io.println("  [FAIL] post-seal search: " + e.msg); fails = fails + 1; }
    }
    qi = qi + 1;
  }

  var equal: Bool = before.len() == after.len() && before.len() > 0;
  var k: Int = 0;
  while k < before.len() && k < after.len() {
    if before[k].id != after[k].id || before[k].distance != after[k].distance { equal = false; }
    k = k + 1;
  }
  fails = check(equal, "union: sealed SQ rescore is bit-identical to the pre-seal exact top-10 (10 queries)", fails);

  let _c0 = io.remove_file(pa);
  let _c1 = io.remove_file("out/sealed-1-1.seg");
  io.println("");
  io.println("probe_sq_sealed: " + int_to_str(fails) + " failed checks");
  return fails;
}
