// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: engine-level HNSW wiring on the REAL modules. Builds two engines
// with identical data (flat oracle vs Hnsw), then verifies: set_index
// builds the graph from the store, engine_search routes through it with
// recall vs the oracle, deletes/revives propagate, filtered search stays
// exact on an Hnsw collection, set_index(Flat) restores exactness, invalid
// params are rejected, and a recovered engine (flat store replayed from the
// WAL) can re-apply the Hnsw index. Exit = failed checks.

module probe_engine_hnsw

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.index.ann_index;
use xiom.vector.index.hnsw;
use xiom.vector.query.search_service;
use xiom.vector.types.dense_vector;
use xiom.vector.types.metric;
use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;
use xiom.io;
use xiom.num.float;

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n; var out = ""; var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  while num > 0 {
    let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10;
  }
  if neg { out = "-" + out; }
  return out;
}

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn lcg_next(s: Int) -> Int {
  return (s * 1103515245 + 12345) % 2147483648;
}

fn rand_coords(state: Int, dim: Int, coords: &mut Vec[Float32]) -> Int {
  var s = state;
  var i: Int = 0;
  while i < dim {
    s = lcg_next(s);
    var c = (s % 4001) as Float32;
    coords.push(c / 1000.0 - 2.0);
    i = i + 1;
  }
  return s;
}

fn vec_from_coords(coords: &Vec[Float32]) -> Vector {
  var v = Vector.new(coords.len());
  var i: Int = 0;
  while i < coords.len() {
    v.set(i, coords[i]);
    i = i + 1;
  }
  return v;
}

fn eng_search(eng: &VectorEngine, q: &Vector, k: Int) -> Vec[SearchResult] {
  match search(eng, q, k) {
    Ok(h) => { return h.items; }
    Err(_) => { return Vec[SearchResult].new(); }
  }
}

fn eng_search_filtered(eng: &VectorEngine, q: &Vector, k: Int, f: &FilterExpr) -> Vec[SearchResult] {
  match search_filtered(eng, q, k, f) {
    Ok(h) => { return h.items; }
    Err(_) => { return Vec[SearchResult].new(); }
  }
}

fn hit_count(oracle: &Vec[SearchResult], approx: &Vec[SearchResult], k: Int) -> Int {
  var hits: Int = 0;
  var i: Int = 0;
  while i < oracle.len() {
    var found: Bool = false;
    var j: Int = 0;
    while j < approx.len() && !found {
      if approx[j].id == oracle[i].id {
        found = true;
        hits = hits + 1;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return hits;
}

fn results_equal(a: &Vec[SearchResult], b: &Vec[SearchResult]) -> Bool {
  if a.len() != b.len() { return false; }
  var i: Int = 0;
  while i < a.len() {
    if a[i].id != b[i].id { return false; }
    if float.float_bits(a[i].distance as Float64) != float.float_bits(b[i].distance as Float64) { return false; }
    i = i + 1;
  }
  return true;
}

fn main() -> Int {
  io.println("=== xvector probe: engine HNSW wiring ===");
  var fails: Int = 0;

  var dim: Int = 8;
  var n: Int = 150;
  var k: Int = 10;
  var qn: Int = 20;

  var flat = engine_new();
  create_collection(&mut flat, dim, DistanceMetric.Euclidean);
  var ann = engine_new();
  create_collection(&mut ann, dim, DistanceMetric.Euclidean);

  var state: Int = 777333111;
  var i: Int = 0;
  while i < n {
    var c = Vec[Float32].new();
    state = rand_coords(state, dim, &mut c);
    var v1 = vec_from_coords(&c);
    var v2 = vec_from_coords(&c);
    upsert(&mut flat, i + 1, v1);
    upsert(&mut ann, i + 1, v2);
    i = i + 1;
  }
  fails = check(engine_size(&flat) == n && engine_size(&ann) == n, "two engines hold 150 points each", fails);

  var params = ann_params_default();
  match set_index(&mut ann, AnnIndexKind.Hnsw, params) {
    Ok(ok) => { fails = check(ok && hnsw_size(&ann.graph) == n, "set_index(Hnsw): graph built from store (150 nodes)", fails); }
    Err(_) => { fails = check(false, "set_index(Hnsw) -> Ok", fails); }
  }
  // --- recall vs the flat oracle (engine surface) ---
  var hits: Int = 0;
  var q: Int = 0;
  while q < qn {
    var c = Vec[Float32].new();
    state = rand_coords(state, dim, &mut c);
    var qv = vec_from_coords(&c);
    var o = eng_search(&flat, &qv, k);
    var a = eng_search(&ann, &qv, k);
    hits = hits + hit_count(&o, &a, k);
    q = q + 1;
  }
  io.println("    diag engine recall@10 (Hnsw vs flat): " + int_to_str(hits) + "/" + int_to_str(qn * k));
  fails = check(hits * 100 >= qn * k * 80, "engine Hnsw recall@10 >= 0.80", fails);

  // Params flow: a low ef_construction build must still work end-to-end.
  match set_index(&mut ann, AnnIndexKind.Hnsw, AnnParams{ m: 16, ef_construction: 32, ef_search: 64 }) {
    Ok(_) => {}
    Err(_) => { fails = fails + 1; }
  }
  fails = check(ann.graph.ef_construction == 32, "set_index honours ef_construction=32", fails);
  var hits32: Int = 0;
  q = 0;
  while q < 5 {
    var c32 = Vec[Float32].new();
    state = rand_coords(state, dim, &mut c32);
    var qv32 = vec_from_coords(&c32);
    var o32 = eng_search(&flat, &qv32, k);
    var a32 = eng_search(&ann, &qv32, k);
    hits32 = hits32 + hit_count(&o32, &a32, k);
    q = q + 1;
  }
  fails = check(hits32 * 100 >= 5 * k * 80, "ef_construction=32 build recall@10 >= 0.80", fails);

  // --- deletes propagate into the graph ---
  match delete_point(&mut ann, 7) { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  match delete_point(&mut flat, 7) { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  var stray: Int = 0;
  var hits_del: Int = 0;
  q = 0;
  while q < 10 {
    var c = Vec[Float32].new();
    state = rand_coords(state, dim, &mut c);
    var qv = vec_from_coords(&c);
    var o = eng_search(&flat, &qv, k);
    var a = eng_search(&ann, &qv, k);
    var t: Int = 0;
    while t < a.len() {
      if a[t].id == 7 { stray = stray + 1; }
      t = t + 1;
    }
    hits_del = hits_del + hit_count(&o, &a, k);
    q = q + 1;
  }
  fails = check(stray == 0, "deleted point 7 never returned by engine_search", fails);
  fails = check(hits_del * 100 >= 10 * k * 80, "recall holds after delete", fails);

  // --- re-upsert revives the tombstoned node ---
  var cr = Vec[Float32].new();
  state = rand_coords(state, dim, &mut cr);
  var vr1 = vec_from_coords(&cr);
  var vr2 = vec_from_coords(&cr);
  upsert(&mut ann, 7, vr1);
  upsert(&mut flat, 7, vr2);
  fails = check(hnsw_live_count(&ann.graph) == n, "re-upsert revives the graph node (live 150)", fails);

  // --- compaction via the facade ---
  match delete_point(&mut ann, 8) { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  match delete_point(&mut flat, 8) { Ok(_) => {} Err(_) => { fails = fails + 1; } }
  var reclaimed: Int = -1;
  match compact_index(&mut ann) {
    Ok(cnt) => { reclaimed = cnt; }
    Err(_) => { fails = fails + 1; }
  }
  fails = check(reclaimed == 1 && hnsw_size(&ann.graph) == n - 1 && hnsw_live_count(&ann.graph) == n - 1,
    "compact_index reclaims 1 node (graph 149, live 149)", fails);
  var hits_c2: Int = 0;
  q = 0;
  while q < 5 {
    var c = Vec[Float32].new();
    state = rand_coords(state, dim, &mut c);
    var qv = vec_from_coords(&c);
    var o = eng_search(&flat, &qv, k);
    var a = eng_search(&ann, &qv, k);
    hits_c2 = hits_c2 + hit_count(&o, &a, k);
    q = q + 1;
  }
  fails = check(hits_c2 * 100 >= 5 * k * 80, "post-compact engine recall@10 >= 0.80", fails);
  match compact_index(&mut flat) {
    Ok(z) => { fails = check(z == 0, "compact_index on Flat -> 0", fails); }
    Err(_) => { fails = fails + 1; }
  }

  // --- filtered search stays exact on an Hnsw collection ---
  i = 1;
  while i <= 5 {
    var p1 = payload_new();
    payload_set(&mut p1, "g", FieldValue.IntVal(i));
    var p2 = payload_new();
    payload_set(&mut p2, "g", FieldValue.IntVal(i));
    set_payload(&mut flat, i, p1);
    set_payload(&mut ann, i, p2);
    i = i + 1;
  }
  var cq = Vec[Float32].new();
  state = rand_coords(state, dim, &mut cq);
  var fq = vec_from_coords(&cq);
  var f = filter_eq("g", FieldValue.IntVal(3));
  var fr = eng_search_filtered(&flat, &fq, 3, &f);
  var fa = eng_search_filtered(&ann, &fq, 3, &f);
  fails = check(fr.len() == 1 && fr[0].id == 3 && results_equal(&fr, &fa),
    "filtered search exact on Hnsw collection ({3})", fails);

  // --- switching back to Flat restores exactness ---
  match set_index(&mut ann, AnnIndexKind.Flat, ann_params_default()) {
    Ok(_) => {}
    Err(_) => { fails = fails + 1; }
  }
  var cq2 = Vec[Float32].new();
  state = rand_coords(state, dim, &mut cq2);
  var fq2 = vec_from_coords(&cq2);
  fails = check(results_equal(&eng_search(&flat, &fq2, k), &eng_search(&ann, &fq2, k)),
    "set_index(Flat): engine results bit-identical to oracle", fails);

  // --- invalid params rejected ---
  var bad = AnnParams{ m: 0, ef_construction: 200, ef_search: 64 };
  match set_index(&mut ann, AnnIndexKind.Hnsw, bad) {
    Ok(_) => { fails = check(false, "set_index(m=0) -> Err", fails); }
    Err(_) => { fails = check(true, "set_index(m=0) -> Err", fails); }
  }

  // --- recover rebuilds the flat store; Hnsw re-applies ---
  var rec = engine_recover(&ann.wal, dim, DistanceMetric.Euclidean);
  fails = check(engine_size(&rec) == n - 1, "engine_recover rebuilds the store (149, point 8 deleted)", fails);
  match set_index(&mut rec, AnnIndexKind.Hnsw, ann_params_default()) {
    Ok(ok) => { fails = check(ok && hnsw_size(&rec.graph) == n - 1, "recovered engine re-applies Hnsw (graph 149)", fails); }
    Err(_) => { fails = check(false, "recovered set_index(Hnsw) -> Ok", fails); }
  }
  var hits_rec: Int = 0;
  q = 0;
  while q < 5 {
    var c = Vec[Float32].new();
    state = rand_coords(state, dim, &mut c);
    var qv = vec_from_coords(&c);
    var o = eng_search(&flat, &qv, k);
    var a = eng_search(&rec, &qv, k);
    hits_rec = hits_rec + hit_count(&o, &a, k);
    q = q + 1;
  }
  fails = check(hits_rec * 100 >= 5 * k * 80, "recovered Hnsw engine recall@10 >= 0.80", fails);

  io.println("");
  io.println("probe_engine_hnsw: " + int_to_str(fails) + " failed checks");
  return fails;
}
